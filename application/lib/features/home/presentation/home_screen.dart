import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/insights/insight_providers.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/sync/change_writer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/local_stamp.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/insight_status.dart';
import '../../../core/widgets/meters.dart';
import '../../../core/widgets/sync_status_chip.dart';
import '../../lifestyle/data/lifestyle_models.dart';
import '../../lifestyle/data/lifestyle_providers.dart';
import '../../progress/data/progress_insights.dart';
import '../../progress/data/progress_models.dart';
import '../../progress/data/progress_providers.dart';
import '../../training/data/training_models.dart';
import '../../training/data/training_providers.dart';
import '../../training/presentation/workout_session_screen.dart';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String dateLine(DateTime now) => '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}';

String _today() => localStampOf(DateTime.now()).localDate;

String _short(String localDate) {
  final d = DateTime.tryParse(localDate);
  return d == null ? localDate : '${_months[d.month - 1]} ${d.day}';
}

String _kg(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _words(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

/// Home is a composition of what the phone holds (today's plan, the running session, recent sessions, logs, records)
/// and what the server calculated (the daily briefing: readiness, deload, streak, trends). Server answers come from the
/// insight cache and say how old they are; nothing is recalculated here.
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
        _StreakCard(),
        _BodyOverviewCard(),
        _LifestyleOverviewCard(),
        _InsightsCard(),
        _QuickWeightCard(),
        _RecentActivityCard(),
        _HighlightsCard(),
        GroupLabel('More'),
        _AlertsCard(),
        _QuickActionsCard(),
      ],
    );
  }
}

/// Watches today's briefing and gives its freshness line for the cards that show server values.
class _BriefingStatus extends ConsumerWidget {
  const _BriefingStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = _today();
    final snap = ref.watch(dailyBriefingProvider(today)).snapshot;
    return InsightStatusLine(snapshot: snap, onRefresh: () => ref.read(insightProvider(dailyBriefingSpec(today)).notifier).refresh());
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final active = ref.watch(activeSessionProvider).valueOrNull;
    final today = _today();
    final entry = ref.watch(scheduleWeekProvider(today)).valueOrNull?.first;
    final split = ref.watch(activeSplitProvider).valueOrNull;
    final day = split == null || entry?.splitDayId == null ? null : [for (final d in split.days) if (d.id == entry!.splitDayId) d].firstOrNull;
    final templates = ref.watch(currentTemplatesProvider).valueOrNull ?? const <TemplateVersion>[];
    final template = entry?.templateVersionId == null ? null : [for (final t in templates) if (t.id == entry!.templateVersionId) t].firstOrNull;
    final briefing = ref.watch(dailyBriefingProvider(today)).briefing;

    final String caption;
    final String title;
    if (active != null) {
      caption = 'In progress · started ${_short(active.localDate)}';
      title = active.name ?? 'Workout in progress';
    } else if (entry?.isRestDay == true) {
      caption = 'Today · ${_short(today)}';
      title = 'Rest day';
    } else if (day != null || template != null) {
      caption = 'Today · ${_short(today)}';
      title = day?.label.isNotEmpty == true ? day!.label : (template?.name ?? 'Workout');
    } else {
      caption = 'Today · ${_short(today)}';
      title = 'No workout planned';
    }
    final planned = briefing?.plan.plannedExercises;
    return AppCard(
      color: p.tile,
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(caption, style: TextStyle(color: p.muted, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Text(title, style: TextStyle(color: p.text, fontSize: 26, fontWeight: FontWeight.w800)),
        if (active == null && planned != null && planned > 0) ...[
          const SizedBox(height: 14),
          Text('$planned exercises planned', style: TextStyle(color: p.muted, fontSize: 16)),
        ],
        if (entry?.isRestDay != true || active != null) ...[
          const SizedBox(height: 18),
          AppButton.primary(
            active != null ? 'Continue workout' : 'Start workout',
            height: 58,
            onPressed: () => startOrContinueWorkout(
              context,
              ref,
              templateVersionId: active == null ? template?.id : null,
              scheduleEntryId: entry?.id,
              splitVersionId: entry?.splitVersionId,
              splitDayId: entry?.splitDayId,
              name: day?.label ?? template?.name,
            ),
          ),
        ],
      ]),
    );
  }
}

class _ReadinessCard extends ConsumerWidget {
  const _ReadinessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final result = ref.watch(dailyBriefingProvider(_today()));
    final b = result.briefing;
    final readiness = b?.readiness;
    final deload = b?.deload;
    return TitledCard(
      title: 'Readiness',
      link: 'Check in',
      onLink: () => context.go(AppRoutes.lifestyle),
      children: [
        if (readiness == null)
          MutedText(result.snapshot.hasData ? 'No readiness answer yet. Add today’s check-in in Lifestyle.' : 'Readiness appears once the daily briefing has loaded.')
        else ...[
          Text(_words(readiness.level), key: const Key('readiness-level'), style: TextStyle(color: p.text, fontSize: 24, fontWeight: FontWeight.w800)),
          if (readiness.wellnessScore != null) ...[
            const SizedBox(height: 6),
            Text('Wellness score ${readiness.wellnessScore!.toStringAsFixed(0)}', style: TextStyle(color: p.muted, fontSize: 15)),
          ],
          for (final line in readiness.reasoning) ...[
            const SizedBox(height: 8),
            Text(line, style: TextStyle(color: p.muted, fontSize: 15, height: 1.35)),
          ],
        ],
        if (deload != null && deload.level != 'none' && deload.level != 'unknown') ...[
          const SizedBox(height: 14),
          Text('Deload: ${_words(deload.level)}', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700)),
          for (final line in deload.reasoning) ...[
            const SizedBox(height: 6),
            Text(line, style: TextStyle(color: p.muted, fontSize: 15, height: 1.35)),
          ],
        ],
        const SizedBox(height: 12),
        MutedText(readiness?.note ?? 'Guidance from your own check-ins, not medical advice.', size: 14),
        const _BriefingStatus(),
      ],
    );
  }
}

class _StreakCard extends ConsumerWidget {
  const _StreakCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final b = ref.watch(dailyBriefingProvider(_today())).briefing;
    final sessions = ref.watch(recentSessionsProvider).valueOrNull ?? const <WorkoutSession>[];
    final d = DateTime.now();
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    String two(int n) => n.toString().padLeft(2, '0');
    final first = '${monday.year}-${two(monday.month)}-${two(monday.day)}';
    final thisWeek = sessions.where((s) => s.status == 'completed' && s.localDate.compareTo(first) >= 0).length;
    Widget stat(String value, String label) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(color: p.text, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
          ]),
        );
    return TitledCard(title: 'Consistency', children: [
      Row(children: [
        stat('$thisWeek', 'Workouts this week'),
        stat(b?.currentStreak == null ? '–' : '${b!.currentStreak}', 'Current streak'),
        stat(b?.longestStreak == null ? '–' : '${b!.longestStreak}', 'Longest streak'),
      ]),
      const _BriefingStatus(),
    ]);
  }
}

class _BodyOverviewCard extends ConsumerWidget {
  const _BodyOverviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final weights = ref.watch(measurementsProvider('weight')).valueOrNull ?? const <BodyMeasurement>[];
    final fats = ref.watch(measurementsProvider('body_fat')).valueOrNull ?? const <BodyMeasurement>[];
    final w = weights.isEmpty ? null : weights.first;
    final prev = weights.length < 2 ? null : weights[1];
    final f = fats.isEmpty ? null : fats.first;
    Widget stat(String value, String note) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(color: p.text, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(note, style: TextStyle(color: p.muted, fontSize: 14)),
          ]),
        );
    String change(double d) => '${d >= 0 ? '+' : '−'}${_kg(d.abs())} kg since ${_short(prev!.localDate)}';
    return TitledCard(
      title: 'Body overview',
      link: 'Progress',
      onLink: () => context.go(AppRoutes.progress),
      children: [
        if (w == null && f == null)
          const MutedText('No weight or body-fat reading yet. Log your weight below.')
        else
          Row(children: [
            stat(w == null ? '–' : '${_kg(w.value)} kg', w == null ? 'No weight yet' : '${_short(w.localDate)}${prev == null ? '' : ' · ${change(w.value - prev.value)}'}'),
            stat(f == null ? '–' : '${_kg(f.value)} %', f == null ? 'No body fat yet' : 'Body fat · ${_short(f.localDate)}'),
          ]),
      ],
    );
  }
}

class _LifestyleOverviewCard extends ConsumerWidget {
  const _LifestyleOverviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = _today();
    final s = ref.watch(daySummaryProvider(today)).valueOrNull;
    final b = ref.watch(dailyBriefingProvider(today)).briefing;
    Widget tile(String label, String value, double? v, String foot) => InnerTile(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: p.muted, fontSize: 15)),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w800)),
            if (v != null) ...[const SizedBox(height: 8), MeterBar(value: v.clamp(0, 1).toDouble(), trackColor: p.card)],
            const SizedBox(height: 8),
            Text(foot, style: TextStyle(color: p.muted, fontSize: 14)),
          ]),
        );
    final water = s?.waterMl ?? 0;
    final waterTarget = b?.waterTargetMl;
    final steps = s?.steps?.steps;
    final stepTarget = b?.stepTarget;
    return TitledCard(
      title: 'Lifestyle today',
      link: 'Lifestyle',
      onLink: () => context.go(AppRoutes.lifestyle),
      children: [
        ButtonPair(
          tile('Supplements', '${s?.supplementsTaken ?? 0}', null, 'Taken today'),
          tile('Meals', '${s?.mealsEaten ?? 0}${(s?.mealsPlanned ?? 0) > 0 ? ' / ${s!.mealsPlanned}' : ''}', (s?.mealsPlanned ?? 0) > 0 ? s!.mealsEaten / s.mealsPlanned : null, 'Eaten'),
        ),
        const SizedBox(height: 12),
        ButtonPair(
          tile('Water', '$water ml', waterTarget == null || waterTarget == 0 ? null : water / waterTarget, waterTarget == null ? 'No target set' : 'of $waterTarget ml'),
          tile('Steps', steps == null ? '–' : '$steps', steps == null || stepTarget == null || stepTarget == 0 ? null : steps / stepTarget, stepTarget == null ? 'No target set' : 'of $stepTarget'),
        ),
      ],
    );
  }
}

class _InsightsCard extends ConsumerWidget {
  const _InsightsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(dailyBriefingProvider(_today()));
    final b = result.briefing;
    final rows = <RowItem>[
      for (final t in (b?.trends ?? const <BriefingTrend>[]).where((t) => t.signal != 'insufficient_data').take(3))
        RowItem(title: '${t.exercise}: ${_words(t.signal)}', subtitle: t.changePct == null ? 'Estimated 1RM, recent sessions' : 'Estimated 1RM ${t.changePct! >= 0 ? '+' : ''}${t.changePct!.toStringAsFixed(1)}% over recent sessions'),
      for (final w in (b?.weakPoints ?? const <BriefingWeakPoint>[]).take(2))
        RowItem(title: '${_words(w.muscleKey)} gets little direct work', subtitle: '${w.directSets28d} direct sets in 4 weeks. Consider it if it fits your split.'),
    ];
    return TitledCard(
      title: 'Insights & suggestions',
      link: 'Progress',
      onLink: () => context.go(AppRoutes.progress),
      children: [
        if (rows.isEmpty) MutedText(result.snapshot.hasData ? 'Nothing to point out right now.' : 'Insights appear once the daily briefing has loaded.') else RowList(rows),
        const _BriefingStatus(),
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

class _RecentActivityCard extends ConsumerWidget {
  const _RecentActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = [for (final s in ref.watch(recentSessionsProvider).valueOrNull ?? const <WorkoutSession>[]) if (s.status == 'completed') s].take(2).toList();
    return TitledCard(
      title: 'Recent activity',
      link: 'History',
      onLink: () => context.go(AppRoutes.training),
      children: [
        if (sessions.isEmpty)
          const MutedText('Finished workouts show up here.')
        else
          RowList([
            for (final s in sessions)
              RowItem(
                title: s.name ?? 'Workout',
                subtitle: '${_short(s.localDate)}${s.endedAt == null ? '' : ' · ${(s.endedAt!.difference(s.startedAt).inMinutes - s.pausedSeconds ~/ 60).clamp(0, 9999)} min'}',
              ),
          ]),
      ],
    );
  }
}

class _HighlightsCard extends ConsumerWidget {
  const _HighlightsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(personalRecordsProvider).valueOrNull ?? const <PersonalRecord>[];
    final achievements = ref.watch(achievementsProvider).valueOrNull ?? const <Achievement>[];
    final names = ref.watch(exerciseNamesProvider);
    return TitledCard(
      title: 'Highlights',
      link: 'Progress',
      onLink: () => context.go(AppRoutes.progress),
      children: [
        if (records.isEmpty && achievements.isEmpty)
          const MutedText('Personal records and achievements are found by the server and appear here when they arrive.')
        else
          RowList([
            for (final r in records.take(2)) RowItem(title: 'Personal record', subtitle: '${names[r.exerciseId] ?? 'Workout'} ${_kg(r.value)} kg · ${_short(r.achievedOn)}'),
            for (final a in achievements.take(1)) RowItem(title: 'Achievement', subtitle: '${a.title} · ${_short(a.achievedOn)}'),
          ]),
      ],
    );
  }
}

class _AlertsCard extends ConsumerWidget {
  const _AlertsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeSessionProvider).valueOrNull;
    final b = ref.watch(dailyBriefingProvider(_today())).briefing;
    final items = <RowItem>[
      if (active != null) RowItem(title: 'Unfinished session', subtitle: active.name ?? 'Workout in progress', trailing: 'Resume ›', onTap: () => context.push(AppRoutes.session)),
      if (b != null && b.reassessmentDue) RowItem(title: 'Reassessment due', subtitle: b.nextReassessmentDate == null ? 'Muscle self-assessment' : 'Muscle self-assessment, ${_short(b.nextReassessmentDate!)}'),
      if (b != null && b.restrictionWarnings.isNotEmpty) RowItem(title: 'Exercise restrictions', subtitle: '${b.restrictionWarnings.length} planned exercise(s) are affected by an injury or restriction'),
      if (b != null && b.supplements.any((s) => s.takenToday < s.expectedDoses)) const RowItem(title: 'Supplements', subtitle: 'Some doses are not logged yet today'),
    ];
    return TitledCard(
      title: 'Alerts',
      children: [if (items.isEmpty) const MutedText('Nothing needs attention.') else RowList(items)],
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
