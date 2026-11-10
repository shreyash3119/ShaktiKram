import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/auth/session_controller.dart';
import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/db/sync_models.dart';
import 'package:shaktikram/core/sync/sync_status.dart';

import 'support/fakes.dart';

OutboxOp _op() => OutboxOp(
      opId: 'op-1',
      entity: 'body_measurements',
      action: 'upsert',
      recordId: 'a',
      clientUpdatedAt: DateTime.utc(2026, 11, 10),
      payload: const {'id': 'a', 'value': 78.0},
    );

Future<ProviderContainer> _ready(Harness h) async {
  final container = ProviderContainer(overrides: h.overrides);
  addTearDown(container.dispose);
  container.read(sessionControllerProvider);
  await pumpEventQueue();
  return container;
}

void main() {
  test('a sync that works clears the pending count and records the time', () async {
    final h = Harness.ready();
    final c = await _ready(h);
    await h.local.saveLocal(_op());

    await c.read(syncStatusProvider.notifier).syncNow();
    final status = c.read(syncStatusProvider);
    expect(status.phase, SyncPhase.synced);
    expect(status.pendingCount, 0);
    expect(status.lastSyncAt, isNotNull);
  });

  test('offline: the change stays queued and the status says offline', () async {
    final h = Harness.ready();
    final c = await _ready(h);
    await h.local.saveLocal(_op());
    h.gateway.applyError = const BackendError.unreachable();

    await c.read(syncStatusProvider.notifier).syncNow();
    expect(c.read(syncStatusProvider).phase, SyncPhase.offline);
    expect(c.read(syncStatusProvider).pendingCount, 1);
  });

  test('a device removed on the server moves the session to revoked', () async {
    final h = Harness.ready();
    final c = await _ready(h);
    h.gateway.applyError = const BackendError('device_revoked', 'this device was revoked');
    await h.local.saveLocal(_op());

    await c.read(syncStatusProvider.notifier).syncNow();
    expect(c.read(sessionControllerProvider).phase, SessionPhase.revoked);
    expect(await h.local.pendingCount(), 1, reason: 'nothing is lost');
  });

  test('a device the server forgot is registered again and the sync is retried once', () async {
    final h = Harness.ready();
    final c = await _ready(h);
    await h.local.saveLocal(_op());
    h.gateway.applyError = const BackendError('unauthorized', 'device is not registered');

    h.gateway.clearApplyErrorOnRegister = true;

    await c.read(syncStatusProvider.notifier).syncNow();

    expect(h.gateway.calls, contains('registerDevice:device-1:Test phone'));
    expect(c.read(sessionControllerProvider).phase, SessionPhase.ready);
    expect(await h.local.pendingCount(), 0);
  });
}
