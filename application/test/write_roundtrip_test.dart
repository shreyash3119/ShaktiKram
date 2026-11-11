import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/auth/session_controller.dart';
import 'package:shaktikram/core/db/sync_models.dart';
import 'package:shaktikram/core/sync/sync_check.dart';
import 'package:shaktikram/core/sync/sync_engine.dart';
import 'package:shaktikram/core/sync/sync_status.dart';

import 'support/fake_server.dart';
import 'support/fakes.dart';
import 'support/memory_local_store.dart';
import 'support/store_contract.dart';

OutboxOp _opAt(String opId, String entity, String id, Map<String, dynamic> payload, DateTime at, {String action = 'upsert'}) => OutboxOp(
      opId: opId,
      entity: entity,
      action: action,
      recordId: id,
      clientUpdatedAt: at,
      payload: payload,
    );

final _early = DateTime.utc(2026, 11, 10, 9, 30); // before the server's clock (10:00)
final _late = DateTime.utc(2026, 11, 10, 11); // after it

class _Phone {
  _Phone(this.name, FakeServer server) : store = MemoryLocalStore() {
    engine = SyncEngine(store: store, gateway: server, deviceId: () => name);
  }

  final String name;
  final MemoryLocalStore store;
  late final SyncEngine engine;
}

void main() {
  late FakeServer server;
  late _Phone a;
  late _Phone b;

  setUp(() async {
    server = FakeServer();
    a = _Phone('dev-a', server);
    b = _Phone('dev-b', server);
    await server.registerDevice(id: 'dev-a', label: 'A', platform: 'mobile');
    await server.registerDevice(id: 'dev-b', label: 'B', platform: 'mobile');
  });

  Future<void> sync(_Phone p) async => expect((await p.engine.syncOnce()).outcome, SyncOutcome.ok);

  group('create, edit, delete', () {
    test('each step reaches the server and comes back with a new revision', () async {
      final id = uid(1);
      await a.store.saveLocal(op('c1', 'meals', id, {'id': id, 'title': 'T', 'category': 'snack'}));
      await sync(a);
      expect(server.row('meals', id)!['title'], 'T');
      final rev1 = server.row('meals', id)!['rev'] as int;
      expect((await a.store.get('meals', id))!['rev'], rev1);
      expect(await a.store.pendingCount(), 0);

      await a.store.saveLocal(op('e1', 'meals', id, {'id': id, 'title': 'T2'}));
      await sync(a);
      expect(server.row('meals', id)!['title'], 'T2');
      expect(server.row('meals', id)!['category'], 'snack', reason: 'an edit only changes the fields it sends');
      final rev2 = server.row('meals', id)!['rev'] as int;
      expect(rev2 > rev1, isTrue);

      await a.store.saveLocal(op('d1', 'meals', id, const {}, action: 'delete'));
      await sync(a);
      expect(server.row('meals', id)!['deleted_at'], isNotNull);
      expect(await a.store.list('meals'), isEmpty);
      expect((await a.store.get('meals', id))!['deleted_at'], isNotNull);
      expect(await a.store.pendingCount(), 0);
      expect(await a.store.issueCount(), 0);
    });

    test('everything done offline is sent in order when the connection returns', () async {
      final id = uid(1);
      await a.store.saveLocal(op('c1', 'meals', id, {'id': id, 'title': 'T', 'category': 'snack'}));
      await a.store.saveLocal(op('e1', 'meals', id, {'id': id, 'title': 'T2'}));
      await a.store.saveLocal(op('d1', 'meals', id, const {}, action: 'delete'));
      server.offline = true;
      expect((await a.engine.syncOnce()).outcome, SyncOutcome.offline);
      expect(await a.store.pendingCount(), 3);
      expect(await a.store.list('meals'), isEmpty);

      server.offline = false;
      await sync(a);
      expect(await a.store.pendingCount(), 0);
      expect(await a.store.issueCount(), 0);
      expect(server.row('meals', id)!['title'], 'T2');
      expect(server.row('meals', id)!['deleted_at'], isNotNull);
    });

    test('a lost response is replayed without creating the record twice, and is still counted as applied', () async {
      final id = uid(1);
      await a.store.saveLocal(op('c1', 'meals', id, {'id': id, 'title': 'T', 'category': 'snack'}));
      server.dropNextResponse = true;
      expect((await a.engine.syncOnce()).outcome, SyncOutcome.offline);
      expect(server.row('meals', id), isNotNull);
      expect(await a.store.pendingCount(), 1);

      await sync(a);
      expect(await a.store.pendingCount(), 0);
      expect(await a.store.issueCount(), 0);
      expect(server.tables['meals'], hasLength(1));
      expect((await a.store.get('meals', id))!['rev'], server.row('meals', id)!['rev']);
    });
  });

  group('refused and ignored changes', () {
    test('a record the server cannot accept is removed and shown as a problem', () async {
      final id = uid(1);
      await a.store.saveLocal(op('c1', 'meals', id, {'id': id, 'title': 'No category'}));
      await sync(a);
      expect(await a.store.get('meals', id), isNull);
      final issue = (await a.store.issues()).single;
      expect(issue.errorCode, 'validation_failed');
      expect(server.row('meals', id), isNull);
    });

    test('a table the phone may not write to is refused', () async {
      await a.store.saveLocal(op('c1', 'personal_records', uid(1), {'id': uid(1)}));
      await sync(a);
      expect((await a.store.issues()).single.errorCode, 'validation_failed');
    });

    test('an edit to a record the server never had is refused as not found', () async {
      await a.store.saveLocal(op('d1', 'meals', uid(1), const {}, action: 'delete'));
      await sync(a);
      expect((await a.store.issues()).single.errorCode, 'not_found');
    });
  });

  group('two devices', () {
    test('what one phone saves appears on the other after a sync', () async {
      final id = uid(1);
      await a.store.saveLocal(op('c1', 'meals', id, {'id': id, 'title': 'T', 'category': 'snack'}));
      await sync(a);
      await sync(b);
      expect((await b.store.get('meals', id))!['title'], 'T');
      expect(await b.store.lastRev(), server.revision);
    });

    Future<void> shareGoal() async {
      await a.store.saveLocal(op('c1', 'goals', uid(1), {'id': uid(1), 'type': 'weight', 'title': 'G'}));
      await sync(a);
      await sync(b);
    }

    test('conflict: the other phone saved after you looked and your change is older, so the server copy wins', () async {
      await shareGoal();
      await b.store.saveLocal(_opAt('b1', 'goals', uid(1), {'id': uid(1), 'title': 'B'}, _early));
      await sync(b);
      server.now = DateTime.utc(2026, 11, 10, 10, 1);

      await a.store.saveLocal(_opAt('a1', 'goals', uid(1), {'id': uid(1), 'title': 'A'}, _early));
      await sync(a);
      expect((await a.store.issues()).single.errorCode, 'conflict_stale_rev');
      expect((await a.store.get('goals', uid(1)))!['title'], 'B');
      expect(server.row('goals', uid(1))!['title'], 'B');
    });

    test('a newer change from a stale phone still wins', () async {
      await shareGoal();
      await b.store.saveLocal(_opAt('b1', 'goals', uid(1), {'id': uid(1), 'title': 'B'}, _early));
      await sync(b);

      await a.store.saveLocal(_opAt('a1', 'goals', uid(1), {'id': uid(1), 'title': 'A'}, _late));
      await sync(a);
      expect(await a.store.issueCount(), 0);
      expect(server.row('goals', uid(1))!['title'], 'A');
    });

    test('append-only: a correction on the current revision is applied, a stale one is not silently accepted', () async {
      final id = uid(1);
      final measurement = {'id': id, 'occurred_at': '2026-11-10T07:00:00Z', 'local_date': '2026-11-10', 'tz_offset_minutes': 330, 'measurement_type': 'weight', 'value': 80.0};
      await a.store.saveLocal(op('c1', 'body_measurements', id, measurement));
      await sync(a);
      await sync(b);

      await b.store.saveLocal(op('b1', 'body_measurements', id, {'id': id, 'value': 79.5}));
      await sync(b);
      expect(server.row('body_measurements', id)!['value'], 79.5);

      await a.store.saveLocal(op('a1', 'body_measurements', id, {'id': id, 'value': 70.0}));
      await sync(a);
      expect((await a.store.issues()).single.errorCode, 'duplicate_ignored');
      expect(server.row('body_measurements', id)!['value'], 79.5);
      expect((await a.store.get('body_measurements', id))!['value'], 79.5);
    });

    test('versioned: a new version closes the previous one and both come back', () async {
      final entity = uid(9);
      await a.store.saveLocal(op('v1', 'profile_versions', uid(1), {'id': uid(1), 'entity_id': entity, 'height_cm': 170}, action: 'new_version'));
      await sync(a);
      server.now = DateTime.utc(2026, 11, 10, 12);
      await a.store.saveLocal(op('v2', 'profile_versions', uid(2), {'id': uid(2), 'entity_id': entity, 'height_cm': 171}, action: 'new_version'));
      await sync(a);

      final versions = await a.store.listByRef('profile_versions', 'entity_id', entity);
      expect(versions, hasLength(2));
      expect(versions.map((v) => v['version']).toSet(), {1, 2});
      expect(versions.firstWhere((v) => v['version'] == 1)['effective_to'], isNotNull);
      expect(versions.firstWhere((v) => v['version'] == 2)['effective_to'], isNull);
    });
  });

  group('device checks', () {
    test('a removed device is told so and keeps its queued changes', () async {
      await a.store.saveLocal(op('c1', 'goals', uid(1), {'id': uid(1), 'type': 'weight', 'title': 'G'}));
      await server.revokeDevice('dev-a');
      expect((await a.engine.syncOnce()).outcome, SyncOutcome.revoked);
      expect(await a.store.pendingCount(), 1);
    });

    test('a server that does not know the device is reported for re-registration', () async {
      final fresh = FakeServer();
      final lone = SyncEngine(store: MemoryLocalStore(), gateway: fresh, deviceId: () => 'dev-x');
      expect((await lone.syncOnce()).outcome, SyncOutcome.notRegistered);
    });
  });

  group('whole app stack with the live sync check', () {
    Future<ProviderContainer> start() async {
      final h = Harness.ready();
      await server.registerDevice(id: 'device-1', label: 'Test phone', platform: 'mobile');
      final c = ProviderContainer(overrides: h.overridesWith(server));
      addTearDown(c.dispose);
      c.read(sessionControllerProvider);
      await pumpEventQueue();
      expect(c.read(sessionControllerProvider).phase, SessionPhase.ready);
      return c;
    }

    test('every step passes against a server that follows the rules', () async {
      final c = await start();
      final steps = await c.read(syncCheckProvider).run();
      expect(steps.map((s) => '${s.passed}:${s.name}').toList(), [
        'true:Save on the phone',
        'true:Create on the server',
        'true:Edit on the server',
        'true:Delete on the server',
        'true:Final state',
      ], reason: steps.map((s) => s.detail).join(' | '));
      expect(c.read(syncStatusProvider).phase, SyncPhase.synced);
      expect(server.tables['meals']!.values.single['deleted_at'], isNotNull);
    });

    test('with no connection the check stops at the first server step and says why', () async {
      final c = await start();
      server.offline = true;
      final steps = await c.read(syncCheckProvider).run();
      expect(steps.last.passed, isFalse);
      expect(steps.last.name, 'Create on the server');
      expect(steps.last.detail, 'No connection to the server.');
    });

    test('a server that refuses the record is reported with its reason', () async {
      final c = await start();
      server.requiredFields['meals'] = ['title', 'category', 'something_missing'];
      final steps = await c.read(syncCheckProvider).run();
      expect(steps.last.passed, isFalse);
      expect(steps.last.detail, contains('validation_failed'));
    });
  });
}
