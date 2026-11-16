import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/insights/insight_providers.dart';
import '../../../core/insights/insight_repository.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/local_stamp.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/insight_status.dart';
import '../../../core/widgets/meters.dart';
import '../../../core/widgets/section_widgets.dart';
import '../../home/presentation/home_screen.dart' show showLogWeight;
import '../../lifestyle/data/lifestyle_models.dart';
import '../../training/presentation/training_dialogs.dart' show ModalCard;
import '../data/progress_insights.dart';
import '../data/progress_service.dart' show measuredMetrics;
import 'progress_editors.dart';
import '../data/progress_models.dart';
import '../data/progress_providers.dart';

/// Progress section: Overview, Strength, Body, Muscles and Goals.
///
/// Two kinds of data, kept visibly apart:
///  - records the phone holds (personal records, achievements, goals, measurements) are shown straight from SQLite;
///  - values the server calculates (trends, goal progress, body-composition estimates, exposure, ratings, streak) come from
///    the insight cache, labelled with how old they are. They are never recalculated here.
class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  static const _tabs = ['Overview', 'Strength', 'Body', 'Muscles', 'Goals'];
  int _tab = 0;

  void _goTo(int tab) => setState(() => _tab = tab);

  List<Widget> _content() {
    switch (_tab) {
      case 1:
        return const [_StrengthTab()];
      case 2:
        return const [_BodyWeight(), _BodyRows()];
      case 3:
        return const [_MuscleRatings(), _Exposure(), _WeakPoints()];
      case 4:
        return const [_GoalsTab()];
      default:
        return [_Overview(onOpenTab: _goTo)];
    }
  }

  /// "Updated 2 min ago": the newest answer among the server values this screen reads.
  String _updated() {
    final today = localStampOf(DateTime.now()).localDate;
    final stamps = <DateTime?>[
      ref.watch(dailyBriefingProvider(today)).snapshot.fetchedAt,
      ref.watch(exerciseTrendsProvider).snapshot.fetchedAt,
      ref.watch(goalProgressProvider).snapshot.fetchedAt,
      ref.watch(muscleExposureProvider).snapshot.fetchedAt,
    ].whereType<DateTime>().toList()..sort();
    return stamps.isEmpty
        ? 'Not updated yet'
        : 'Updated ${ageText(stamps.last)}';
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Progress',
      subtitle: _updated(),
      trailing: HeaderIconButton(
        key: const Key('progress-info'),
        icon: Icons.info_outline,
        tooltip: 'About these numbers',
        onTap:
            () => showDialog<void>(
              context: context,
              builder: (_) => const _AboutDialog(),
            ),
      ),
      children: [
        UnderlineTabs(
          labels: _tabs,
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        ..._content(),
      ],
    );
  }
}

class _AboutDialog extends ConsumerWidget {
  const _AboutDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = localStampOf(DateTime.now()).localDate;
    return ModalCard(
      title: 'About these numbers',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Records, weights and goals are kept on this phone. Trends, goal progress, exposure and ratings are calculated by the server and shown with how old they are. They are never recalculated here.\n\nNot medical advice.',
            style: TextStyle(color: p.text, fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 16),
          AppButton(
            'Refresh now',
            key: const Key('progress-refresh'),
            onPressed: () {
              for (final spec in [
                dailyBriefingSpec(today),
                exerciseTrendsSpec,
                exerciseSessionBestSpec,
                goalProgressSpec,
                goalMilestonesSpec,
                muscleExposureSpec,
                muscleRatingsSpec,
                bodyCompositionSpec,
              ]) {
                ref.read(insightProvider(spec).notifier).refresh();
              }
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

// ---- helpers ----

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _dateText(String localDate) {
  final d = DateTime.tryParse(localDate);
  return d == null ? localDate : '${_months[d.month - 1]} ${d.day}';
}

String _kg(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _cap(String s) =>
    s.isEmpty
        ? s
        : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

String _prKind(String kind) => switch (kind) {
  'max_weight' => 'Heaviest weight',
  'est_1rm' => 'Estimated 1RM',
  'best_reps_at_weight' => 'Most reps at this weight',
  'session_volume' => 'Session volume',
  'workout_volume' => 'Workout volume',
  _ => _cap(kind),
};

String _prValue(PersonalRecord r) => switch (r.kind) {
  'best_reps_at_weight' =>
    '${r.reps ?? _kg(r.value)} reps${r.weightKg == null ? '' : ' @ ${_kg(r.weightKg!)} kg'}',
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
  for (var i = 0; i < dates.length; i++)
    (i == 0 || i == dates.length - 1 || i == dates.length ~/ 2)
        ? _dateText(dates[i])
        : '',
];

Widget _gap([double h = 12]) => SizedBox(height: h);

/// Shows the freshness line for a cached answer and refreshes it on request.
class _Status extends ConsumerWidget {
  const _Status(this.spec, this.snapshot);

  final InsightSpec spec;
  final InsightSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) => InsightStatusLine(
    snapshot: snapshot,
    onRefresh: () => ref.read(insightProvider(spec).notifier).refresh(),
  );
}

RowItem _measurementRow(BodyMeasurement m) {
  final label = m.type == 'custom' ? (m.customLabel ?? 'Custom') : _cap(m.type);
  final unit = switch (m.type) {
    'weight' || 'muscle_mass' => 'kg',
    'body_fat' => '%',
    'custom' => m.customUnit ?? '',
    _ => 'cm',
  };
  return RowItem(
    title: label,
    subtitle:
        '${_dateText(m.localDate)}${m.method == null ? '' : ' · ${_cap(m.method!)}'}',
    trailing: '${_kg(m.value)} $unit'.trim(),
  );
}

/// Shown under a card when its server answer could not be loaded or is old. Healthy answers add nothing.
class _Problem extends ConsumerWidget {
  const _Problem(this.spec, this.snapshot);

  final InsightSpec spec;
  final InsightSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthy =
        snapshot.hasData &&
        snapshot.error == null &&
        snapshot.freshness != InsightFreshness.stale;
    if (healthy) return const SizedBox.shrink();
    return _Status(spec, snapshot);
  }
}

// ---- Overview ----

class _Overview extends ConsumerWidget {
  const _Overview({required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = localStampOf(DateTime.now()).localDate;
    final records =
        ref.watch(personalRecordsProvider).valueOrNull ??
        const <PersonalRecord>[];
    final names = ref.watch(exerciseNamesProvider);
    final briefing = ref.watch(dailyBriefingProvider(today));
    final weights =
        ref.watch(measurementsProvider('weight')).valueOrNull ??
        const <BodyMeasurement>[];
    final goals = ref.watch(goalsProvider).valueOrNull ?? const <Goal>[];
    final progress = ref.watch(goalProgressProvider);
    final goal =
        goals
            .where((g) => g.status == 'active')
            .followedBy(goals.where((g) => g.status == 'paused'))
            .firstOrNull;
    final gp = goal == null ? null : _progressFor(progress, goal.id);
    final latest = records.isEmpty ? null : records.first;
    final streak = briefing.briefing?.currentStreak;
    final longest = briefing.briefing?.longestStreak;
    final w = weights.isEmpty ? null : weights.first;
    final trends = ref.watch(exerciseTrendsProvider);
    final trendRows = [
      for (final t in trends.rows)
        if (t.signal != 'insufficient_data') t,
    ];
    final exposure = ref.watch(muscleExposureProvider);
    final labels =
        ref.watch(muscleLabelsProvider).valueOrNull ?? const <String, String>{};
    final totals = _exposureTotals(exposure.rows);

    Widget tile(
      Key key,
      String label,
      String value,
      String link,
      String note,
      VoidCallback onTap, {
      double fill = 0,
    }) => Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: p.muted, fontSize: 15)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: p.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            MeterBar(value: fill.clamp(0, 1).toDouble(), trackColor: p.tile),
            const SizedBox(height: 10),
            LinkText(link, onTap: onTap),
            const SizedBox(height: 2),
            Text(
              note,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 15),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(
                const Key('tile-record'),
                'Latest record',
                latest == null ? '–' : _prValue(latest),
                'See records',
                latest == null
                    ? 'None yet'
                    : '${names[latest.exerciseId] ?? 'Workout'} · ${_dateText(latest.achievedOn)}',
                () => onOpenTab(1),
              ),
              const SizedBox(width: 12),
              tile(
                const Key('tile-streak'),
                'Workout streak',
                streak == null ? '–' : '$streak',
                'See streak',
                'workouts in a row',
                () => context.go(AppRoutes.training),
                fill:
                    streak == null || longest == null || longest == 0
                        ? 0
                        : streak / longest,
              ),
            ],
          ),
        ),
        _gap(),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(
                const Key('tile-weight'),
                'Weight',
                w == null ? '–' : '${_kg(w.value)} kg',
                'See body',
                w == null ? 'No weight yet' : _dateText(w.localDate),
                () => onOpenTab(2),
              ),
              const SizedBox(width: 12),
              tile(
                const Key('tile-goal'),
                'Goal',
                goal == null ? 'None' : goal.title,
                'See goals',
                goal == null
                    ? 'No active goal'
                    : '${_cap(goal.status)} · ${gp == null ? 'progress not loaded' : _cap(gp.progressStatus)}',
                () => onOpenTab(4),
                fill: (gp?.progressPct ?? 0) / 100,
              ),
            ],
          ),
        ),
        _gap(),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardTitle('Strength trends'),
              if (trendRows.isEmpty)
                NoteRow(
                  trends.snapshot.hasData
                      ? 'Log two sessions of an exercise to see a trend.'
                      : 'Trends appear once they have loaded from the server.',
                )
              else
                RowList([
                  for (final t in (trendRows..sort((a, b) => (names[a.exerciseId] ?? '').compareTo(names[b.exerciseId] ?? ''))).take(3))
                    RowItem(
                      title: names[t.exerciseId] ?? 'Exercise',
                      subtitle: '${t.sessionsConsidered} sessions',
                      trailing:
                          '${_cap(t.signal)}${t.changePct == null ? '' : ' ${t.changePct! >= 0 ? '+' : ''}${t.changePct!.toStringAsFixed(1)}%'}',
                    ),
                ]),
            ],
          ),
        ),
        _gap(),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _CardTitle('Training exposure · 4 weeks'),
              if (totals.isEmpty)
                NoteRow(
                  exposure.snapshot.hasData
                      ? 'No counted working sets yet.'
                      : 'Exposure appears once it has loaded from the server.',
                )
              else
                _ExposureBars(totals: totals, labels: labels, limit: 4),
            ],
          ),
        ),
        _gap(),
        const InfoLine('Calculated by the server. Not medical advice.'),
        _Problem(exerciseTrendsSpec, trends.snapshot),
        _Problem(muscleExposureSpec, exposure.snapshot),
      ],
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text, {this.sub});

  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              color: p.text,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(sub!, style: TextStyle(color: p.muted, fontSize: 16)),
          ],
        ],
      ),
    );
  }
}

GoalProgress? _progressFor(InsightRows<GoalProgress> progress, String goalId) {
  for (final r in progress.rows) {
    if (r.goalId == goalId) return r;
  }
  return null;
}

/// Direct working sets per muscle over the last four weeks, least first.
List<MapEntry<String, double>> _exposureTotals(List<MuscleExposure> rows) {
  final cutoff = DateTime.now().subtract(const Duration(days: 28));
  final totals = <String, double>{};
  for (final e in rows) {
    if ((DateTime.tryParse(e.weekStart) ?? DateTime(2000)).isAfter(cutoff)) {
      totals[e.muscleId] = (totals[e.muscleId] ?? 0.0) + e.directSets;
    }
  }
  return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// One bar per muscle: longer and darker means more direct sets.
class _ExposureBars extends StatelessWidget {
  const _ExposureBars({
    required this.totals,
    required this.labels,
    required this.limit,
  });

  final List<MapEntry<String, double>> totals;
  final Map<String, String> labels;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final shown = totals.take(limit).toList();
    final top = shown.isEmpty ? 1.0 : shown.first.value;
    return Column(
      children: [
        for (final e in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 104,
                  child: Text(
                    labels[e.key] ?? 'Muscle',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.text, fontSize: 15),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Stack(
                      children: [
                        Container(height: 12, color: p.tile),
                        FractionallySizedBox(
                          widthFactor: top == 0 ? 0 : (e.value / top).clamp(0.05, 1),
                          child: Container(
                            height: 12,
                            color: p.primary.withValues(
                              alpha: top == 0 ? 0.4 : 0.35 + 0.65 * (e.value / top),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${e.value.round()}',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: p.muted, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---- Strength ----
// ---- Strength ----

class _StrengthTrends extends ConsumerWidget {
  const _StrengthTrends();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trends = ref.watch(exerciseTrendsProvider);
    final names = ref.watch(exerciseNamesProvider);
    final rows = [
      for (final t in trends.rows)
        if (t.signal != 'insufficient_data') t,
    ]..sort(
      (a, b) =>
          (names[a.exerciseId] ?? '').compareTo(names[b.exerciseId] ?? ''),
    );
    return TitledCard(
      title: 'Strength trends',
      children: [
        const MutedText(
          'From your last four sessions of each exercise (estimated 1RM). An observation, not an instruction.',
        ),
        _gap(10),
        if (rows.isEmpty)
          MutedText(
            trends.snapshot.hasData
                ? 'Not enough sessions yet to show a trend.'
                : 'Trends appear once they have loaded from the server.',
          )
        else
          RowList([
            for (final t in rows.take(8))
              RowItem(
                title: names[t.exerciseId] ?? 'Exercise',
                subtitle:
                    '${t.sessionsConsidered} sessions · last ${_dateText(t.lastSessionDate ?? '')}',
                trailing:
                    '${_cap(t.signal)}${t.changePct == null ? '' : ' ${t.changePct! >= 0 ? '+' : ''}${t.changePct!.toStringAsFixed(1)}%'}',
              ),
          ]),
        _Status(exerciseTrendsSpec, trends.snapshot),
      ],
    );
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
    final ids =
        byExercise.keys.toList()
          ..sort((a, b) => (names[a] ?? '').compareTo(names[b] ?? ''));
    final index = ids.isEmpty ? 0 : _exercise.clamp(0, ids.length - 1);
    final selected =
        ids.isEmpty
            ? <ExerciseSessionBest>[]
            : (byExercise[ids[index]]!
              ..sort((a, b) => a.localDate.compareTo(b.localDate)));
    double? value(ExerciseSessionBest r) =>
        _metric == 0 ? r.topWeightKg : r.bestE1rmKg;
    final points = [
      for (final r in selected)
        if (value(r) != null) (r.localDate, value(r)!),
    ];

    return TitledCard(
      title: 'Strength',
      children: [
        if (ids.isEmpty)
          const MutedText(
            'Finished workouts with logged sets show up here once they have been calculated by the server.',
          )
        else ...[
          PillTabs(
            labels: [for (final id in ids.take(12)) names[id] ?? 'Exercise'],
            index: index,
            layout: PillLayout.scroll,
            onChanged: (i) => setState(() => _exercise = i),
          ),
          _gap(10),
          PillTabs(
            labels: const ['Top set', 'Est. 1RM'],
            index: _metric,
            onChanged: (i) => setState(() => _metric = i),
          ),
          _gap(),
          if (points.length < 2)
            const MutedText('At least two sessions are needed to draw a line.')
          else ...[
            Builder(
              builder: (_) {
                final a = _axis([for (final p in points) p.$2]);
                return LineChartView(
                  values: [for (final p in points) p.$2],
                  xLabels: _xLabels([for (final p in points) p.$1]),
                  yMin: a.min,
                  yMax: a.max,
                  yTicks: a.ticks,
                );
              },
            ),
            _gap(10),
            MutedText(
              '${_metric == 0 ? 'Heaviest working set' : 'Best estimated 1RM'} (kg) per session. Latest ${_kg(points.last.$2)} kg, previous ${_kg(points[points.length - 2].$2)} kg.',
            ),
          ],
        ],
        _Status(exerciseSessionBestSpec, best.snapshot),
      ],
    );
  }
}

class _PrHistory extends ConsumerWidget {
  const _PrHistory({this.full = false});

  final bool full;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records =
        ref.watch(personalRecordsProvider).valueOrNull ??
        const <PersonalRecord>[];
    final names = ref.watch(exerciseNamesProvider);
    final shown = full ? records.take(30) : records.take(3);
    return TitledCard(
      title: 'PR history',
      children: [
        if (records.isEmpty)
          const MutedText(
            'Personal records are found by the server after a workout syncs. They appear here when they arrive.',
          )
        else
          RowList([
            for (final r in shown)
              RowItem(
                title: names[r.exerciseId] ?? 'Workout',
                subtitle:
                    '${_prKind(r.kind)} · ${_dateText(r.achievedOn)}${r.previousValue == null ? '' : ' · was ${_kg(r.previousValue!)}'}',
                trailing: _prValue(r),
              ),
          ]),
      ],
    );
  }
}

class _StrengthTab extends ConsumerStatefulWidget {
  const _StrengthTab();

  @override
  ConsumerState<_StrengthTab> createState() => _StrengthTabState();
}

class _StrengthTabState extends ConsumerState<_StrengthTab> {
  int? _open;

  @override
  Widget build(BuildContext context) {
    final trends = ref.watch(exerciseTrendsProvider);
    final best = ref.watch(exerciseSessionBestProvider);
    final records =
        ref.watch(personalRecordsProvider).valueOrNull ??
        const <PersonalRecord>[];
    final trendCount =
        trends.rows.where((t) => t.signal != 'insufficient_data').length;
    final bestCount = {for (final r in best.rows) r.exerciseId}.length;
    final has = [trendCount > 0, bestCount > 0, records.isNotEmpty];
    final open = _open ?? has.indexOf(true);
    String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

    Widget detail() => switch (open) {
      0 => const _StrengthTrends(),
      1 => const _E1rmChart(),
      2 => const _PrHistory(full: true),
      _ => const SizedBox.shrink(),
    };
    void toggle(int i) => setState(() => _open = open == i ? -1 : i);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: RowList([
            RowItem(
              key: const Key('strength-row-trends'),
              title: 'Strength trends',
              subtitle: 'Estimated 1RM, last four sessions',
              trailing: trendCount == 0 ? 'No data' : plural(trendCount, 'exercise', 'exercises'),
              onTap: () => toggle(0),
            ),
            RowItem(
              key: const Key('strength-row-chart'),
              title: 'Strength',
              subtitle: 'Finished workouts with logged sets',
              trailing: bestCount == 0 ? 'No data' : plural(bestCount, 'exercise', 'exercises'),
              onTap: () => toggle(1),
            ),
            RowItem(
              key: const Key('strength-row-prs'),
              title: 'PR history',
              subtitle: 'Found after a workout syncs',
              trailing: records.isEmpty ? 'No records' : plural(records.length, 'record', 'records'),
              onTap: () => toggle(2),
            ),
          ]),
        ),
        if (!has.contains(true)) ...[
          _gap(),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _CardTitle('Nothing to show yet'),
                NoteRow('Complete a workout with logged sets and your trends will appear here.'),
              ],
            ),
          ),
        ] else if (open >= 0) ...[
          _gap(),
          detail(),
        ],
        _gap(),
        const InfoLine('Estimates are from your records, not direct measurements.'),
        _Problem(exerciseTrendsSpec, trends.snapshot),
      ],
    );
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
    final p = context.pal;
    final all =
        ref.watch(measurementsProvider('weight')).valueOrNull ??
        const <BodyMeasurement>[];
    final cutoff = DateTime.now().subtract(Duration(days: _days[_range]));
    final inRange =
        [
          for (final m in all)
            if ((m.occurredAt ?? DateTime.now()).isAfter(cutoff)) m,
        ].reversed.toList();
    final latest = all.isEmpty ? null : all.first;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            latest == null
                ? 'Body weight'
                : 'Body weight · ${_dateText(latest.localDate)}',
            style: TextStyle(color: p.muted, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            latest == null ? '–' : '${_kg(latest.value)} kg',
            key: const Key('body-weight-value'),
            style: TextStyle(
              color: p.text,
              fontSize: 40,
              fontWeight: FontWeight.w800,
            ),
          ),
          _gap(10),
          PillTabs(
            labels: const ['1M', '3M', '6M', '1Y'],
            index: _range,
            container: true,
            onChanged: (i) => setState(() => _range = i),
          ),
          _gap(14),
          if (inRange.length < 2) ...[
            SizedBox(
              height: 120,
              child: CustomPaint(
                painter: _BaselineDot(
                  line: p.divider,
                  dot: p.primary,
                  show: inRange.length == 1,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Log your weight on at least two days to see a line.',
              style: TextStyle(color: p.muted, fontSize: 15),
            ),
          ] else ...[
            Builder(
              builder: (_) {
                final a = _axis([for (final m in inRange) m.value]);
                return LineChartView(
                  values: [for (final m in inRange) m.value],
                  xLabels: _xLabels([for (final m in inRange) m.localDate]),
                  yMin: a.min,
                  yMax: a.max,
                  yTicks: a.ticks,
                );
              },
            ),
            _gap(10),
            MutedText(
              'Daily weight moves around; compare longer periods.',
              size: 14,
            ),
          ],
          _gap(14),
          AppButton(
            'Log weight',
            key: const Key('progress-log-weight'),
            height: 56,
            onPressed: () => showLogWeight(context),
          ),
        ],
      ),
    );
  }
}

class _BaselineDot extends CustomPainter {
  _BaselineDot({required this.line, required this.dot, required this.show});

  final Color line;
  final Color dot;
  final bool show;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 8;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = line
        ..strokeWidth = 1.5,
    );
    if (show) {
      canvas.drawCircle(Offset(size.width * 0.7, y), 5, Paint()..color = dot);
    }
  }

  @override
  bool shouldRepaint(_BaselineDot old) => old.show != show;
}

class _BodyRows extends ConsumerWidget {
  const _BodyRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comp = ref.watch(bodyCompositionProvider);
    final latestComp = comp.rows.isEmpty ? null : comp.rows.first;
    final all =
        ref.watch(measurementsProvider(null)).valueOrNull ??
        const <BodyMeasurement>[];
    final weights =
        ref.watch(measurementsProvider('weight')).valueOrNull ??
        const <BodyMeasurement>[];
    final w = weights.isEmpty ? null : weights.first;
    final fat = latestComp?.bodyFatPct;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: RowList([
              RowItem(
                key: const Key('body-composition-row'),
                title: 'Body composition',
                subtitle:
                    fat == null
                        ? (comp.snapshot.hasData
                            ? 'No body-fat readings yet'
                            : 'Appears once it has loaded')
                        : 'Body fat${latestComp?.method == null ? '' : ' · ${_cap(latestComp!.method!)}'}',
                trailing: fat == null ? 'Add in Lifestyle' : '${_kg(fat)}%',
                onTap:
                    fat == null
                        ? () => context.go(AppRoutes.lifestyle)
                        : () => showDialog<void>(
                          context: context,
                          builder: (_) => _CompositionDialog(latestComp!),
                        ),
              ),
              RowItem(
                key: const Key('body-weight-row'),
                title: 'Weight',
                subtitle: w == null ? 'No weight yet' : _dateText(w.localDate),
                trailing: w == null ? '–' : '${_kg(w.value)} kg',
                onTap:
                    all.isEmpty
                        ? null
                        : () => showDialog<void>(
                          context: context,
                          builder: (_) => ModalCard(
                            title: 'Measurement history',
                            child: RowList([
                              for (final m in all.take(12)) _measurementRow(m),
                            ]),
                          ),
                        ),
              ),
            ]),
          ),
          _Problem(bodyCompositionSpec, comp.snapshot),
        ],
      ),
    );
  }
}

class _CompositionDialog extends StatelessWidget {
  const _CompositionDialog(this.latest);

  final BodyComposition latest;

  @override
  Widget build(BuildContext context) {
    return ModalCard(
      title: 'Body composition',
      subtitle: _dateText(latest.localDate),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RowList([
            if (latest.weightKg != null)
              RowItem(
                title: 'Weight',
                trailing: '${_kg(latest.weightKg!)} kg',
              ),
            if (latest.bodyFatPct != null)
              RowItem(
                title: 'Body fat',
                subtitle:
                    latest.method == null ? 'Reading' : _cap(latest.method!),
                trailing: '${_kg(latest.bodyFatPct!)}%',
              ),
            if (latest.fatMassKg != null)
              RowItem(
                title: 'Fat mass',
                subtitle: 'Estimated: weight × body fat %',
                trailing: '${_kg(latest.fatMassKg!)} kg',
              ),
            if (latest.leanMassKg != null)
              RowItem(
                title: 'Lean mass',
                subtitle: 'Estimated',
                trailing: '${_kg(latest.leanMassKg!)} kg',
              ),
          ]),
          const SizedBox(height: 12),
          const MutedText(
            'Fat and lean mass are estimates from one reading. Readings vary by method; compare like with like.',
          ),
        ],
      ),
    );
  }
}

// ---- Muscles ----

class _MuscleRatings extends ConsumerWidget {
  const _MuscleRatings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratings = ref.watch(muscleRatingsProvider);
    final rated = [
      for (final r in ratings.rows)
        if (r.currentLevel != null) r,
    ]..sort((a, b) => a.muscleKey.compareTo(b.muscleKey));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            'Your ratings',
            sub:
                'Ratings you entered yourself. Not calculated from training.',
          ),
          if (rated.isNotEmpty) ...[
            RowList([
              for (final r in rated)
                RowItem(
                  title: _cap(r.muscleKey),
                  subtitle:
                      '${r.category == null ? '' : '${_cap(r.category!)} · '}${r.ratedOn == null ? '' : _dateText(r.ratedOn!)}',
                  trailing:
                      '${r.currentLevel}${r.previousLevel == null ? '' : ' (was ${r.previousLevel})'}',
                ),
            ]),
            _gap(12),
          ] else if (!ratings.snapshot.hasData) ...[
            const MutedText('Ratings appear once they have loaded from the server.'),
            _gap(12),
          ],
          AppButton.primary(
            rated.isEmpty ? 'Rate your muscles' : 'Update your ratings',
            height: 58,
            onPressed: () => showAssessmentSheet(context),
          ),
          _Problem(muscleRatingsSpec, ratings.snapshot),
        ],
      ),
    );
  }
}

class _Exposure extends ConsumerWidget {
  const _Exposure();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exposure = ref.watch(muscleExposureProvider);
    final labels =
        ref.watch(muscleLabelsProvider).valueOrNull ?? const <String, String>{};
    final totals = _exposureTotals(exposure.rows);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle(
              'Training exposure · 4 weeks',
              sub: 'Direct working sets per muscle from finished workouts.',
            ),
            if (totals.isEmpty)
              NoteRow(
                exposure.snapshot.hasData
                    ? 'No counted sets yet.'
                    : 'Exposure appears once it has loaded from the server.',
              )
            else
              _ExposureBars(totals: totals, labels: labels, limit: 10),
            const SizedBox(height: 12),
            const MutedText('Darker bar = more direct sets.', size: 15),
            _Problem(muscleExposureSpec, exposure.snapshot),
          ],
        ),
      ),
    );
  }
}

class _WeakPoints extends ConsumerWidget {
  const _WeakPoints();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = localStampOf(DateTime.now()).localDate;
    final briefing = ref.watch(dailyBriefingProvider(today));
    final weak = briefing.briefing?.weakPoints ?? const <BriefingWeakPoint>[];
    final exposure = ref.watch(muscleExposureProvider);
    final ratings = ref.watch(muscleRatingsProvider);
    final cutoff = DateTime.now().subtract(const Duration(days: 28));
    final hasSets = exposure.rows.any(
      (e) =>
          e.directSets > 0 &&
          (DateTime.tryParse(e.weekStart) ?? DateTime(2000)).isAfter(cutoff),
    );
    final hasRatings = ratings.rows.any((r) => r.currentLevel != null);
    final String empty;
    if (!briefing.snapshot.hasData) {
      empty = 'Suggestions appear once the daily briefing has loaded.';
    } else if (!hasSets && !hasRatings) {
      empty = 'Log workouts with sets, or rate your muscles, to get suggestions.';
    } else {
      empty = 'No low-exposure muscles detected from the data you have.';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Muscles with little direct work'),
            if (weak.isEmpty)
              NoteRow(empty)
            else ...[
              RowList([
                for (final w in weak)
                  RowItem(
                    title: _cap(w.muscleKey),
                    subtitle:
                        '${w.directSets28d} direct sets in 4 weeks${w.suggestions.isEmpty ? '' : ' · e.g. ${w.suggestions.join(', ')}'}',
                  ),
              ]),
              _gap(10),
              const MutedText(
                'Suggestions to consider within your split and recovery, not instructions.',
                size: 14,
              ),
            ],
            _Problem(dailyBriefingSpec(today), briefing.snapshot),
          ],
        ),
      ),
    );
  }
}

// ---- Goals ----

class _GoalsTab extends ConsumerWidget {
  const _GoalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final goals = ref.watch(goalsProvider).valueOrNull ?? const <Goal>[];
    final all = ref.watch(allGoalsProvider).valueOrNull ?? const <Goal>[];
    final shownIds = {for (final g in goals) g.id};
    final archived = [
      for (final g in all)
        if (!shownIds.contains(g.id)) g,
    ];
    final progress = ref.watch(goalProgressProvider);
    final byGoal = {for (final g in progress.rows) g.goalId: g};

    final milestoneRows = <Widget>[];
    final reached = {
      for (final m in ref.watch(goalMilestonesProvider).rows)
        m.milestoneId: m.isReached,
    };
    var milestoneCount = 0;
    for (final g in [...goals, ...archived]) {
      final local =
          ref.watch(milestonesProvider(g.id)).valueOrNull ??
          const <Milestone>[];
      for (final m in local) {
        milestoneCount++;
        final r = reached[m.id];
        milestoneRows.add(
          RowItem(
            title: m.title,
            subtitle: g.title,
            trailing:
                r == true
                    ? 'Reached'
                    : (r == null
                        ? '${_kg(m.targetValue)} · not checked yet'
                        : '${_kg(m.targetValue)} target'),
            trailingColor: r == true ? p.green : null,
            chevron: true,
            onTap: () => showMilestoneEditor(context, g.id, milestone: m),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (goals.isEmpty)
          const AppCard(
            child: NoteRow('No goals yet. Create one to track it here.'),
          ),
        for (final g in goals) ...[
          InkWell(
            key: Key('goal-${g.id}'),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            onTap: () => showGoalActions(context, g),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          g.title,
                          style: TextStyle(
                            color: p.text,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusPill(_cap(g.status)),
                    ],
                  ),
                  if (_isOpen(g)) ...[
                    const SizedBox(height: 14),
                    MeterBar(
                      value:
                          ((byGoal[g.id]?.progressPct ?? 0) / 100)
                              .clamp(0, 1)
                              .toDouble(),
                      trackColor: p.tile,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    _goalLine(g, byGoal[g.id]),
                    style: TextStyle(color: p.muted, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          _gap(),
        ],
        AppButton.primary(
          'New goal',
          height: 58,
          onPressed: () => showGoalEditor(context),
        ),
        _gap(),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: RowList([
            RowItem(
              key: const Key('archived-goals-row'),
              title: 'Archived goals (${archived.length})',
              subtitle:
                  archived.isEmpty
                      ? 'None'
                      : '${archived.first.title} (${_closedWord(archived.first)})${_targetText(archived.first)}',
              chevron: true,
              onTap:
                  archived.isEmpty
                      ? null
                      : () => showDialog<void>(
                        context: context,
                        builder:
                            (dialog) => ModalCard(
                              title: 'Archived goals',
                              child: RowList([
                                for (final g in archived)
                                  RowItem(
                                    title: g.title,
                                    subtitle:
                                        '${_closedWord(g)}${_targetText(g)}',
                                    chevron: true,
                                    onTap: () {
                                      Navigator.of(dialog).pop();
                                      showGoalActions(context, g);
                                    },
                                  ),
                              ]),
                            ),
                      ),
            ),
            RowItem(
              key: const Key('milestones-row'),
              title: 'Milestones',
              subtitle:
                  milestoneCount == 0
                      ? 'None yet. Open a goal to add one.'
                      : '$milestoneCount across your goals',
              chevron: true,
              onTap:
                  milestoneCount == 0
                      ? null
                      : () => showDialog<void>(
                        context: context,
                        builder:
                            (_) => ModalCard(
                              title: 'Milestones',
                              child: RowList(milestoneRows),
                            ),
                      ),
            ),
          ]),
        ),
        _gap(),
        const InfoLine(
          'Tap a goal to edit, record progress, pause, complete or archive it.',
        ),
        _Problem(goalProgressSpec, progress.snapshot),
        _Problem(goalMilestonesSpec, ref.watch(goalMilestonesProvider).snapshot),
      ],
    );
  }

  static bool _isOpen(Goal g) => g.status == 'active' || g.status == 'paused';

  static String _closedWord(Goal g) =>
      g.status == 'abandoned' ? 'archived' : g.status;

  static String _targetText(Goal g) =>
      g.targetValue == null
          ? ''
          : ' · target ${_kg(g.targetValue!)}${g.targetUnit == null ? '' : ' ${g.targetUnit}'}';

  /// Completed goals are closed: the server's progress percentage no longer applies, so it is not shown.
  static String _goalLine(Goal g, GoalProgress? p) {
    if (!_isOpen(g)) return 'Finished${_targetText(g)}';
    if (p == null) return 'Progress not loaded yet${_targetText(g)}';
    if (p.progressStatus == 'insufficient_data') {
      return 'Not enough data yet. ${_missing(g)}';
    }
    final value =
        p.currentValue == null || p.targetValue == null
            ? ''
            : '${_kg(p.currentValue!)} / ${_kg(p.targetValue!)}${g.targetUnit == null ? '' : ' ${g.targetUnit}'} · ';
    return '$value${_cap(p.progressStatus)}${p.progressPct == null ? '' : ' (${p.progressPct!.round()}%)'}';
  }

  static String _missing(Goal g) {
    final m = g.targetMetric;
    if (g.targetValue == null) return 'Set a target value.';
    if (m == null || m.isEmpty) return 'Record values with "Record progress".';
    if (measuredMetrics.containsKey(m)) {
      return 'Log ${measuredMetrics[m]!.$1.toLowerCase()} on or after the start date.';
    }
    return 'Needs logged workouts for that exercise.';
  }
}
