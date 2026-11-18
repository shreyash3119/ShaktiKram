import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/insight_status.dart' show ageText;
import '../data/step_providers.dart';

/// Activity tab: connect Health Connect so steps from the Google Health app, a watch or the phone are imported.
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
    final s = ref.watch(stepSyncProvider);
    final c = ref.read(stepSyncProvider.notifier);
    final String text;
    String? button;
    VoidCallback? action;
    switch (s.phase) {
      case StepSyncPhase.checking:
        text = 'Checking Health Connect…';
      case StepSyncPhase.unsupported:
        text = 'Phone step import is not available on this device.';
      case StepSyncPhase.notInstalled:
        text = 'Health Connect is needed. Install or update it, then come back.';
        button = 'Get Health Connect';
        action = () => unawaited(c.connect());
      case StepSyncPhase.needsAccess:
        text = 'Allow this app to read your steps from Health Connect. It only reads steps, and you can remove access any time in Health Connect.';
        button = 'Connect steps';
        action = () => unawaited(c.connect());
      case StepSyncPhase.syncing:
        text = 'Reading steps…';
      case StepSyncPhase.error:
        text = s.message ?? 'Something went wrong.';
        button = 'Try again';
        action = () => unawaited(c.connect());
      case StepSyncPhase.ready:
        final today = s.todaySteps == null ? '' : ' Today so far: ${s.todaySteps} steps.';
        text = 'Connected. Steps are imported from Health Connect, which combines the Google Health app, your watch and other apps.$today'
            '${s.lastSyncAt == null ? '' : ' Updated ${ageText(s.lastSyncAt)}.'}';
        button = 'Update steps now';
        action = () => unawaited(c.sync());
    }
    return TitledCard(title: 'Phone and watch steps', children: [
      MutedText(text, size: 15),
      if (s.phase == StepSyncPhase.ready && s.keptManualDays > 0) ...[
        const SizedBox(height: 8),
        MutedText('${s.keptManualDays} day${s.keptManualDays == 1 ? '' : 's'} you entered by hand ${s.keptManualDays == 1 ? 'was' : 'were'} left as you entered.', size: 13),
      ],
      if (button != null) ...[
        const SizedBox(height: 12),
        AppButton(button, key: const Key('step-import-button'), onPressed: action),
      ],
      const SizedBox(height: 10),
      const MutedText('A day you type in by hand is never overwritten by an import.', size: 13),
    ]);
  }
}
