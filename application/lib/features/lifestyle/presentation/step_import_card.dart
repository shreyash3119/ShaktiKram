import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/insight_status.dart' show ageText;
import '../data/step_providers.dart';

/// Activity tab: a compact Health Connect tile. An icon, the name and one line of status; tapping it connects or
/// updates. Steps from the Google Health app, a watch or the phone are imported by the same controller as before.
class StepImportCard extends ConsumerStatefulWidget {
  const StepImportCard({super.key});

  @override
  ConsumerState<StepImportCard> createState() => _StepImportCardState();
}

class _StepImportCardState extends ConsumerState<StepImportCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(stepSyncProvider.notifier).check());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = ref.watch(stepSyncProvider);
    final c = ref.read(stepSyncProvider.notifier);
    final String status;
    IconData icon = Icons.link;
    VoidCallback? action;
    var busy = false;
    switch (s.phase) {
      case StepSyncPhase.checking:
        status = 'Checking…';
        busy = true;
      case StepSyncPhase.unsupported:
        status = 'Not available on this phone';
        icon = Icons.block;
      case StepSyncPhase.notInstalled:
        status = 'Install to connect';
        action = () => unawaited(c.connect());
      case StepSyncPhase.needsAccess:
        status = 'Not connected · tap to connect';
        action = () => unawaited(c.connect());
      case StepSyncPhase.syncing:
        status = 'Reading steps…';
        busy = true;
      case StepSyncPhase.error:
        status = 'Could not sync · tap to retry';
        icon = Icons.refresh;
        action = () => unawaited(c.connect());
      case StepSyncPhase.ready:
        status = s.lastSyncAt == null ? 'Connected' : 'Updated ${ageText(s.lastSyncAt)}';
        icon = Icons.sync;
        action = () => unawaited(c.sync());
    }
    final connected = s.phase == StepSyncPhase.ready || s.phase == StepSyncPhase.syncing;
    final tile = Row(
      children: [
        Icon(Icons.favorite, size: 22, color: connected ? p.green : p.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Health Connect', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700)),
              Text(status, key: const Key('step-import-status'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, size: 20, color: action == null ? p.faint : p.link),
      ],
    );
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        key: action == null ? null : const Key('step-import-button'),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: tile,
        ),
      ),
    );
  }
}
