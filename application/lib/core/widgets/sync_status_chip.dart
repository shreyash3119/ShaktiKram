import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_status.dart';

/// Small indicator for the app bar: synced, syncing, N waiting, offline or error.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, String label, Color color) = switch (status.phase) {
      SyncPhase.synced => (Icons.cloud_done_outlined, 'Synced', scheme.primary),
      SyncPhase.syncing => (Icons.sync, 'Syncing', scheme.primary),
      SyncPhase.pending => (Icons.cloud_upload_outlined, '${status.pendingCount} waiting', scheme.tertiary),
      SyncPhase.offline => (Icons.cloud_off_outlined, 'Offline', scheme.outline),
      SyncPhase.error => (Icons.error_outline, 'Sync problem', scheme.error),
    };

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Semantics(
        label: 'Sync status: $label',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}
