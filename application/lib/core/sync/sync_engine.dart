import '../auth/uuid.dart';
import '../backend/backend_error.dart';
import '../backend/backend_gateway.dart';
import '../db/local_store.dart';
import '../db/sync_models.dart';

enum SyncOutcome {
  /// Everything sent and pulled.
  ok,

  /// The server could not be reached. Changes stay queued.
  offline,

  /// The server says this device was removed.
  revoked,

  /// The server answered with an error. Changes stay queued.
  error,

  /// The server does not know this device. The app registers it again and tries once more.
  notRegistered,

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

  /// [onProgress] is told how many rows this round has received so far (useful for the first, large pull).
  Future<SyncReport> syncOnce({void Function(int pulled)? onProgress}) async {
    if (_busy) return const SyncReport(SyncOutcome.busy);
    _busy = true;
    var pushed = 0;
    var pulled = 0;
    try {
      final device = deviceId();
      if (device == null) return const SyncReport(SyncOutcome.error, message: 'This device is not registered yet.');

      // 1. Push. Each pass sends at most one operation per record, so an edit never goes out in the same request
      // as the create it depends on (the edit needs the revision the create gets). The next pass is built after the
      // answers are stored, so the edit then carries the right base revision. An operation already tried in this
      // round (kept for retry) is not sent again until the next round.
      final tried = <String>{};
      while (true) {
        final queued = await store.pendingOps(afterSeq: 0, limit: pushBatch * 20);
        final batch = <OutboxOp>[];
        final records = <String>{};
        for (final op in queued) {
          final id = op.recordId;
          // The oldest queued operation of a record holds back the later ones, even while it waits for a retry.
          if (id != null && !records.add('${op.entity}/$id')) continue;
          if (tried.contains(op.opId)) continue;
          batch.add(op);
          if (batch.length >= pushBatch) break;
        }
        if (batch.isEmpty) break;
        tried.addAll(batch.map((o) => o.opId));
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
        onProgress?.call(pulled);
        if (!page.hasMore || page.nextRev <= since) break;
        since = page.nextRev;
      }

      await store.setLastSyncAt(DateTime.now().toUtc());
      return SyncReport(SyncOutcome.ok, pushed: pushed, pulled: pulled);
    } on BackendError catch (e) {
      if (e.isDeviceRevoked) return SyncReport(SyncOutcome.revoked, pushed: pushed, pulled: pulled, message: e.userMessage);
      if (e.isDeviceNotRegistered) return SyncReport(SyncOutcome.notRegistered, pushed: pushed, pulled: pulled, message: e.userMessage);
      if (e.isUnreachable) return SyncReport(SyncOutcome.offline, pushed: pushed, pulled: pulled);
      return SyncReport(SyncOutcome.error, pushed: pushed, pulled: pulled, message: e.userMessage);
    } catch (_) {
      // An answer the app could not read, or a storage problem. Changes stay queued; the owner sees a sync problem.
      return SyncReport(SyncOutcome.error, pushed: pushed, pulled: pulled, message: 'Sync stopped unexpectedly. Your changes are still saved on this phone.');
    } finally {
      _busy = false;
    }
  }
}
