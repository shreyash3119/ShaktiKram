import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the small sync indicator shows (decision F4).
enum SyncPhase { synced, syncing, pending, offline, error }

class SyncStatus {
  const SyncStatus(this.phase, {this.pendingCount = 0});

  final SyncPhase phase;

  /// Local changes not yet accepted by the server.
  final int pendingCount;
}

/// STUB. Always reports "synced" until the sync client exists (build step 3).
/// The real implementation will read the outbox count and connectivity, and replace only this notifier.
class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncStatus(SyncPhase.synced);
}

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);
