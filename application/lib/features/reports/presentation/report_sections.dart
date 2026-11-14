import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/meters.dart';
import '../data/report_models.dart';
import 'report_format.dart';

/// The note under figures the app only shows: what they are and where they come from.
class KindNote extends StatelessWidget {
  const KindNote(this.kind, {super.key});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final text = valueKindNote(kind);
    if (text == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 10), child: MutedText(text, size: 12));
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.blocks);
  final List<StatBlock> blocks;

  @override
  Widget build(BuildContext context) => Row(children: [for (final b in blocks) Expanded(child: b)]);
}

Widget _gap([double h = 12]) => SizedBox(height: h);

Widget _empty(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: MutedText(text));

/// Overview: headline figures, consistency, observations and the comparison.
class OverviewSection extends StatelessWidget {
  const OverviewSection({super.key, required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = summary.training;
    final a = t.attendance;
    final p = context.pal;
    final nothing = t.sessions == 0 && summary.body.measurements.isEmpty && summary.lifestyle.stepDaysLogged == 0 && summary.recovery.checkinDays == 0 && summary.recovery.sleepNights == 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TitledCard(title: summary.period.label.isEmpty ? 'This period' : summary.period.label, children: [
        MutedText(summary.period.start == null ? '${summary.period.days} days' : '${fmtDate(summary.period.start)} to ${fmtDate(summary.period.end)} · ${summary.period.days} days'),
        _gap(),
        _StatRow([StatBlock('${t.sessions}', 'Workouts'), StatBlock(fmtNum(t.volumeKg, decimals: 0), 'Volume (kg)'), StatBlock('${t.workingSets}', 'Working sets')]),
        _gap(),
        _StatRow([StatBlock('${t.totalReps}', 'Total reps'), StatBlock(t.avgDurationMin == null ? '—' : '${fmtNum(t.avgDurationMin, decimals: 0)} min', 'Avg duration'), StatBlock('${summary.strength.records.length}', 'Records')]),
        if (nothing) ...[_gap(), _empty('No records were found in this period. Finished workouts with logged sets, measurements and daily logs appear here once the server has them.')],
      ]),
      _gap(16),
      TitledCard(title: 'Consistency', children: [
        if (a.scheduled == 0)
          _empty('No scheduled training days in this period, so there is no consistency figure.')
        else ...[
          Row(children: [
            RingGauge(value: (a.consistencyPct ?? 0) / 100, centerText: fmtPct(a.consistencyPct), subText: '${a.completed} of ${a.scheduled}', size: 96, stroke: 9),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${a.completed} of ${a.scheduled} scheduled sessions completed', style: TextStyle(color: p.text, fontSize: 15)),
                const SizedBox(height: 4),
                MutedText('${a.missed} missed · ${a.breakDays} on planned breaks'),
              ]),
            ),
          ]),
        ],
        const SizedBox(height: 10),
        const MutedText('Planned rest days, rescheduled days and planned breaks do not count as missed.', size: 12),
      ]),
      _gap(16),
      _Comparison(summary: summary),
      if (summary.comparison != null) _gap(16),
      _Observations(summary.observations),
    ]);
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = summary.comparison;
    if (c == null) return const SizedBox.shrink();
    final p = context.pal;
    return TitledCard(title: 'Compared with ${c.previousPeriod.label.isEmpty ? 'the previous period' : c.previousPeriod.label}', children: [
      if (c.metrics.isEmpty)
        _empty('The server sent no comparison figures.')
      else
        RowList([
          for (final m in c.metrics)
            RowItem(
              title: comparisonLabel(m.key),
              subtitle: 'Before: ${fmtNum(m.previous, decimals: 1)} · Now: ${fmtNum(m.current, decimals: 1)}',
              trailing: fmtChange(m.changePct),
              trailingColor: m.changePct == null ? p.muted : (m.changePct! > 0 ? p.green : (m.changePct! < 0 ? p.amber : p.muted)),
            ),
        ]),
      const SizedBox(height: 10),
      const MutedText('A change needs context: a short or quiet previous period can make small differences look large. A dash means there was nothing to compare.', size: 12),
    ]);
  }
}

class _Observations extends StatelessWidget {
  const _Observations(this.items);
  final List<Observation> items;

  @override
  Widget build(BuildContext context) {
    return TitledCard(title: 'Observations', children: [
      if (items.isEmpty)
        _empty('Nothing to note for this period yet.')
      else
        for (final o in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(o.text, style: TextStyle(color: context.pal.text, fontSize: 14, height: 1.35))),
      const MutedText('These are statements taken from your records. They are not medical advice or a diagnosis.', size: 12),
    ]);
  }
}

/// Workouts: weekly volume and attendance, with the split, break and deload context.
class WorkoutsSection extends StatelessWidget {
  const WorkoutsSection({super.key, required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = summary.training;
    final a = t.attendance;
    final ctx = summary.context;
    final weekly = t.weekly;
    final maxVolume = weekly.fold<double>(0, (m, w) => (w.volumeKg ?? 0) > m ? (w.volumeKg ?? 0) : m);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TitledCard(title: 'Volume by week', children: [
        if (t.sessions == 0)
          _empty('No finished workouts with logged sets in this period.')
        else if (weekly.isEmpty)
          _empty('No weekly breakdown for this period.')
        else ...[
          BarChartView(values: [for (final w in weekly) w.volumeKg ?? 0], labels: [for (final w in weekly) w.weekStart == null ? '' : '${w.weekStart!.day}/${w.weekStart!.month}'], maxValue: maxVolume <= 0 ? 1 : maxVolume, showValues: weekly.length <= 8),
          const SizedBox(height: 8),
          const MutedText('Total kg lifted per week (weeks start on Monday). The first and last week can include days outside the period.', size: 12),
        ],
      ]),
      _gap(16),
      TitledCard(title: 'Attendance', children: [
        if (a.scheduled == 0 && a.breakDays == 0)
          _empty('No scheduled training days in this period.')
        else
          RowList([
            RowItem(title: 'Scheduled', trailing: '${a.scheduled}'),
            RowItem(title: 'Completed', trailing: '${a.completed}'),
            RowItem(title: 'Missed', trailing: '${a.missed}'),
            RowItem(title: 'Days on planned breaks', trailing: '${a.breakDays}'),
            RowItem(title: 'Consistency', trailing: fmtPct(a.consistencyPct)),
          ]),
        if (a.weekly.isNotEmpty) ...[
          _gap(),
          const GroupLabel('By week'),
          RowList([for (final w in a.weekly) RowItem(title: 'Week of ${fmtDate(w.weekStart)}', subtitle: '${w.completed} of ${w.scheduled} done · ${w.missed} missed', trailing: fmtPct(w.consistencyPct))]),
        ],
      ]),
      _gap(16),
      TitledCard(title: 'Training context', children: [
        if (ctx.splits.isEmpty && ctx.breaks.isEmpty && ctx.deloads.isEmpty)
          _empty('No split changes, planned breaks or deloads in this period.')
        else ...[
          if (ctx.splits.isNotEmpty) ...[
            const GroupLabel('Splits'),
            RowList([for (final s in ctx.splits) RowItem(title: s.name, subtitle: '${fmtDate(s.startDate)} to ${s.endDate == null ? 'now' : fmtDate(s.endDate)}', trailing: s.pattern == null ? null : prettyKey(s.pattern!))]),
          ],
          if (ctx.breaks.isNotEmpty) ...[
            _gap(),
            const GroupLabel('Planned breaks'),
            RowList([for (final b in ctx.breaks) RowItem(title: b.title, subtitle: '${fmtDate(b.startDate)} to ${fmtDate(b.endDate)}', trailing: b.daysInPeriod == null ? null : '${b.daysInPeriod} d')]),
          ],
          if (ctx.deloads.isNotEmpty) ...[
            _gap(),
            const GroupLabel('Deloads'),
            RowList([for (final d in ctx.deloads) RowItem(title: '${fmtDate(d.startDate)} to ${fmtDate(d.endDate)}', subtitle: d.reason, trailing: d.status == null ? null : prettyKey(d.status!))]),
          ],
        ],
      ]),
    ]);
  }
}

/// Strength: per-exercise change, estimated 1RM over time and personal records.
class StrengthSectionView extends StatelessWidget {
  const StrengthSectionView({super.key, required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary.strength;
    final charts = [for (final e in s.e1rmSeries.entries) if (e.value.where((x) => x.e1rmKg != null).length >= 2) e];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TitledCard(title: 'Exercises', children: [
        if (s.exercises.isEmpty)
          _empty('No finished workouts with logged sets in this period.')
        else
          RowList([
            for (final e in s.exercises)
              RowItem(
                title: e.exercise,
                subtitle: '${e.sessions} ${e.sessions == 1 ? 'session' : 'sessions'} · top ${fmtKg(e.topWeightKg)} · volume ${fmtNum(e.volumeKg, decimals: 0)} kg',
                trailing: e.e1rmChangePct == null ? null : fmtChange(e.e1rmChangePct),
              ),
          ]),
        KindNote(s.valueKind),
        if (s.exercises.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: MutedText('The change is the estimated 1RM from the first to the last session. It needs at least two sessions.', size: 12)),
      ]),
      _gap(16),
      TitledCard(title: 'Estimated 1RM over time', children: [
        if (charts.isEmpty)
          _empty('A trend needs at least two sessions of the same exercise in this period.')
        else
          for (final e in charts) _E1rmChart(name: e.key, points: e.value),
      ]),
      _gap(16),
      TitledCard(title: 'Personal records', children: [
        if (s.records.isEmpty)
          _empty('No personal records were set in this period.')
        else
          RowList([
            for (final r in s.records)
              RowItem(
                title: r.exercise,
                subtitle: '${fmtDate(r.achievedOn)} · ${recordKindLabel(r.kind)}${r.weightKg == null ? '' : ' · ${fmtKg(r.weightKg)}${r.reps == null ? '' : ' × ${r.reps}'}'}',
                trailing: r.value == null ? null : fmtNum(r.value, decimals: 1),
              ),
          ]),
      ]),
    ]);
  }
}

class _E1rmChart extends StatelessWidget {
  const _E1rmChart({required this.name, required this.points});
  final String name;
  final List<E1rmPoint> points;

  @override
  Widget build(BuildContext context) {
    final pts = [for (final p in points) if (p.e1rmKg != null) p];
    final values = [for (final p in pts) p.e1rmKg!];
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo) < 1 ? 1.0 : (hi - lo) * 0.15;
    final yMin = (lo - pad).floorToDouble();
    final yMax = (hi + pad).ceilToDouble();
    final labels = [for (final p in pts) p.date == null ? '' : '${p.date!.day}/${p.date!.month}'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GroupLabel(name),
        const SizedBox(height: 6),
        LineChartView(values: values, xLabels: labels, yMin: yMin, yMax: yMax, yTicks: [yMin, (yMin + yMax) / 2, yMax], height: 140),
      ]),
    );
  }
}

/// Body: measurements, weight trend, composition, muscle ratings and injuries.
class BodySectionView extends StatelessWidget {
  const BodySectionView({super.key, required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final b = summary.body;
    final m = summary.muscles;
    final inj = summary.injuries;
    final weights = [for (final w in b.weightSeries) if (w.value != null) w];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TitledCard(title: 'Measurements', children: [
        if (b.measurements.isEmpty)
          _empty('No body measurements were logged in this period.')
        else
          RowList([
            for (final x in b.measurements)
              RowItem(
                title: x.label.isNotEmpty ? x.label : prettyKey(x.type),
                subtitle: '${x.count} ${x.count == 1 ? 'reading' : 'readings'}${x.method == null ? '' : ' · ${prettyKey(x.method!)}'} · ${fmtNum(x.firstValue, decimals: 1)} → ${fmtNum(x.lastValue, decimals: 1)} ${x.unit}',
                trailing: x.change == null ? null : '${x.change! > 0 ? '+' : ''}${fmtNum(x.change, decimals: 1)} ${x.unit}',
              ),
          ]),
        KindNote(b.valueKind),
      ]),
      _gap(16),
      TitledCard(title: 'Body weight', children: [
        if (weights.length < 2)
          _empty(weights.isEmpty ? 'No weight readings in this period.' : 'One reading is not a trend. A line needs at least two.')
        else
          _WeightChart(weights),
      ]),
      _gap(16),
      TitledCard(title: 'Body composition', children: [
        if (b.composition.isEmpty)
          _empty('No body composition estimates in this period.')
        else
          RowList([
            for (final c in b.composition)
              RowItem(
                title: fmtDate(c.date),
                subtitle: '${c.method == null ? '' : '${prettyKey(c.method!)} · '}weight ${fmtKg(c.weightKg)} · fat ${fmtKg(c.fatMassKg)} · lean ${fmtKg(c.leanMassKg)}',
                trailing: c.bodyFatPct == null ? null : '${fmtNum(c.bodyFatPct)}%',
              ),
          ]),
        const KindNote('estimated'),
      ]),
      _gap(16),
      TitledCard(title: 'Muscle ratings and exposure', children: [
        if (m.ratings.isEmpty && m.exposure.isEmpty && m.priorityChanges.isEmpty)
          _empty('No muscle ratings or training exposure in this period.')
        else ...[
          if (m.ratings.isNotEmpty) ...[
            const GroupLabel('Your ratings'),
            RowList([
              for (final r in m.ratings)
                RowItem(title: prettyKey(r.muscleKey), subtitle: '${ratingChangeLabel(r.change)} · ${r.assessments} ${r.assessments == 1 ? 'assessment' : 'assessments'}', trailing: r.firstLevel == r.lastLevel ? '${r.lastLevel ?? '—'}/5' : '${r.firstLevel ?? '—'} → ${r.lastLevel ?? '—'}'),
            ]),
            KindNote(m.valueKind),
          ],
          if (m.exposure.isNotEmpty) ...[
            _gap(),
            const GroupLabel('Sets that trained each muscle'),
            RowList([for (final e in m.exposure) RowItem(title: prettyKey(e.muscleKey), subtitle: '${e.indirectSets} supporting', trailing: '${e.directSets} direct')]),
            const Padding(padding: EdgeInsets.only(top: 6), child: MutedText('Only finished workouts with logged sets count towards exposure.', size: 12)),
          ],
          if (m.priorityChanges.isNotEmpty) ...[
            _gap(),
            const GroupLabel('Priority changes'),
            RowList([for (final c in m.priorityChanges) RowItem(title: prettyKey(c.muscleKey), subtitle: fmtDate(c.fromDate), trailing: c.priority == null ? null : prettyKey(c.priority!))]),
          ],
        ],
      ]),
      _gap(16),
      TitledCard(title: 'Injuries and pain', children: [
        if (inj.injuries.isEmpty && inj.painEntries == 0)
          _empty('No injuries or pain entries in this period.')
        else ...[
          if (inj.injuries.isNotEmpty)
            RowList([
              for (final i in inj.injuries)
                RowItem(
                  title: i.name,
                  subtitle: '${[if (i.bodyRegion != null) prettyKey(i.bodyRegion!), if (i.side != null) prettyKey(i.side!), if (i.status != null) prettyKey(i.status!)].join(' · ')}${i.suggestProfessionalReview ? '\nFlagged: consider having it assessed by a professional.' : ''}',
                  trailing: i.latestPainLevel == null ? null : 'Pain ${i.latestPainLevel}/10',
                ),
            ]),
          if (inj.painEntries > 0) ...[
            _gap(),
            MutedText('${inj.painEntries} pain ${inj.painEntries == 1 ? 'entry' : 'entries'} · highest ${fmtNum(inj.painMax, decimals: 0)}/10 · average ${fmtNum(inj.painAverage)}/10'),
          ],
        ],
      ]),
    ]);
  }
}

class _WeightChart extends StatelessWidget {
  const _WeightChart(this.points);
  final List<DatedValue> points;

  @override
  Widget build(BuildContext context) {
    final values = [for (final p in points) p.value!];
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final pad = (hi - lo) < 1 ? 1.0 : (hi - lo) * 0.2;
    final yMin = (lo - pad).floorToDouble();
    final yMax = (hi + pad).ceilToDouble();
    return LineChartView(values: values, xLabels: [for (final p in points) p.date == null ? '' : '${p.date!.day}/${p.date!.month}'], yMin: yMin, yMax: yMax, yTicks: [yMin, (yMin + yMax) / 2, yMax]);
  }
}

/// Lifestyle: recovery, steps, cardio, hydration, nutrition and supplements.
class LifestyleSectionView extends StatelessWidget {
  const LifestyleSectionView({super.key, required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = summary.lifestyle;
    final r = summary.recovery;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TitledCard(title: 'Recovery', children: [
        if (r.checkinDays == 0 && r.sleepNights == 0)
          _empty('No daily check-ins or sleep logs in this period.')
        else
          RowList([
            if (r.sleepNights > 0) RowItem(title: 'Sleep', subtitle: '${r.sleepNights} ${r.sleepNights == 1 ? 'night' : 'nights'}${r.sleepAvgQuality == null ? '' : ' · quality ${fmtNum(r.sleepAvgQuality)}'}', trailing: r.sleepAvgHours == null ? null : '${fmtNum(r.sleepAvgHours)} h'),
            if (r.checkinDays > 0) ...[
              RowItem(title: 'Check-in days', trailing: '${r.checkinDays}'),
              RowItem(title: 'Energy', trailing: fmtNum(r.energy)),
              RowItem(title: 'Soreness', trailing: fmtNum(r.soreness)),
              RowItem(title: 'Fatigue', trailing: fmtNum(r.fatigue)),
              RowItem(title: 'Stress', trailing: fmtNum(r.stress)),
              RowItem(title: 'Motivation', trailing: fmtNum(r.motivation)),
            ],
          ]),
        if (r.checkinDays > 0) const Padding(padding: EdgeInsets.only(top: 6), child: MutedText('Daily check-in figures are averages of your own ratings.', size: 12)),
      ]),
      _gap(16),
      TitledCard(title: 'Activity', children: [
        if (l.stepDaysLogged == 0 && l.cardioSessions == 0)
          _empty('No steps or cardio logged in this period.')
        else
          RowList([
            if (l.stepDaysLogged > 0) RowItem(title: 'Steps', subtitle: '${l.stepDaysLogged} days logged · target reached on ${l.stepDaysOnTarget}', trailing: l.avgSteps == null ? null : '${fmtNum(l.avgSteps, decimals: 0)} avg'),
            if (l.cardioSessions > 0) RowItem(title: 'Cardio', subtitle: '${fmtNum(l.cardioMinutes, decimals: 0)} min${l.cardioKm == null || l.cardioKm == 0 ? '' : ' · ${fmtNum(l.cardioKm)} km'}', trailing: '${l.cardioSessions} sessions'),
          ]),
      ]),
      _gap(16),
      TitledCard(title: 'Hydration and nutrition', children: [
        if (l.hydrationDays == 0 && l.nutritionDays == 0)
          _empty('No hydration or meal plan entries in this period.')
        else
          RowList([
            if (l.hydrationDays > 0) RowItem(title: 'Hydration', subtitle: '${l.hydrationDays} days logged${l.avgHydrationPctOfTarget == null ? '' : ' · ${fmtNum(l.avgHydrationPctOfTarget, decimals: 0)}% of target'}', trailing: l.avgHydrationMl == null ? null : '${fmtNum(l.avgHydrationMl, decimals: 0)} ml'),
            if (l.nutritionDays > 0)
              RowItem(
                title: 'Protein',
                subtitle: '${l.nutritionDays} days with a meal plan · planned ${fmtNum(l.avgPlannedProteinG)} g · eaten ${fmtNum(l.avgEatenProteinG)} g',
                trailing: l.avgProteinTargetG == null ? null : 'target ${fmtNum(l.avgProteinTargetG, decimals: 0)} g',
              ),
          ]),
        KindNote(l.valueKind),
      ]),
      _gap(16),
      TitledCard(title: 'Supplements', children: [
        if (l.supplements.isEmpty)
          _empty('No supplement doses were logged in this period.')
        else
          RowList([for (final s in l.supplements) RowItem(title: s.name, subtitle: '${s.taken} taken · ${s.missed} missed · ${s.skipped} skipped on purpose', trailing: s.adherencePct == null ? null : fmtPct(s.adherencePct))]),
        if (l.supplements.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: MutedText('Percentages are shares of the doses you logged, not of every day.', size: 12)),
      ]),
    ]);
  }
}

/// Goals as they stand at the time of the report (goals are not limited to the period).
class GoalsSectionView extends StatelessWidget {
  const GoalsSectionView({super.key, required this.summary});
  final ReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final g = summary.goals;
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TitledCard(title: 'Goals', children: [
        if (g.goals.isEmpty)
          _empty('No goals yet. Add one on the Progress tab.')
        else
          for (final goal in g.goals)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(goal.title, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600))),
                  Text(goal.status == null ? '' : prettyKey(goal.status!), style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
                const SizedBox(height: 6),
                if (goal.status == 'active' && goal.progressPct != null) ...[
                  MeterBar(value: (goal.progressPct ?? 0) / 100),
                  const SizedBox(height: 6),
                ],
                MutedText(_goalLine(goal)),
              ]),
            ),
        const MutedText('Goals show where they stand when the report is made, not only inside the period.', size: 12),
      ]),
      _gap(16),
      TitledCard(title: 'Milestones', children: [
        if (g.milestones.isEmpty)
          _empty('No milestones.')
        else
          RowList([for (final m in g.milestones) RowItem(title: m.title, subtitle: m.goal, trailing: m.isReached ? 'Reached' : (m.targetValue == null ? null : fmtNum(m.targetValue)), trailingColor: m.isReached ? p.green : null)]),
      ]),
    ]);
  }

  String _goalLine(GoalRow g) {
    final parts = <String>[];
    if (g.currentValue != null || g.targetValue != null) parts.add('${fmtNum(g.currentValue)} of ${fmtNum(g.targetValue)}');
    if (g.status == 'active' && g.progressPct != null) parts.add(fmtPct(g.progressPct));
    final label = g.status == 'active' ? progressStatusLabel(g.progressStatus) : '';
    if (label.isNotEmpty) parts.add(label);
    return parts.isEmpty ? 'No progress figure yet.' : parts.join(' · ');
  }
}
