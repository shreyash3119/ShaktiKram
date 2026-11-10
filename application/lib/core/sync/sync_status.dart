import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../backend/backend_gateway.dart';
import '../db/local_store.dart';
import 'sync_engine.dart';

/// What the small sync indicator shows (decision F4).
enum SyncPhase { synced, syncing, pending, offline, error }

class SyncStatus {
  const SyncStatus(this.phase, {this.pendingCount = 0, this.issueCount = 0, this.lastSyncAt, this.message});

  final SyncPhase phase;

  /// Local changes not yet accepted by the server.
  final int pendingCount;

  /// Changes the server refused or that lost a conflict.
  final int issueCount;
  final DateTime? lastSyncAt;

  /// The last problem, in plain words.
  final String? message;

  SyncStatus copyWith({SyncPhase? phase, int? pendingCount, int? issueCount, DateTime? lastSyncAt, String? message, bool clearMessage = false}) {
    return SyncStatus(
      phase ?? this.phase,
      pendingCount: pendingCount ?? this.pendingCount,
      issueCount: issueCount ?? this.issueCount,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

/// Counts up each time local data changes (a save, or rows pulled from the server). Screens watch it to reload.
class DataRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final dataRevisionProvider = NotifierProvider<DataRevisionNotifier, int>(DataRevisionNotifier.new);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    store: ref.read(localStoreProvider),
    gateway: ref.read(backendGatewayProvider),
    deviceId: () => ref.read(sessionControllerProvider).deviceId,
  );
});

/// Owns the sync indicator and runs sync rounds. Never reads the local store until a sync or refresh is asked for.
class SyncStatusNotifier extends Notifier<SyncStatus> {
  bool _running = false;
  bool _again = false;
  bool _alive = true;

  @override
  SyncStatus build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return const SyncStatus(SyncPhase.synced);
  }

  /// Re-reads the counts after a local save and shows "pending" if something is waiting.
  Future<void> refresh() async {
    final store = ref.read(localStoreProvider);
    final pending = await store.pendingCount();
    final issues = await store.issueCount();
    final last = await store.lastSyncAt();
    if (!_alive) return;
    ref.read(dataRevisionProvider.notifier).bump();
    if (_running) return;
    state = state.copyWith(
      phase: pending > 0 ? (state.phase == SyncPhase.offline ? SyncPhase.offline : SyncPhase.pending) : _idlePhase(issues),
      pendingCount: pending,
      issueCount: issues,
      lastSyncAt: last,
    );
  }

  SyncPhase _idlePhase(int issues) => issues > 0 ? SyncPhase.error : SyncPhase.synced;

  /// Runs a sync round now. A call made during a round makes it run once more afterwards.
  Future<void> syncNow() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        if (!_alive) return;
        state = state.copyWith(phase: SyncPhase.syncing, clearMessage: true);
        final report = await ref.read(syncEngineProvider).syncOnce();
        if (!_alive) return;
        final store = ref.read(localStoreProvider);
        final pending = await store.pendingCount();
        final issues = await store.issueCount();
        final last = await store.lastSyncAt();
        if (!_alive) return;
        if (report.changedData) ref.read(dataRevisionProvider.notifier).bump();
        final phase = switch (report.outcome) {
          SyncOutcome.ok || SyncOutcome.busy => pending > 0 ? SyncPhase.pending : _idlePhase(issues),
          SyncOutcome.offline => SyncPhase.offline,
          SyncOutcome.error || SyncOutcome.revoked => SyncPhase.error,
        };
        state = SyncStatus(phase, pendingCount: pending, issueCount: issues, lastSyncAt: last, message: report.message);
        if (report.outcome == SyncOutcome.revoked) {
          ref.read(sessionControllerProvider.notifier).markRevoked();
          return;
        }
      } while (_again);
    } finally {
      _running = false;
    }
  }
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);
