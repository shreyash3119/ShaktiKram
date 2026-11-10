import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_status.dart';
import '../theme/app_theme.dart';

/// Small pill for the Home header: Synced, Syncing, N waiting, Offline or Sync problem.
/// Settings also shows the full sync status.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final p = context.pal;

    final (String label, Color color) = switch (status.phase) {
      SyncPhase.synced => ('Synced', p.link),
      SyncPhase.syncing => ('Syncing', p.link),
      SyncPhase.pending => ('${status.pendingCount} waiting', p.amber),
      SyncPhase.offline => ('Offline', p.muted),
      SyncPhase.error => ('Sync problem', p.red),
    };

    return Semantics(
      label: 'Sync status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500)),
      ),
    );
  }
}
