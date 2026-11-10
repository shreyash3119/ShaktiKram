import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/db/local_store.dart';
import 'package:shaktikram/core/db/sync_models.dart';

String uid(int n) => '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

PulledRow pulled(String entity, int rev, Map<String, dynamic> record) => PulledRow(entity: entity, rev: rev, record: record);

OutboxOp op(String opId, String entity, String id, Map<String, dynamic> payload, {String action = 'upsert'}) => OutboxOp(
      opId: opId,
      entity: entity,
      action: action,
      recordId: id,
      clientUpdatedAt: DateTime.utc(2026, 11, 10, 9),
      payload: payload,
    );

/// The rules every [LocalStore] must follow. Run against the in-memory store in `flutter test` and against SQLite on a
/// phone in `integration_test`.
void runStoreContract(String name, Future<LocalStore> Function() create) {
  group('LocalStore contract: $name', () {
    late LocalStore store;
    setUp(() async => store = await create());

    test('pulled records can be read back, by id and as a list', () async {
      await store.applyPulled([
        pulled('exercises', 2, {'id': uid(1), 'name': 'Bench Press'}),
        pulled('exercises', 3, {'id': uid(2), 'name': 'Squat'}),
        pulled('muscles', 4, {'id': uid(3), 'name': 'Chest'}),
      ], 4);
      expect((await store.get('exercises', uid(1)))!['name'], 'Bench Press');
      expect(await store.get('exercises', uid(3)), isNull);
      expect(await store.list('exercises'), hasLength(2));
      expect(await store.list('muscles'), hasLength(1));
      expect(await store.recordCount(), 3);
      expect(await store.lastRev(), 4);
    });

    test('lists are newest first, can be limited and can be cut to one day', () async {
      await store.applyPulled([
        pulled('body_measurements', 2, {'id': uid(1), 'occurred_at': '2026-11-08T07:00:00Z', 'local_date': '2026-11-08', 'value': 1}),
        pulled('body_measurements', 3, {'id': uid(2), 'occurred_at': '2026-11-10T07:00:00Z', 'local_date': '2026-11-10', 'value': 3}),
        pulled('body_measurements', 4, {'id': uid(3), 'occurred_at': '2026-11-09T07:00:00Z', 'local_date': '2026-11-09', 'value': 2}),
      ], 4);
      expect((await store.list('body_measurements')).map((r) => r['value']), [3, 2, 1]);
      expect((await store.list('body_measurements', limit: 2)).map((r) => r['value']), [3, 2]);
      expect((await store.list('body_measurements', localDate: '2026-11-09')).map((r) => r['value']), [2]);
    });

    test('soft-deleted records are hidden unless asked for', () async {
      await store.applyPulled([
        pulled('goals', 2, {'id': uid(1), 'deleted_at': '2026-11-09T00:00:00Z'}),
        pulled('goals', 3, {'id': uid(2)}),
      ], 3);
      expect((await store.list('goals')).map((r) => r['id']), [uid(2)]);
      expect(await store.list('goals', includeDeleted: true), hasLength(2));
      expect(await store.recordCount(), 1);
    });

    test('records are found by the records they link to', () async {
      await store.applyPulled([
        pulled('sets', 2, {'id': uid(1), 'session_exercise_id': uid(100), 'occurred_at': '2026-11-10T07:00:00Z'}),
        pulled('sets', 3, {'id': uid(2), 'session_exercise_id': uid(100), 'occurred_at': '2026-11-10T07:05:00Z'}),
        pulled('sets', 4, {'id': uid(3), 'session_exercise_id': uid(101), 'occurred_at': '2026-11-10T07:10:00Z'}),
      ], 4);
      final found = await store.listByRef('sets', 'session_exercise_id', uid(100));
      expect(found.map((r) => r['id']), [uid(2), uid(1)]);
      expect(await store.listByRef('sets', 'session_exercise_id', uid(999)), isEmpty);
      expect(await store.listByRef('sets', 'session_id', uid(100)), isEmpty);
    });

    test('a record that moves to another parent is found under the new one only', () async {
      await store.applyPulled([pulled('session_exercises', 2, {'id': uid(1), 'session_id': uid(100)})], 2);
      await store.applyPulled([pulled('session_exercises', 5, {'id': uid(1), 'session_id': uid(101)})], 5);
      expect(await store.listByRef('session_exercises', 'session_id', uid(100)), isEmpty);
      expect(await store.listByRef('session_exercises', 'session_id', uid(101)), hasLength(1));
    });

    test('deleted children are hidden from link lookups unless asked for', () async {
      await store.applyPulled([
        pulled('sets', 2, {'id': uid(1), 'session_exercise_id': uid(100), 'deleted_at': '2026-11-10T00:00:00Z'}),
        pulled('sets', 3, {'id': uid(2), 'session_exercise_id': uid(100)}),
      ], 3);
      expect(await store.listByRef('sets', 'session_exercise_id', uid(100)), hasLength(1));
      expect(await store.listByRef('sets', 'session_exercise_id', uid(100), includeDeleted: true), hasLength(2));
    });

    test('a local save shows at once, is queued with the last known revision, and keeps its order number', () async {
      await store.applyPulled([pulled('goals', 7, {'id': uid(1), 'title': 'Cut'})], 7);
      final saved = await store.saveLocal(op('op-1', 'goals', uid(1), {'id': uid(1), 'title': 'Cut to 75'}));
      expect(saved.baseRev, 7);
      expect(saved.seq, isNotNull);
      expect((await store.get('goals', uid(1)))!['title'], 'Cut to 75');
      expect(await store.pendingCount(), 1);
      final second = await store.saveLocal(op('op-2', 'goals', uid(2), {'id': uid(2), 'title': 'New'}));
      expect(second.seq! > saved.seq!, isTrue);
      expect(second.baseRev, isNull);
      expect((await store.pendingOps()).map((o) => o.opId), ['op-1', 'op-2']);
      expect((await store.pendingOps(afterSeq: saved.seq!)).map((o) => o.opId), ['op-2']);
    });

    test('a pull does not overwrite an unsent local edit, and ignores older revisions', () async {
      await store.applyPulled([pulled('goals', 5, {'id': uid(1), 'title': 'Server'})], 5);
      await store.saveLocal(op('op-1', 'goals', uid(1), {'id': uid(1), 'title': 'Mine'}));
      await store.applyPulled([pulled('goals', 6, {'id': uid(1), 'title': 'Server 2'})], 6);
      expect((await store.get('goals', uid(1)))!['title'], 'Mine');
      await store.applyPulled([pulled('goals', 2, {'id': uid(1), 'title': 'Old'})], 6);
      expect((await store.get('goals', uid(1)))!['title'], 'Mine');
    });

    test('applied: the change leaves the queue and the next edit uses the new revision', () async {
      final saved = await store.saveLocal(op('op-1', 'goals', uid(1), {'id': uid(1), 'title': 'A'}));
      await store.recordResult(saved, const OpResult(opId: 'op-1', result: 'applied', rev: 9));
      expect(await store.pendingCount(), 0);
      final next = await store.saveLocal(op('op-2', 'goals', uid(1), {'id': uid(1), 'title': 'B'}));
      expect(next.baseRev, 9);
    });

    test('a pending second edit takes the revision the first one received', () async {
      final first = await store.saveLocal(op('op-1', 'goals', uid(1), {'id': uid(1), 'title': 'A'}));
      await store.saveLocal(op('op-2', 'goals', uid(1), {'id': uid(1), 'title': 'B'}));
      await store.recordResult(first, const OpResult(opId: 'op-1', result: 'applied', rev: 4));
      expect((await store.pendingOps()).single.baseRev, 4);
    });

    test('rejected: kept as an issue, a never-synced record disappears, a synced one returns to the server copy', () async {
      final created = await store.saveLocal(op('op-1', 'goals', uid(1), {'id': uid(1), 'title': 'A'}));
      await store.recordResult(created, const OpResult(opId: 'op-1', result: 'rejected', errorCode: 'validation_failed', message: 'no'));
      expect(await store.get('goals', uid(1)), isNull);
      expect(await store.issueCount(), 1);
      expect((await store.issues()).single.state, OpState.rejected);

      await store.applyPulled([pulled('goals', 5, {'id': uid(2), 'title': 'Server'})], 5);
      final edit = await store.saveLocal(op('op-2', 'goals', uid(2), {'id': uid(2), 'title': 'Mine'}));
      await store.recordResult(edit, const OpResult(opId: 'op-2', result: 'rejected', errorCode: 'validation_failed'));
      expect((await store.get('goals', uid(2)))!['title'], 'Server');

      await store.dismissIssue('op-1');
      expect(await store.issueCount(), 1);
    });

    test('conflict: the server copy comes back and the change is kept as an issue', () async {
      await store.applyPulled([pulled('goals', 5, {'id': uid(1), 'title': 'Server'})], 5);
      final edit = await store.saveLocal(op('op-1', 'goals', uid(1), {'id': uid(1), 'title': 'Mine'}));
      await store.recordResult(edit, const OpResult(opId: 'op-1', result: 'conflict', errorCode: 'conflict_stale_rev'));
      expect((await store.get('goals', uid(1)))!['title'], 'Server');
      expect((await store.issues()).single.state, OpState.conflict);
    });

    test('reference_missing stays queued until the retry limit', () async {
      var current = await store.saveLocal(op('op-1', 'goals', uid(1), {'id': uid(1)}));
      for (var i = 0; i < 4; i++) {
        await store.recordResult(current, const OpResult(opId: 'op-1', result: 'rejected', errorCode: 'reference_missing'));
        current = (await store.pendingOps()).single;
      }
      expect(current.attempts, 4);
      await store.recordResult(current, const OpResult(opId: 'op-1', result: 'rejected', errorCode: 'reference_missing'));
      expect(await store.pendingCount(), 0);
      expect(await store.issueCount(), 1);
    });

    test('the pull cursor and last sync time are kept', () async {
      expect(await store.lastRev(), 0);
      expect(await store.lastSyncAt(), isNull);
      await store.applyPulled([pulled('goals', 12, {'id': uid(1)})], 12);
      final when = DateTime.utc(2026, 11, 10, 9, 30);
      await store.setLastSyncAt(when);
      expect(await store.lastRev(), 12);
      expect((await store.lastSyncAt())!.toUtc(), when);
    });
  });
}
