import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/metric_card.dart';
import '../../../core/widgets/screen_scaffold.dart';

/// What kind of day it is. Decides which cards lead the dashboard (decision F2).
enum DayKind { training, rest, unknown }

/// STUB. Always "unknown" until the schedule data is synced locally (build step 4).
/// Training day and rest day come from `schedule_entries` and `v_attendance_daily`.
class DayKindNotifier extends Notifier<DayKind> {
  @override
  DayKind build() => DayKind.unknown;
}

final dayKindProvider = NotifierProvider<DayKindNotifier, DayKind>(DayKindNotifier.new);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(dayKindProvider);

    return ScreenScaffold(
      title: 'Home',
      children: [
        _TodayCard(kind: kind),
        const _CheckInCard(),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: MetricCard(label: 'Workout streak', icon: Icons.local_fire_department_outlined, note: 'Needs synced schedule')),
            SizedBox(width: AppTheme.gap),
            Expanded(child: MetricCard(label: 'Current weight', icon: Icons.monitor_weight_outlined, note: 'Body tracking: backend Stage 3')),
          ],
        ),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: MetricCard(label: 'Steps today', icon: Icons.directions_walk_outlined, note: 'Activity: backend Stage 3')),
            SizedBox(width: AppTheme.gap),
            Expanded(child: MetricCard(label: 'Last session', icon: Icons.history, note: 'Needs synced sessions')),
          ],
        ),
      ],
    );
  }
}

/// The prominent card. Wording follows the day kind; the Start button arrives with the workout screen.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.kind});
  final DayKind kind;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (String title, String body) = switch (kind) {
      DayKind.training => ('Today\'s workout', 'Your planned session will appear here.'),
      DayKind.rest => ('Rest day', 'No session planned. Recovery and activity show below.'),
      DayKind.unknown => ('Today', 'No plan loaded yet. Your schedule appears here after the first sync.'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: text.titleLarge),
          const SizedBox(height: 6),
          Text(body, style: text.bodyMedium),
        ]),
      ),
    );
  }
}

/// Optional daily check-in (decision F7). Never blocks anything. Real fields come with backend Stage 3.
class _CheckInCard extends StatelessWidget {
  const _CheckInCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const Icon(Icons.favorite_border),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Daily check-in', style: text.titleSmall),
              Text('Energy, sleep, soreness, fatigue, stress, pain. Optional. Available after backend Stage 3.',
                  style: text.bodySmall),
            ]),
          ),
        ]),
      ),
    );
  }
}
