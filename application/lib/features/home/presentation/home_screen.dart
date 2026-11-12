import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/sync/change_writer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/meters.dart';
import '../../../core/widgets/sync_status_chip.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String dateLine(DateTime now) => '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}';

/// Home dashboard. Values marked "Sample values" are placeholders until the backend data is synced locally.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ScreenFrame(
      title: greetingFor(now),
      subtitle: dateLine(now),
      trailing: const SyncStatusChip(),
      children: const [
        _TodayCard(),
        _ReadinessCard(),
        _StreakRow(),
        _BodyOverviewCard(),
        _MusclePrioritiesCard(),
        _LifestyleOverviewCard(),
        _InsightsCard(),
        _QuickWeightCard(),
        _RecentActivityCard(),
        _HighlightsCard(),
        GroupLabel('More'),
        _TodayStatusCard(),
        _AlertsCard(),
        _QuickActionsCard(),
        _WeeklySummaryCard(),
        _RecordsCard(),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      color: p.tile,
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Today · Day 1 of 4', style: TextStyle(color: p.muted, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Text('Chest + Shoulders', style: TextStyle(color: p.text, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Row(children: [
          for (final m in ['Chest', 'Shoulders'])
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Text(m, style: TextStyle(color: p.link, fontSize: 15)),
            ),
        ]),
        const SizedBox(height: 14),
        Text('7 exercises · about 60–75 min', style: TextStyle(color: p.muted, fontSize: 16)),
        const SizedBox(height: 18),
        AppButton.primary('Start workout', height: 58, onPressed: () => context.push(AppRoutes.session)),
      ]),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Readiness check-in',
      sample: true,
      link: 'Update',
      children: [
        Row(children: [
          const RingGauge(value: 0.8, centerText: '8.0', subText: '/10', size: 112),
          const SizedBox(width: 12),
          Expanded(
            child: Column(children: [
              const MeterRow(label: 'Energy', value: 0.8, trailing: '8/10', labelWidth: 70, trailingWidth: 50),
              const MeterRow(label: 'Sleep', value: 0.75, trailing: '7.5/10', labelWidth: 70, trailingWidth: 50),
              MeterRow(label: 'Soreness', value: 0.3, trailing: '3/10', color: p.amber, labelWidth: 70, trailingWidth: 50),
              MeterRow(label: 'Fatigue', value: 0.2, trailing: '2/10', color: p.amber, labelWidth: 70, trailingWidth: 50),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        const MutedText(
          'Based on today’s check-in. Train as planned and adjust to how your warm-up feels. '
          'This is guidance, not medical advice.',
          size: 15,
        ),
      ],
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const done = [true, true, true, false, false, false, false];
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Streak', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text('3 days', style: TextStyle(color: p.text, fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const MutedText('This week 3 / 4'),
              const Spacer(),
              const SizedBox(height: 14),
              Row(children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: done[i] ? p.greenFill : p.tile),
                        child: done[i] ? Icon(Icons.check, size: 11, color: p.green) : null,
                      ),
                      const SizedBox(height: 4),
                      Text(days[i], style: TextStyle(color: p.muted, fontSize: 11)),
                    ]),
                  ),
              ]),
            ]),
          ),
        ),
        const SizedBox(width: AppTheme.gap),
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('This week', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text('3/4', style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w800)),
              Text('Workouts', style: TextStyle(color: p.muted, fontSize: 13)),
              const SizedBox(height: 18),
              Text('12,450 kg', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w700)),
              Text('Volume', style: TextStyle(color: p.muted, fontSize: 13)),
              const SizedBox(height: 14),
              Text('3 h 45 m', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w700)),
              Text('Active time', style: TextStyle(color: p.muted, fontSize: 13)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _BodyOverviewCard extends StatelessWidget {
  const _BodyOverviewCard();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Body overview',
      sample: true,
      link: 'Progress',
      onLink: () => context.go(AppRoutes.progress),
      children: [
        Row(children: [
          Expanded(child: _BodyStat('78.0 kg', '▼ 0.6 kg · 7 days', p)),
          Expanded(child: _BodyStat('18.4 %', '▼ 0.4 % · 7 days', p)),
        ]),
        const SizedBox(height: 14),
        const MutedText('Body fat: smart-scale reading, Nov 2.', size: 15),
      ],
    );
  }
}

class _BodyStat extends StatelessWidget {
  const _BodyStat(this.value, this.change, this.p);
  final String value;
  final String change;
  final AppPalette p;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(color: p.text, fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(change, style: TextStyle(color: p.muted, fontSize: 14)),
    ]);
  }
}

class _MusclePrioritiesCard extends StatelessWidget {
  const _MusclePrioritiesCard();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Muscle priorities',
      link: 'Muscles',
      onLink: () => context.go(AppRoutes.progress),
      children: [
        const MutedText('From your own self-assessment (1–5).', size: 15),
        const SizedBox(height: 8),
        MeterRow(label: 'Rear delts', value: 0.2, trailing: 'P1', color: p.amber, trailingWidth: 30),
        MeterRow(label: 'Abs', value: 0.4, trailing: 'P1', color: p.amber, trailingWidth: 30),
        const MeterRow(label: 'Forearms', value: 0.4, trailing: 'P2', trailingWidth: 30),
        const MeterRow(label: 'Obliques', value: 0.2, trailing: 'P2', trailingWidth: 30),
      ],
    );
  }
}

class _LifestyleOverviewCard extends StatelessWidget {
  const _LifestyleOverviewCard();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget tile(String label, String value, double v, String foot) => InnerTile(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: p.muted, fontSize: 15)),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            MeterBar(value: v, trackColor: p.card),
            const SizedBox(height: 8),
            Text(foot, style: TextStyle(color: p.muted, fontSize: 14)),
          ]),
        );
    return TitledCard(
      title: 'Lifestyle overview',
      sample: true,
      link: 'Lifestyle',
      onLink: () => context.go(AppRoutes.lifestyle),
      children: [
        ButtonPair(tile('Supplements', '2 / 3', 0.67, 'Taken'), tile('Meals', '3 / 4', 0.75, 'Completed')),
        const SizedBox(height: 12),
        ButtonPair(tile('Water', '2.4 / 3.0 L', 0.8, '80%'), tile('Steps', '6,420', 0.64, 'of 10,000')),
      ],
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Insights & suggestions',
      link: 'All',
      children: [
        RowList([
          RowItem(title: 'Bench press is up over the last 2 weeks', subtitle: 'Top set 82.5 → 85 kg'),
          RowItem(title: 'Rear delts and abs get little direct work', subtitle: 'Consider adding a set or two if it fits your split.'),
          RowItem(title: 'Sleep average 6.8 h, below your 7.5 h target', subtitle: 'Better sleep supports recovery.'),
        ]),
      ],
    );
  }
}

/// A weight entry as a `body_measurements` payload (append-only table). Dates follow the phone's local time.
Map<String, dynamic> weightPayload(double kg, DateTime now) {
  final local = now.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return {
    'occurred_at': now.toUtc().toIso8601String(),
    'local_date': '${local.year}-${two(local.month)}-${two(local.day)}',
    'tz_offset_minutes': local.timeZoneOffset.inMinutes,
    'measurement_type': 'weight',
    'value': kg,
    'source': 'manual',
  };
}

class _QuickWeightCard extends ConsumerStatefulWidget {
  const _QuickWeightCard();

  @override
  ConsumerState<_QuickWeightCard> createState() => _QuickWeightCardState();
}

class _QuickWeightCardState extends ConsumerState<_QuickWeightCard> {
  String _text = '78.0';
  String? _note;
  bool _noteIsError = false;

  Future<void> _save() async {
    final kg = double.tryParse(_text.trim().replaceAll(',', '.'));
    if (kg == null || kg < 20 || kg > 400) {
      setState(() {
        _note = 'Enter a weight between 20 and 400 kg.';
        _noteIsError = true;
      });
      return;
    }
    await ref.read(changeWriterProvider).upsert('body_measurements', weightPayload(kg, DateTime.now()));
    if (!mounted) return;
    setState(() {
      _note = 'Saved on this phone. It will sync when online.';
      _noteIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Quick log weight',
      children: [
        const FieldLabel('kg'),
        Row(children: [
          Expanded(
            child: FieldBox(
              fieldKey: const Key('quick-weight-field'),
              initial: _text,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) => _text = v,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: AppButton.primary('Save', key: const Key('quick-weight-save'), height: 56, onPressed: _save)),
        ]),
        const SizedBox(height: 14),
        Text(
          _note ?? 'Saved with today’s date.',
          key: const Key('quick-weight-note'),
          style: TextStyle(color: _noteIsError ? p.red : p.muted, fontSize: 15),
        ),
      ],
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard();

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Recent activity',
      sample: true,
      link: 'History',
      onLink: () => context.go(AppRoutes.training),
      children: const [
        RowList([
          RowItem(title: 'Back + Abs', subtitle: 'Sun, Nov 2 · 58 min · 6 exercises', chevron: true),
          RowItem(title: 'Chest + Shoulders', subtitle: 'Fri, Oct 31 · 64 min · 7 exercises', chevron: true),
        ]),
      ],
    );
  }
}

class _HighlightsCard extends StatelessWidget {
  const _HighlightsCard();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Highlights',
      sample: true,
      children: [
        RowList([
          RowItem(title: 'New PR', subtitle: 'Bench Press 85 kg · Nov 2', chevron: true),
          RowItem(title: 'Achievement', subtitle: '4-week consistency above 75%', chevron: true),
        ]),
      ],
    );
  }
}

enum _DayState { planned, inProgress, completed, skipped, rest }

class _TodayStatusCard extends StatefulWidget {
  const _TodayStatusCard();

  @override
  State<_TodayStatusCard> createState() => _TodayStatusCardState();
}

class _TodayStatusCardState extends State<_TodayStatusCard> {
  _DayState _state = _DayState.inProgress;

  static const _labels = ['Planned', 'In progress', 'Completed', 'Skipped', 'Rest day'];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final (String line, String? button) = switch (_state) {
      _DayState.planned => ('Chest + Shoulders · 7 exercises · about 60–75 min', 'Start workout'),
      _DayState.inProgress => ('Chest + Shoulders · exercise 2 of 7 · 00:42:10', 'Continue workout'),
      _DayState.completed => ('Chest + Shoulders · completed · 58 min', null),
      _DayState.skipped => ('Chest + Shoulders · skipped. You can log it later.', null),
      _DayState.rest => ('Rest day. Recovery is part of the plan.', null),
    };
    return TitledCard(
      title: 'Today’s status',
      children: [
        PillTabs(
          labels: _labels,
          index: _state.index,
          layout: PillLayout.wrap,
          onChanged: (i) => setState(() => _state = _DayState.values[i]),
        ),
        const SizedBox(height: 14),
        Text(line, style: TextStyle(color: p.muted, fontSize: 15, height: 1.4)),
        if (button != null) ...[
          const SizedBox(height: 14),
          AppButton.primary(button, height: 54, onPressed: () => context.push(AppRoutes.session)),
        ],
        const SizedBox(height: 12),
        const MutedText('Shows “Start workout” when planned and “Rest day” on rest days.'),
      ],
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard();

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Alerts',
      link: 'All',
      children: [
        RowList([
          RowItem(
            title: 'Unfinished session',
            subtitle: 'Chest + Shoulders started earlier',
            trailing: 'Resume ›',
            onTap: () => context.push(AppRoutes.session),
          ),
          const RowItem(title: 'Next workout', subtitle: 'Day 3 · Arms + Forearms · tomorrow 6:30 pm', chevron: true),
          const RowItem(title: 'Reassessment due', subtitle: 'Muscle self-assessment, Nov 16', chevron: true),
        ]),
      ],
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard();

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Quick actions',
      children: [
        ButtonPair(
          AppButton('Workout history', onPressed: () => context.go(AppRoutes.training)),
          AppButton('Log meal', onPressed: () => context.go(AppRoutes.lifestyle)),
        ),
      ],
    );
  }
}

class _WeeklySummaryCard extends StatelessWidget {
  const _WeeklySummaryCard();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Weekly activity summary',
      sample: true,
      children: [
        const Row(children: [
          Expanded(child: StatBlock('3', 'Workouts')),
          Expanded(flex: 2, child: StatBlock('12,450 kg', 'Volume')),
          Expanded(flex: 2, child: StatBlock('3 h 45 m', 'Time')),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(width: 70, child: Text('Steps avg', style: TextStyle(color: p.muted, fontSize: 14.5))),
          const Expanded(child: MeterBar(value: 0.64)),
          SizedBox(width: 44, child: Text('6.4k', textAlign: TextAlign.right, style: TextStyle(color: p.text, fontSize: 14.5))),
        ]),
      ],
    );
  }
}

class _RecordsCard extends StatelessWidget {
  const _RecordsCard();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Records & achievements',
      sample: true,
      link: 'All',
      children: [
        RowList([
          RowItem(title: 'Bench Press 85 kg', subtitle: 'New personal record · Nov 2', trailing: 'PR'),
          RowItem(title: '3 weeks of consistent training', subtitle: 'Consistency milestone', trailing: 'Milestone'),
        ]),
      ],
    );
  }
}
