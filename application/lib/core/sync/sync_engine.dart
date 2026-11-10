import '../auth/uuid.dart';
import '../backend/backend_error.dart';
import '../backend/backend_gateway.dart';
import '../db/local_store.dart';

enum SyncOutcome {
  /// Everything sent and pulled.
  ok,

  /// The server could not be reached. Changes stay queued.
  offline,

  /// The server says this device was removed.
  revoked,

  /// The server answered with an error. Changes stay queued.
  error,

  /// A sync is already running.
  busy,
}

class SyncReport {
  const SyncReport(this.outcome, {this.pushed = 0, this.pulled = 0, this.message});

  final SyncOutcome outcome;

  /// Operations the server answered for (applied, refused or in conflict).
  final int pushed;

  /// Rows received.
  final int pulled;
  final String? message;

  bool get changedData => pushed > 0 || pulled > 0;
}

/// One round of sync: send queued changes, then fetch what changed on the server.
/// Knows nothing about screens or Riverpod.
class SyncEngine {
  SyncEngine({
    required this.store,
    required this.gateway,
    required this.deviceId,
    this.pushBatch = 100,
    this.pullPage = 200,
  });

  final LocalStore store;
  final BackendGateway gateway;

  /// The id of this device, or null before registration.
  final String? Function() deviceId;
  final int pushBatch;
  final int pullPage;

  bool _busy = false;

  Future<SyncReport> syncOnce() async {
    if (_busy) return const SyncReport(SyncOutcome.busy);
    _busy = true;
    var pushed = 0;
    var pulled = 0;
    try {
      final device = deviceId();
      if (device == null) return const SyncReport(SyncOutcome.error, message: 'This device is not registered yet.');

      // 1. Push. The cursor makes sure an operation kept for retry is not sent twice in one round.
      var cursor = 0;
      while (true) {
        final batch = await store.pendingOps(afterSeq: cursor, limit: pushBatch);
        if (batch.isEmpty) break;
        cursor = batch.last.seq!;
        final results = await gateway.applyOperations(deviceId: device, requestId: newUuidV4(), operations: batch);
        final byId = {for (final r in results) r.opId: r};
        for (final op in batch) {
          final result = byId[op.opId];
          if (result == null) continue; // No answer: stays queued for the next round.
          await store.recordResult(op, result);
          pushed++;
        }
      }

      // 2. Pull.
      var since = await store.lastRev();
      while (true) {
        final page = await gateway.pullChanges(deviceId: device, sinceRev: since, limit: pullPage);
        if (page.nextRev <= since && page.rows.isEmpty) break;
        pulled += page.rows.length;
        await store.applyPulled(page.rows, page.nextRev > since ? page.nextRev : since);
        if (!page.hasMore || page.nextRev <= since) break;
        since = page.nextRev;
      }

      await store.setLastSyncAt(DateTime.now().toUtc());
      return SyncReport(SyncOutcome.ok, pushed: pushed, pulled: pulled);
    } on BackendError catch (e) {
      if (e.isDeviceRevoked) return SyncReport(SyncOutcome.revoked, pushed: pushed, pulled: pulled, message: e.userMessage);
      if (e.isUnreachable) return SyncReport(SyncOutcome.offline, pushed: pushed, pulled: pulled);
      return SyncReport(SyncOutcome.error, pushed: pushed, pulled: pulled, message: e.userMessage);
    } finally {
      _busy = false;
    }
  }
}
