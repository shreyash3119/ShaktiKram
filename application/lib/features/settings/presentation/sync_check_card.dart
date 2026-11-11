import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_check.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';

/// Development only (shown in debug builds): runs the live create, edit and delete check against the configured
/// Supabase project.
class SyncCheckCard extends ConsumerStatefulWidget {
  const SyncCheckCard({super.key});

  @override
  ConsumerState<SyncCheckCard> createState() => _SyncCheckCardState();
}

class _SyncCheckCardState extends ConsumerState<SyncCheckCard> {
  bool _running = false;
  List<CheckStep>? _steps;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _steps = null;
    });
    List<CheckStep> steps;
    try {
      steps = await ref.read(syncCheckProvider).run();
    } catch (e) {
      steps = [CheckStep('Sync check', false, 'Stopped unexpectedly: $e')];
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _steps = steps;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final steps = _steps;
    return TitledCard(
      title: 'Sync check (development)',
      children: [
        Text(
          'Creates a meal called "SYNC CHECK ...", edits it, then deletes it, checking each step with the server. '
          'Run it only against a development Supabase project.',
          style: TextStyle(color: p.muted, fontSize: 14),
        ),
        const SizedBox(height: 12),
        AppButton(_running ? 'Running...' : 'Run sync check', key: const Key('sync-check-run'), onPressed: _running ? null : _run),
        if (steps != null) ...[
          const SizedBox(height: 12),
          for (final s in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${s.passed ? 'Passed' : 'Failed'}: ${s.name}. ${s.detail}',
                style: TextStyle(color: s.passed ? p.green : p.red, fontSize: 14),
              ),
            ),
        ],
      ],
    );
  }
}
