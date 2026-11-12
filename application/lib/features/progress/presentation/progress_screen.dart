import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/insights/insight_providers.dart';
import '../../../core/insights/insight_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/local_stamp.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/insight_status.dart';
import '../../../core/widgets/meters.dart';
import '../../lifestyle/data/lifestyle_models.dart';
import '../data/progress_insights.dart';
import '../data/progress_models.dart';
import '../data/progress_providers.dart';

/// Progress section: Overview, Strength, Body, Muscles and Goals.
///
/// Two kinds of data, kept visibly apart:
///  - records the phone holds (personal records, achievements, goals, measurements) are shown straight from SQLite;
///  - values the server calculates (trends, goal progress, body-composition estimates, exposure, ratings, streak) come from
///    the insight cache, labelled with how old they are. They are never recalculated here.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  static const _tabs = ['Overview', 'Strength', 'Body', 'Muscles', 'Goals'];
  int _tab = 0;

  List<Widget> _content() {
    switch (_tab) {
      case 1:
        return const [_StrengthTrends(), _E1rmChart(), _PrHistory(full: true)];
      case 2:
        return const [_BodyWeight(), _BodyCompositionCard(), _MeasurementHistory()];
      case 3:
        return const [_MuscleRatings(), _Exposure(), _WeakPoints()];
      case 4:
        return const [_GoalsCard(), _GoalMilestones()];
      default:
        return const [_Highlights(), _StrengthTrends(), _PrHistory(), _BodyLast(), _GoalsCard(), _Exposure()];
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Progress',
      subtitle: 'Your history and change over time',
      children: [
        PillTabs(labels: _tabs, index: _tab, container: true, layout: PillLayout.scroll, onChanged: (i) => setState(() => _tab = i)),
        ..._content(),
      ],
    );
  }
}

// ---- helpers ----

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _dateText(String localDate) {
  final d = DateTime.tryParse(localDate);
  return d == null ? localDate : '${_months[d.month - 1]} ${d.day}';
}

String _kg(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

String _prKind(String kind) => switch (kind) {
      'max_weight' => 'Heaviest weight',
      'est_1rm' => 'Estimated 1RM',
      'best_reps_at_weight' => 'Most reps at this weight',
      'session_volume' => 'Session volume',
      'workout_volume' => 'Workout volume',
      _ => _cap(kind),
    };

String _prValue(PersonalRecord r) => switch (r.kind) {
      'best_reps_at_weight' => '${r.reps ?? _kg(r.value)} reps${r.weightKg == null ? '' : ' @ ${_kg(r.weightKg!)} kg'}',
      _ => '${_kg(r.value)} kg',
    };

/// Axis limits that fit the values, with four ticks.
({double min, double max, List<double> ticks}) _axis(List<double> values) {
  var lo = values.reduce((a, b) => a < b ? a : b);
  var hi = values.reduce((a, b) => a > b ? a : b);
  if (hi - lo < 1) {
    lo -= 1;
    hi += 1;
  }
  final pad = (hi - lo) * 0.1;
  lo = (lo - pad).floorToDouble();
  hi = (hi + pad).ceilToDouble();
  final step = (hi - lo) / 3;
  return (min: lo, max: hi, ticks: [for (var i = 0; i < 4; i++) lo + step * i]);
}

/// X labels for a series: the first, the middle and the last date, blanks elsewhere.
List<String> _xLabels(List<String> dates) => [
      for (var i = 0; i < dates.length; i++) (i == 0 || i == dates.length - 1 || i == dates.length ~/ 2) ? _dateText(dates[i]) : '',
    ];

Widget _gap([double h = 12]) => SizedBox(height: h);

/// Shows the freshness line for a cached answer and refreshes it on request.
class _Status extends ConsumerWidget {
  const _Status(this.spec, this.snapshot);

  final InsightSpec spec;
  final InsightSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) => InsightStatusLine(snapshot: snapshot, onRefresh: () => ref.read(insightProvider(spec).notifier).refresh());
}

// ---- Overview ----

class _Highlights extends ConsumerWidget {
  const _Highlights();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final records = ref.watch(personalRecordsProvider).valueOrNull ?? const <PersonalRecord>[];
    final names = ref.watch(exerciseNamesProvider);
    final achievements = ref.watch(achievementsProvider).valueOrNull ?? const <Achievement>[];
    final briefing = ref.watch(dailyBriefingProvider(localStampOf(DateTime.now()).localDate));
    final latest = records.isEmpty ? null : records.first;
    final streak = briefing.briefing?.currentStreak;

    Widget col(String label, String value, String note) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: p.text, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(note, style: TextStyle(color: p.muted, fontSize: 13)),
          ]),
        );
    return TitledCard(title: 'Recent highlights', children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        col('Latest record', latest == null ? '–' : '${names[latest.exerciseId] ?? 'Workout'} ${_prValue(latest)}', latest == null ? 'None yet' : '${_prKind(latest.kind)} · ${_dateText(latest.achievedOn)}'),
        const SizedBox(width: 12),
        col('Workout streak', streak == null ? '–' : '$streak ${streak == 1 ? 'workout' : 'workouts'}', streak == null ? 'Not loaded yet' : 'Longest ${briefing.briefing?.longestStreak ?? '–'}'),
      ]),
      if (achievements.isNotEmpty) ...[
        _gap(),
        RowList([
          for (final a in achievements.take(2)) RowItem(title: a.title, subtitle: 'Achievement · ${_dateText(a.achievedOn)}'),
        ]),
      ],
      InsightStatusLine(snapshot: briefing.snapshot, onRefresh: () => ref.read(insightProvider(dailyBriefingSpec(localStampOf(DateTime.now()).localDate)).notifier).refresh()),
    ]);
  }
}

class _BodyLast extends ConsumerWidget {
  const _BodyLast();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(measurementsProvider(null)).valueOrNull ?? const <BodyMeasurement>[];
    final latest = <String, BodyMeasurement>{};
    for (final m in all) {
      latest.putIfAbsent(m.type == 'custom' ? 'custom:${m.customLabel}' : m.type, () => m);
    }
    final newest = all.isEmpty ? null : all.first.localDate;
    return TitledCard(title: newest == null ? 'Body' : 'Body · last measured ${_dateText(newest)}', children: [
      if (latest.isEmpty)
        const MutedText('No measurements yet. Log your weight from Home.')
      else
        RowList([for (final m in latest.values.take(4)) _measurementRow(m)]),
    ]);
  }
}

RowItem _measurementRow(BodyMeasurement m) {
  final label = m.type == 'custom' ? (m.customLabel ?? 'Custom') : _cap(m.type);
  final unit = switch (m.type) { 'weight' || 'muscle_mass' => 'kg', 'body_fat' => '%', 'custom' => m.customUnit ?? '', _ => 'cm' };
  return RowItem(title: label, subtitle: '${_dateText(m.localDate)}${m.method == null ? '' : ' · ${_cap(m.method!)}'}', trailing: '${_kg(m.value)} $unit'.trim());
}

// ---- Strength ----

class _StrengthTrends extends ConsumerWidget {
  const _StrengthTrends();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trends = ref.watch(exerciseTrendsProvider);
    final names = ref.watch(exerciseNamesProvider);
    final rows = [for (final t in trends.rows) if (t.signal != 'insufficient_data') t]..sort((a, b) => (names[a.exerciseId] ?? '').compareTo(names[b.exerciseId] ?? ''));
    return TitledCard(title: 'Strength trends', children: [
      const MutedText('From your last four sessions of each exercise (estimated 1RM). An observation, not an instruction.'),
      _gap(10),
      if (rows.isEmpty)
        MutedText(trends.snapshot.hasData ? 'Not enough sessions yet to show a trend.' : 'Trends appear once they have loaded from the server.')
      else
        RowList([
          for (final t in rows.take(8))
            RowItem(
              title: names[t.exerciseId] ?? 'Exercise',
              subtitle: '${t.sessionsConsidered} sessions · last ${_dateText(t.lastSessionDate ?? '')}',
              trailing: '${_cap(t.signal)}${t.changePct == null ? '' : ' ${t.changePct! >= 0 ? '+' : ''}${t.changePct!.toStringAsFixed(1)}%'}',
            ),
        ]),
      _Status(exerciseTrendsSpec, trends.snapshot),
    ]);
  }
}

class _E1rmChart extends ConsumerStatefulWidget {
  const _E1rmChart();

  @override
  ConsumerState<_E1rmChart> createState() => _E1rmChartState();
}

class _E1rmChartState extends ConsumerState<_E1rmChart> {
  int _exercise = 0;
  int _metric = 0;

  @override
  Widget build(BuildContext context) {
    final best = ref.watch(exerciseSessionBestProvider);
    final names = ref.watch(exerciseNamesProvider);
    final byExercise = <String, List<ExerciseSessionBest>>{};
    for (final r in best.rows) {
      byExercise.putIfAbsent(r.exerciseId, () => []).add(r);
    }
    final ids = byExercise.keys.toList()..sort((a, b) => (names[a] ?? '').compareTo(names[b] ?? ''));
    final index = ids.isEmpty ? 0 : _exercise.clamp(0, ids.length - 1);
    final selected = ids.isEmpty ? <ExerciseSessionBest>[] : (byExercise[ids[index]]!..sort((a, b) => a.localDate.compareTo(b.localDate)));
    double? value(ExerciseSessionBest r) => _metric == 0 ? r.topWeightKg : r.bestE1rmKg;
    final points = [for (final r in selected) if (value(r) != null) (r.localDate, value(r)!)];

    return TitledCard(title: 'Strength', children: [
      if (ids.isEmpty)
        const MutedText('Finished workouts with logged sets show up here once they have been calculated by the server.')
      else ...[
        PillTabs(labels: [for (final id in ids.take(12)) names[id] ?? 'Exercise'], index: index, layout: PillLayout.scroll, onChanged: (i) => setState(() => _exercise = i)),
        _gap(10),
        PillTabs(labels: const ['Top set', 'Est. 1RM'], index: _metric, onChanged: (i) => setState(() => _metric = i)),
        _gap(),
        if (points.length < 2)
          const MutedText('At least two sessions are needed to draw a line.')
        else ...[
          Builder(builder: (_) {
            final a = _axis([for (final p in points) p.$2]);
            return LineChartView(values: [for (final p in points) p.$2], xLabels: _xLabels([for (final p in points) p.$1]), yMin: a.min, yMax: a.max, yTicks: a.ticks);
          }),
          _gap(10),
          MutedText('${_metric == 0 ? 'Heaviest working set' : 'Best estimated 1RM'} (kg) per session. Latest ${_kg(points.last.$2)} kg, previous ${_kg(points[points.length - 2].$2)} kg.'),
        ],
      ],
      _Status(exerciseSessionBestSpec, best.snapshot),
    ]);
  }
}

class _PrHistory extends ConsumerWidget {
  const _PrHistory({this.full = false});

  final bool full;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(personalRecordsProvider).valueOrNull ?? const <PersonalRecord>[];
    final names = ref.watch(exerciseNamesProvider);
    final shown = full ? records.take(30) : records.take(3);
    return TitledCard(title: 'PR history', children: [
      if (records.isEmpty)
        const MutedText('Personal records are found by the server after a workout syncs. They appear here when they arrive.')
      else
        RowList([
          for (final r in shown)
            RowItem(
              title: names[r.exerciseId] ?? 'Workout',
              subtitle: '${_prKind(r.kind)} · ${_dateText(r.achievedOn)}${r.previousValue == null ? '' : ' · was ${_kg(r.previousValue!)}'}',
              trailing: _prValue(r),
            ),
        ]),
    ]);
  }
}

// ---- Body ----

class _BodyWeight extends ConsumerStatefulWidget {
  const _BodyWeight();

  @override
  ConsumerState<_BodyWeight> createState() => _BodyWeightState();
}

class _BodyWeightState extends ConsumerState<_BodyWeight> {
  int _range = 1;
  static const _days = [30, 90, 180, 365];

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(measurementsProvider('weight')).valueOrNull ?? const <BodyMeasurement>[];
    final cutoff = DateTime.now().subtract(Duration(days: _days[_range]));
    final inRange = [for (final m in all) if ((m.occurredAt ?? DateTime.now()).isAfter(cutoff)) m].reversed.toList();
    return TitledCard(title: 'Body weight', children: [
      PillTabs(labels: const ['1M', '3M', '6M', '1Y'], index: _range, onChanged: (i) => setState(() => _range = i)),
      _gap(10),
      if (inRange.length < 2)
        const MutedText('Log your weight on at least two days to see a line.')
      else ...[
        Builder(builder: (_) {
          final a = _axis([for (final m in inRange) m.value]);
          return LineChartView(values: [for (final m in inRange) m.value], xLabels: _xLabels([for (final m in inRange) m.localDate]), yMin: a.min, yMax: a.max, yTicks: a.ticks);
        }),
        _gap(10),
        MutedText('Latest ${_kg(inRange.last.value)} kg on ${_dateText(inRange.last.localDate)}. Daily weight moves around; compare longer periods.'),
      ],
    ]);
  }
}

class _BodyCompositionCard extends ConsumerWidget {
  const _BodyCompositionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comp = ref.watch(bodyCompositionProvider);
    final latest = comp.rows.isEmpty ? null : comp.rows.first;
    return TitledCard(title: 'Body composition', children: [
      if (latest == null)
        MutedText(comp.snapshot.hasData ? 'No body-fat readings yet. Add one in Lifestyle.' : 'Body composition appears once it has loaded from the server.')
      else ...[
        RowList([
          if (latest.weightKg != null) RowItem(title: 'Weight', subtitle: _dateText(latest.localDate), trailing: '${_kg(latest.weightKg!)} kg'),
          if (latest.bodyFatPct != null) RowItem(title: 'Body fat', subtitle: latest.method == null ? 'Reading' : _cap(latest.method!), trailing: '${_kg(latest.bodyFatPct!)}%'),
          if (latest.fatMassKg != null) RowItem(title: 'Fat mass', subtitle: 'Estimated: weight × body fat %', trailing: '${_kg(latest.fatMassKg!)} kg'),
          if (latest.leanMassKg != null) RowItem(title: 'Lean mass', subtitle: 'Estimated', trailing: '${_kg(latest.leanMassKg!)} kg'),
        ]),
        _gap(10),
        const MutedText('Fat and lean mass are estimates from one reading. Readings vary by method; compare like with like.'),
      ],
      _Status(bodyCompositionSpec, comp.snapshot),
    ]);
  }
}

class _MeasurementHistory extends ConsumerWidget {
  const _MeasurementHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(measurementsProvider(null)).valueOrNull ?? const <BodyMeasurement>[];
    return TitledCard(title: 'Measurement history', children: [
      if (all.isEmpty) const MutedText('Measurements you log appear here.') else RowList([for (final m in all.take(12)) _measurementRow(m)]),
    ]);
  }
}

// ---- Muscles ----

class _MuscleRatings extends ConsumerWidget {
  const _MuscleRatings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratings = ref.watch(muscleRatingsProvider);
    final rated = [for (final r in ratings.rows) if (r.currentLevel != null) r]..sort((a, b) => a.muscleKey.compareTo(b.muscleKey));
    return TitledCard(title: 'Muscles · your own ratings', children: [
      const MutedText('These are the ratings you entered yourself. They are not calculated from training.'),
      _gap(10),
      if (rated.isEmpty)
        MutedText(ratings.snapshot.hasData ? 'No assessment recorded yet.' : 'Ratings appear once they have loaded from the server.')
      else
        RowList([
          for (final r in rated)
            RowItem(
              title: _cap(r.muscleKey),
              subtitle: '${r.category == null ? '' : '${_cap(r.category!)} · '}${r.ratedOn == null ? '' : _dateText(r.ratedOn!)}',
              trailing: '${r.currentLevel}${r.previousLevel == null ? '' : ' (was ${r.previousLevel})'}',
            ),
        ]),
      _Status(muscleRatingsSpec, ratings.snapshot),
    ]);
  }
}

class _Exposure extends ConsumerWidget {
  const _Exposure();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exposure = ref.watch(muscleExposureProvider);
    final labels = ref.watch(muscleLabelsProvider).valueOrNull ?? const <String, String>{};
    final cutoff = DateTime.now().subtract(const Duration(days: 28));
    final recent = [for (final e in exposure.rows) if ((DateTime.tryParse(e.weekStart) ?? DateTime(2000)).isAfter(cutoff))];
    final totals = <String, int>{};
    for (final e in recent) {
      totals[e.muscleId] = (totals[e.muscleId] ?? 0) + e.directSets;
    }
    final ordered = totals.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return TitledCard(title: 'Training exposure · last 4 weeks', children: [
      const MutedText('Direct working sets per muscle. This counts what you did; it says nothing about how developed a muscle is.'),
      _gap(10),
      if (ordered.isEmpty)
        MutedText(exposure.snapshot.hasData ? 'No working sets in the last four weeks.' : 'Exposure appears once it has loaded from the server.')
      else
        RowList([for (final e in ordered.take(10)) RowItem(title: labels[e.key] ?? 'Muscle', subtitle: 'Direct sets, 4 weeks', trailing: '${e.value}')]),
      _Status(muscleExposureSpec, exposure.snapshot),
    ]);
  }
}

class _WeakPoints extends ConsumerWidget {
  const _WeakPoints();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = localStampOf(DateTime.now()).localDate;
    final briefing = ref.watch(dailyBriefingProvider(today));
    final weak = briefing.briefing?.weakPoints ?? const <BriefingWeakPoint>[];
    return TitledCard(title: 'Muscles that get little direct work', children: [
      if (weak.isEmpty)
        MutedText(briefing.snapshot.hasData ? 'Nothing flagged right now.' : 'Suggestions appear once the daily briefing has loaded.')
      else
        RowList([
          for (final w in weak)
            RowItem(
              title: _cap(w.muscleKey),
              subtitle: '${w.directSets28d} direct sets in 4 weeks${w.suggestions.isEmpty ? '' : ' · e.g. ${w.suggestions.join(', ')}'}',
            ),
        ]),
      _gap(10),
      const MutedText('Suggestions to consider within your split and recovery, not instructions.'),
      InsightStatusLine(snapshot: briefing.snapshot, onRefresh: () => ref.read(insightProvider(dailyBriefingSpec(today)).notifier).refresh()),
    ]);
  }
}

// ---- Goals ----

class _GoalsCard extends ConsumerWidget {
  const _GoalsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final goals = ref.watch(goalsProvider).valueOrNull ?? const <Goal>[];
    final progress = ref.watch(goalProgressProvider);
    final byGoal = {for (final g in progress.rows) g.goalId: g};
    return TitledCard(title: 'Goals', children: [
      if (goals.isEmpty)
        const MutedText('No goals yet.')
      else
        for (final g in goals.take(5)) ...[
          Text(g.title, style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_goalLine(g, byGoal[g.id]), style: TextStyle(color: p.muted, fontSize: 14)),
          const SizedBox(height: 8),
          MeterBar(value: ((byGoal[g.id]?.progressPct ?? 0) / 100).clamp(0, 1).toDouble()),
          _gap(14),
        ],
      if (goals.isNotEmpty) _Status(goalProgressSpec, progress.snapshot),
    ]);
  }

  static String _goalLine(Goal g, GoalProgress? p) {
    final status = _cap(g.status);
    if (p == null) return '$status · progress not loaded yet';
    final value = p.currentValue == null || p.targetValue == null ? '' : '${_kg(p.currentValue!)} / ${_kg(p.targetValue!)}${g.targetUnit == null ? '' : ' ${g.targetUnit}'} · ';
    return '$status · $value${_cap(p.progressStatus)}${p.progressPct == null ? '' : ' (${p.progressPct!.round()}%)'}';
  }
}

class _GoalMilestones extends ConsumerWidget {
  const _GoalMilestones();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final goals = ref.watch(goalsProvider).valueOrNull ?? const <Goal>[];
    final milestones = ref.watch(goalMilestonesProvider);
    final titles = {for (final g in goals) g.id: g.title};
    final shown = [for (final m in milestones.rows) if (titles.containsKey(m.goalId)) m];
    return TitledCard(title: 'Goal milestones', children: [
      if (shown.isEmpty)
        MutedText(milestones.snapshot.hasData ? 'No milestones set for your goals.' : 'Milestones appear once they have loaded from the server.')
      else
        RowList([
          for (final m in shown)
            RowItem(
              title: m.title,
              subtitle: titles[m.goalId],
              trailing: m.isReached ? 'Reached' : '${_kg(m.targetValue)} target',
              trailingColor: m.isReached ? p.green : null,
            ),
        ]),
      _Status(goalMilestonesSpec, milestones.snapshot),
    ]);
  }
}
