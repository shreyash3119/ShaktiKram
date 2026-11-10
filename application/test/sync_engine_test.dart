import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/db/sync_models.dart';
import 'package:shaktikram/core/sync/sync_engine.dart';

import 'support/fakes.dart';
import 'support/memory_local_store.dart';

OutboxOp _create(
  String id, {
  String entity = 'body_measurements',
  Map<String, dynamic>? payload,
}) => OutboxOp(
  opId: 'op-$id',
  entity: entity,
  action: 'upsert',
  recordId: id,
  clientUpdatedAt: DateTime.utc(2026, 11, 8, 7),
  payload: payload ?? {'id': id, 'measurement_type': 'weight', 'value': 78.0},
);

OutboxOp _edit(String id, String opId, double value) => OutboxOp(
  opId: opId,
  entity: 'body_measurements',
  action: 'upsert',
  recordId: id,
  clientUpdatedAt: DateTime.utc(2026, 11, 8, 8),
  payload: {'id': id, 'value': value},
);

void main() {
  late MemoryLocalStore store;
  late FakeGateway gateway;
  late SyncEngine engine;

  setUp(() {
    store = MemoryLocalStore();
    gateway = FakeGateway();
    engine = SyncEngine(
      store: store,
      gateway: gateway,
      deviceId: () => 'device-1',
    );
  });

  test('a saved change shows locally at once and is queued', () async {
    await store.saveLocal(_create('a'));
    expect((await store.get('body_measurements', 'a'))!['value'], 78.0);
    expect(await store.pendingCount(), 1);
    final op = (await store.pendingOps()).single;
    expect(op.seq, 1);
    expect(op.baseRev, isNull);
    expect(op.toWire()['op_id'], 'op-a');
    expect(op.toWire().containsKey('base_rev'), isFalse);
  });

  test(
    'applied: the queue empties and the record keeps its revision',
    () async {
      await store.saveLocal(_create('a'));
      gateway.onApply =
          (op) => OpResult(opId: op.opId, result: 'applied', rev: 7);
      final report = await engine.syncOnce();
      expect(report.outcome, SyncOutcome.ok);
      expect(report.pushed, 1);
      expect(await store.pendingCount(), 0);
      expect(await store.lastSyncAt(), isNotNull);
      await store.saveLocal(_edit('a', 'op-a2', 79.0));
      expect((await store.pendingOps()).single.baseRev, 7);
    },
  );

  test(
    'two queued edits of one record: the second takes the first one\'s new revision',
    () async {
      await store.saveLocal(_create('a'));
      await store.saveLocal(_edit('a', 'op-a2', 79.0));
      gateway.onApply =
          (op) => OpResult(
            opId: op.opId,
            result: 'applied',
            rev: op.opId == 'op-a' ? 3 : 4,
          );
      await engine.syncOnce();
      expect(await store.pendingCount(), 0);
      expect((await store.get('body_measurements', 'a'))!['value'], 79.0);
    },
  );

  test('a replay of an operation that was applied counts as applied', () async {
    await store.saveLocal(_create('a'));
    gateway.onApply =
        (op) => OpResult(
          opId: op.opId,
          result: 'duplicate',
          originalResult: 'applied',
          rev: 4,
        );
    await engine.syncOnce();
    expect(await store.pendingCount(), 0);
    expect(await store.issueCount(), 0);
  });

  test('a replay of an operation that was rejected stays rejected', () async {
    await store.saveLocal(_create('a'));
    gateway.onApply =
        (op) => OpResult(
          opId: op.opId,
          result: 'duplicate',
          originalResult: 'rejected',
          errorCode: 'validation_failed',
        );
    await engine.syncOnce();
    expect(await store.pendingCount(), 0);
    expect((await store.issues()).single.errorCode, 'validation_failed');
  });

  test(
    'a duplicate that changed nothing is not success: it is kept as an issue',
    () async {
      await store.applyPulled([
        const PulledRow(
          entity: 'body_measurements',
          rev: 5,
          record: {'id': 'a', 'value': 80.0},
        ),
      ], 5);
      await store.saveLocal(_edit('a', 'op-a2', 70.0));
      gateway.onApply =
          (op) => OpResult(opId: op.opId, result: 'duplicate', rev: 5);
      await engine.syncOnce();
      final issue = (await store.issues()).single;
      expect(issue.errorCode, 'duplicate_ignored');
      expect(issue.state, OpState.rejected);
      expect((await store.get('body_measurements', 'a'))!['value'], 80.0);
    },
  );

  test(
    'create then edit before the first sync: the edit goes out after the create, with its revision',
    () async {
      await store.saveLocal(_create('a'));
      await store.saveLocal(_edit('a', 'op-a2', 79.0));
      gateway.onApply =
          (op) => OpResult(
            opId: op.opId,
            result: 'applied',
            rev: op.opId == 'op-a' ? 3 : 4,
          );
      await engine.syncOnce();
      expect(gateway.sentBatches.length, 2);
      expect(gateway.sentBatches[0].map((o) => o.opId), ['op-a']);
      expect(gateway.sentBatches[1].single.opId, 'op-a2');
      expect(gateway.sentBatches[1].single.baseRev, 3);
      expect(await store.pendingCount(), 0);
    },
  );

  test('an edit waits while the create before it is being retried', () async {
    await store.saveLocal(_create('a'));
    await store.saveLocal(_edit('a', 'op-a2', 79.0));
    gateway.onApply =
        (op) => OpResult(
          opId: op.opId,
          result: 'rejected',
          errorCode: 'reference_missing',
        );
    await engine.syncOnce();
    expect(gateway.sentBatches.expand((b) => b).map((o) => o.opId), ['op-a']);
    expect(await store.pendingCount(), 2);
  });

  test('operations of different records go out together', () async {
    await store.saveLocal(_create('a'));
    await store.saveLocal(_create('b'));
    await engine.syncOnce();
    expect(gateway.sentBatches.length, 1);
    expect(gateway.sentBatches.single, hasLength(2));
  });

  test(
    'rejected: kept as an issue and a never-synced record is removed',
    () async {
      await store.saveLocal(_create('a'));
      gateway.onApply =
          (op) => OpResult(
            opId: op.opId,
            result: 'rejected',
            errorCode: 'validation_failed',
            message: 'bad value',
          );
      await engine.syncOnce();
      expect(await store.pendingCount(), 0);
      expect(await store.issueCount(), 1);
      expect((await store.issues()).single.errorCode, 'validation_failed');
      expect(await store.get('body_measurements', 'a'), isNull);
      await store.dismissIssue('op-a');
      expect(await store.issueCount(), 0);
    },
  );

  test('conflict: the server copy comes back', () async {
    await store.applyPulled([
      const PulledRow(
        entity: 'body_measurements',
        rev: 5,
        record: {'id': 'a', 'value': 80.0},
      ),
    ], 5);
    await store.saveLocal(_edit('a', 'op-a2', 70.0));
    expect((await store.get('body_measurements', 'a'))!['value'], 70.0);
    gateway.onApply =
        (op) => OpResult(
          opId: op.opId,
          result: 'conflict',
          errorCode: 'conflict_stale_rev',
        );
    await engine.syncOnce();
    expect((await store.get('body_measurements', 'a'))!['value'], 80.0);
    expect((await store.issues()).single.state, OpState.conflict);
  });

  test(
    'reference_missing is retried, then given up after five tries',
    () async {
      await store.saveLocal(_create('a'));
      gateway.onApply =
          (op) => OpResult(
            opId: op.opId,
            result: 'rejected',
            errorCode: 'reference_missing',
          );
      for (var i = 0; i < 4; i++) {
        await engine.syncOnce();
        expect(await store.pendingCount(), 1, reason: 'try ${i + 1}');
      }
      await engine.syncOnce();
      expect(await store.pendingCount(), 0);
      expect(await store.issueCount(), 1);
    },
  );

  test('a retried operation is not sent twice in one round', () async {
    await store.saveLocal(_create('a'));
    gateway.onApply =
        (op) => OpResult(
          opId: op.opId,
          result: 'rejected',
          errorCode: 'reference_missing',
        );
    await engine.syncOnce();
    expect(gateway.sentBatches.length, 1);
  });

  test('offline: changes stay queued and nothing is lost', () async {
    await store.saveLocal(_create('a'));
    gateway.applyError = const BackendError.unreachable();
    final report = await engine.syncOnce();
    expect(report.outcome, SyncOutcome.offline);
    expect(await store.pendingCount(), 1);
    expect(await store.lastSyncAt(), isNull);
  });

  test('device_revoked is reported', () async {
    await store.saveLocal(_create('a'));
    gateway.applyError = const BackendError('device_revoked', 'removed');
    expect((await engine.syncOnce()).outcome, SyncOutcome.revoked);
  });

  test('other server errors keep the queue and report an error', () async {
    await store.saveLocal(_create('a'));
    gateway.applyError = const BackendError('internal_error', 'oops');
    final report = await engine.syncOnce();
    expect(report.outcome, SyncOutcome.error);
    expect(await store.pendingCount(), 1);
  });

  test('pull walks every page and stores the cursor', () async {
    gateway.pullPages.addAll([
      const PullPage(
        rows: [
          PulledRow(
            entity: 'body_measurements',
            rev: 2,
            record: {'id': 'x', 'value': 1.0},
          ),
          PulledRow(
            entity: 'body_measurements',
            rev: 3,
            record: {'id': 'y', 'value': 2.0},
          ),
        ],
        nextRev: 3,
        hasMore: true,
      ),
      const PullPage(
        rows: [
          PulledRow(
            entity: 'body_measurements',
            rev: 4,
            record: {'id': 'z', 'value': 3.0},
          ),
        ],
        nextRev: 4,
        hasMore: false,
      ),
    ]);
    final report = await engine.syncOnce();
    expect(report.pulled, 3);
    expect(gateway.pullSince, [0, 3]);
    expect(await store.lastRev(), 4);
    expect(await store.recordCount(), 3);
  });

  test(
    'pull does not overwrite an unsent local edit, and ignores older revisions',
    () async {
      await store.applyPulled([
        const PulledRow(
          entity: 'body_measurements',
          rev: 5,
          record: {'id': 'a', 'value': 80.0},
        ),
      ], 5);
      await store.saveLocal(_edit('a', 'op-a2', 70.0));
      await store.applyPulled([
        const PulledRow(
          entity: 'body_measurements',
          rev: 6,
          record: {'id': 'a', 'value': 81.0},
        ),
      ], 6);
      expect((await store.get('body_measurements', 'a'))!['value'], 70.0);
      await store.applyPulled([
        const PulledRow(
          entity: 'body_measurements',
          rev: 2,
          record: {'id': 'a', 'value': 1.0},
        ),
      ], 6);
      expect((await store.get('body_measurements', 'a'))!['value'], 70.0);
    },
  );

  test('a soft-deleted record is hidden from lists', () async {
    await store.applyPulled([
      const PulledRow(
        entity: 'body_measurements',
        rev: 2,
        record: {'id': 'a', 'value': 1.0, 'deleted_at': '2026-11-08T00:00:00Z'},
      ),
      const PulledRow(
        entity: 'body_measurements',
        rev: 3,
        record: {'id': 'b', 'value': 2.0},
      ),
    ], 3);
    expect((await store.list('body_measurements')).map((r) => r['id']), ['b']);
    expect(
      await store.list('body_measurements', includeDeleted: true),
      hasLength(2),
    );
  });

  test(
    'an unreadable server answer is a sync problem, not a crash, and keeps the queue',
    () async {
      await store.saveLocal(_create('a'));
      gateway.onApply = (op) => throw StateError('bad answer');
      final report = await engine.syncOnce();
      expect(report.outcome, SyncOutcome.error);
      expect(await store.pendingCount(), 1);
      gateway.onApply =
          (op) => OpResult(opId: op.opId, result: 'applied', rev: 2);
      expect((await engine.syncOnce()).outcome, SyncOutcome.ok);
      expect(await store.pendingCount(), 0);
    },
  );

  test('without a device id the round reports an error', () async {
    final noDevice = SyncEngine(
      store: store,
      gateway: gateway,
      deviceId: () => null,
    );
    expect((await noDevice.syncOnce()).outcome, SyncOutcome.error);
  });
}
