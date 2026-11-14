/// Typed view of the reporting service's `GET /api/v1/reports/summary` answer (backend: `app/reports/summary.py`).
/// Every number here was calculated by the server; the app only reads and shows it. Values may be missing or null
/// (for example an average over no days), so every field is read defensively.
library;

double? _num(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
String? _str(Object? v) => v is String ? v : null;
bool _bool(Object? v) => v == true;
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) parse) => v is List ? [for (final e in v) if (e is Map) parse(Map<String, dynamic>.from(e))] : <T>[];

class ReportPeriodInfo {
  const ReportPeriodInfo({required this.kind, required this.label, this.start, this.end, this.days = 0});

  final String kind;
  final String label;
  final DateTime? start;
  final DateTime? end;
  final int days;

  factory ReportPeriodInfo.fromJson(Map<String, dynamic> j) =>
      ReportPeriodInfo(kind: _str(j['kind']) ?? '', label: _str(j['label']) ?? '', start: _date(j['start']), end: _date(j['end']), days: _int(j['days']) ?? 0);
}

class WeekVolume {
  const WeekVolume({this.weekStart, this.sessions = 0, this.volumeKg});

  final DateTime? weekStart;
  final int sessions;
  final double? volumeKg;

  factory WeekVolume.fromJson(Map<String, dynamic> j) => WeekVolume(weekStart: _date(j['week_start']), sessions: _int(j['sessions']) ?? 0, volumeKg: _num(j['volume_kg']));
}

class AttendanceWeek {
  const AttendanceWeek({this.weekStart, this.scheduled = 0, this.completed = 0, this.missed = 0, this.breakDays = 0, this.consistencyPct});

  final DateTime? weekStart;
  final int scheduled;
  final int completed;
  final int missed;
  final int breakDays;
  final double? consistencyPct;

  factory AttendanceWeek.fromJson(Map<String, dynamic> j) => AttendanceWeek(
      weekStart: _date(j['week_start']),
      scheduled: _int(j['scheduled']) ?? 0,
      completed: _int(j['completed']) ?? 0,
      missed: _int(j['missed']) ?? 0,
      breakDays: _int(j['break_days']) ?? 0,
      consistencyPct: _num(j['consistency_pct']));
}

class Attendance {
  const Attendance({this.scheduled = 0, this.completed = 0, this.missed = 0, this.breakDays = 0, this.consistencyPct, this.weekly = const []});

  final int scheduled;
  final int completed;
  final int missed;
  final int breakDays;

  /// Null when nothing was scheduled.
  final double? consistencyPct;
  final List<AttendanceWeek> weekly;

  factory Attendance.fromJson(Map<String, dynamic> j) => Attendance(
      scheduled: _int(j['scheduled']) ?? 0,
      completed: _int(j['completed']) ?? 0,
      missed: _int(j['missed']) ?? 0,
      breakDays: _int(j['break_days']) ?? 0,
      consistencyPct: _num(j['consistency_pct']),
      weekly: _list(j['weekly'], AttendanceWeek.fromJson));
}

class TrainingSection {
  const TrainingSection({this.sessions = 0, this.volumeKg = 0, this.workingSets = 0, this.totalReps = 0, this.avgDurationMin, this.weekly = const [], this.attendance = const Attendance()});

  final int sessions;
  final double volumeKg;
  final int workingSets;
  final int totalReps;
  final double? avgDurationMin;
  final List<WeekVolume> weekly;
  final Attendance attendance;

  factory TrainingSection.fromJson(Map<String, dynamic> j) => TrainingSection(
      sessions: _int(j['sessions']) ?? 0,
      volumeKg: _num(j['volume_kg']) ?? 0,
      workingSets: _int(j['working_sets']) ?? 0,
      totalReps: _int(j['total_reps']) ?? 0,
      avgDurationMin: _num(j['avg_duration_min']),
      weekly: _list(j['weekly'], WeekVolume.fromJson),
      attendance: Attendance.fromJson(_map(j['attendance'])));
}

class ExerciseStrength {
  const ExerciseStrength({required this.exercise, this.sessions = 0, this.firstE1rmKg, this.lastE1rmKg, this.topWeightKg, this.volumeKg, this.e1rmChangePct});

  final String exercise;
  final int sessions;
  final double? firstE1rmKg;
  final double? lastE1rmKg;
  final double? topWeightKg;
  final double? volumeKg;

  /// Estimated 1RM change between the first and last session; null with fewer than two sessions.
  final double? e1rmChangePct;

  factory ExerciseStrength.fromJson(Map<String, dynamic> j) => ExerciseStrength(
      exercise: _str(j['exercise']) ?? '',
      sessions: _int(j['sessions']) ?? 0,
      firstE1rmKg: _num(j['first_e1rm_kg']),
      lastE1rmKg: _num(j['last_e1rm_kg']),
      topWeightKg: _num(j['top_weight_kg']),
      volumeKg: _num(j['volume_kg']),
      e1rmChangePct: _num(j['e1rm_change_pct']));
}

class E1rmPoint {
  const E1rmPoint({this.date, this.e1rmKg});

  final DateTime? date;
  final double? e1rmKg;

  factory E1rmPoint.fromJson(Map<String, dynamic> j) => E1rmPoint(date: _date(j['date']), e1rmKg: _num(j['e1rm_kg']));
}

class RecordRow {
  const RecordRow({this.achievedOn, required this.exercise, required this.kind, this.value, this.previousValue, this.weightKg, this.reps});

  final DateTime? achievedOn;
  final String exercise;
  final String kind;
  final double? value;
  final double? previousValue;
  final double? weightKg;
  final int? reps;

  factory RecordRow.fromJson(Map<String, dynamic> j) => RecordRow(
      achievedOn: _date(j['achieved_on']),
      exercise: _str(j['exercise']) ?? '',
      kind: _str(j['kind']) ?? '',
      value: _num(j['value']),
      previousValue: _num(j['previous_value']),
      weightKg: _num(j['weight_kg']),
      reps: _int(j['reps']));
}

class StrengthSection {
  const StrengthSection({this.exercises = const [], this.e1rmSeries = const {}, this.records = const [], this.valueKind = 'estimated'});

  final List<ExerciseStrength> exercises;

  /// Estimated 1RM over time for the most-trained exercises, by exercise name.
  final Map<String, List<E1rmPoint>> e1rmSeries;
  final List<RecordRow> records;

  /// `estimated`: 1RM values are estimates, not measurements.
  final String valueKind;

  factory StrengthSection.fromJson(Map<String, dynamic> j) {
    final series = <String, List<E1rmPoint>>{};
    for (final e in _map(j['e1rm_series']).entries) {
      series[e.key] = _list(e.value, E1rmPoint.fromJson);
    }
    return StrengthSection(
        exercises: _list(j['exercises'], ExerciseStrength.fromJson), e1rmSeries: series, records: _list(j['records'], RecordRow.fromJson), valueKind: _str(j['value_kind']) ?? 'estimated');
  }
}

class BodyMeasurement {
  const BodyMeasurement({required this.type, this.label = '', this.unit = '', this.method, this.count = 0, this.firstValue, this.lastValue, this.change});

  final String type;
  final String label;
  final String unit;
  final String? method;
  final int count;
  final double? firstValue;
  final double? lastValue;

  /// Last minus first; null with fewer than two readings.
  final double? change;

  factory BodyMeasurement.fromJson(Map<String, dynamic> j) => BodyMeasurement(
      type: _str(j['measurement_type']) ?? '',
      label: _str(j['label']) ?? '',
      unit: _str(j['unit']) ?? '',
      method: _str(j['method']),
      count: _int(j['n']) ?? 0,
      firstValue: _num(j['first_value']),
      lastValue: _num(j['last_value']),
      change: _num(j['change']));
}

class DatedValue {
  const DatedValue({this.date, this.value});

  final DateTime? date;
  final double? value;

  factory DatedValue.fromJson(Map<String, dynamic> j) => DatedValue(date: _date(j['date']), value: _num(j['value']));
}

class CompositionRow {
  const CompositionRow({this.date, this.method, this.bodyFatPct, this.weightKg, this.fatMassKg, this.leanMassKg});

  final DateTime? date;
  final String? method;
  final double? bodyFatPct;
  final double? weightKg;
  final double? fatMassKg;
  final double? leanMassKg;

  factory CompositionRow.fromJson(Map<String, dynamic> j) => CompositionRow(
      date: _date(j['date']),
      method: _str(j['method']),
      bodyFatPct: _num(j['body_fat_pct']),
      weightKg: _num(j['weight_kg']),
      fatMassKg: _num(j['fat_mass_kg']),
      leanMassKg: _num(j['lean_mass_kg']));
}

class BodySection {
  const BodySection({this.measurements = const [], this.weightSeries = const [], this.composition = const [], this.valueKind = 'estimated'});

  final List<BodyMeasurement> measurements;
  final List<DatedValue> weightSeries;
  final List<CompositionRow> composition;
  final String valueKind;

  factory BodySection.fromJson(Map<String, dynamic> j) => BodySection(
      measurements: _list(j['measurements'], BodyMeasurement.fromJson),
      weightSeries: _list(j['weight_series'], DatedValue.fromJson),
      composition: _list(j['composition'], CompositionRow.fromJson),
      valueKind: _str(j['value_kind']) ?? 'estimated');
}

class MuscleRating {
  const MuscleRating({required this.muscleKey, this.assessments = 0, this.firstLevel, this.lastLevel, this.change = 'same_rating'});

  final String muscleKey;
  final int assessments;
  final int? firstLevel;
  final int? lastLevel;

  /// `higher_rating`, `lower_rating` or `same_rating`: a change in the person's own rating, not measured growth.
  final String change;

  factory MuscleRating.fromJson(Map<String, dynamic> j) => MuscleRating(
      muscleKey: _str(j['muscle_key']) ?? '',
      assessments: _int(j['assessments']) ?? 0,
      firstLevel: _int(j['first_level']),
      lastLevel: _int(j['last_level']),
      change: _str(j['assessment_change']) ?? 'same_rating');
}

class PriorityChange {
  const PriorityChange({required this.muscleKey, this.priority, this.fromDate});

  final String muscleKey;
  final String? priority;
  final DateTime? fromDate;

  factory PriorityChange.fromJson(Map<String, dynamic> j) => PriorityChange(muscleKey: _str(j['muscle_key']) ?? '', priority: _str(j['priority']), fromDate: _date(j['from_date']));
}

class MuscleExposure {
  const MuscleExposure({required this.muscleKey, this.directSets = 0, this.indirectSets = 0});

  final String muscleKey;
  final int directSets;
  final int indirectSets;

  factory MuscleExposure.fromJson(Map<String, dynamic> j) => MuscleExposure(muscleKey: _str(j['muscle_key']) ?? '', directSets: _int(j['direct_sets']) ?? 0, indirectSets: _int(j['indirect_sets']) ?? 0);
}

class MusclesSection {
  const MusclesSection({this.ratings = const [], this.priorityChanges = const [], this.exposure = const [], this.valueKind = 'user_assessment'});

  final List<MuscleRating> ratings;
  final List<PriorityChange> priorityChanges;
  final List<MuscleExposure> exposure;

  /// `user_assessment`: ratings are the person's own, not measurements.
  final String valueKind;

  factory MusclesSection.fromJson(Map<String, dynamic> j) => MusclesSection(
      ratings: _list(j['ratings'], MuscleRating.fromJson),
      priorityChanges: _list(j['priority_changes'], PriorityChange.fromJson),
      exposure: _list(j['training_exposure'], MuscleExposure.fromJson),
      valueKind: _str(j['value_kind']) ?? 'user_assessment');
}

class InjuryRow {
  const InjuryRow({required this.name, this.bodyRegion, this.side, this.status, this.severity, this.startDate, this.resolvedOn, this.latestPainLevel, this.suggestProfessionalReview = false});

  final String name;
  final String? bodyRegion;
  final String? side;
  final String? status;
  final String? severity;
  final DateTime? startDate;
  final DateTime? resolvedOn;
  final int? latestPainLevel;
  final bool suggestProfessionalReview;

  factory InjuryRow.fromJson(Map<String, dynamic> j) => InjuryRow(
      name: _str(j['name']) ?? '',
      bodyRegion: _str(j['body_region_key']),
      side: _str(j['side']),
      status: _str(j['status']),
      severity: _str(j['severity']),
      startDate: _date(j['start_date']),
      resolvedOn: _date(j['resolved_on']),
      latestPainLevel: _int(j['latest_pain_level']),
      suggestProfessionalReview: _bool(j['suggest_professional_review']));
}

class InjuriesSection {
  const InjuriesSection({this.injuries = const [], this.painEntries = 0, this.painMax, this.painAverage});

  final List<InjuryRow> injuries;
  final int painEntries;
  final double? painMax;
  final double? painAverage;

  factory InjuriesSection.fromJson(Map<String, dynamic> j) {
    final pain = _map(j['pain']);
    return InjuriesSection(injuries: _list(j['injuries'], InjuryRow.fromJson), painEntries: _int(pain['entries']) ?? 0, painMax: _num(pain['max_level']), painAverage: _num(pain['avg_level']));
  }
}

class RecoverySection {
  const RecoverySection({this.checkinDays = 0, this.energy, this.sleepQuality, this.soreness, this.fatigue, this.motivation, this.stress, this.sleepNights = 0, this.sleepAvgHours, this.sleepAvgQuality});

  final int checkinDays;
  final double? energy;
  final double? sleepQuality;
  final double? soreness;
  final double? fatigue;
  final double? motivation;
  final double? stress;
  final int sleepNights;
  final double? sleepAvgHours;
  final double? sleepAvgQuality;

  factory RecoverySection.fromJson(Map<String, dynamic> j) {
    final c = _map(j['checkin_averages']);
    final s = _map(j['sleep']);
    return RecoverySection(
        checkinDays: _int(c['days']) ?? 0,
        energy: _num(c['energy']),
        sleepQuality: _num(c['sleep_quality']),
        soreness: _num(c['soreness']),
        fatigue: _num(c['fatigue']),
        motivation: _num(c['motivation']),
        stress: _num(c['stress']),
        sleepNights: _int(s['nights']) ?? 0,
        sleepAvgHours: _num(s['avg_hours']),
        sleepAvgQuality: _num(s['avg_quality']));
  }
}

class SupplementRow {
  const SupplementRow({required this.name, this.taken = 0, this.missed = 0, this.skipped = 0, this.adherencePct});

  final String name;
  final int taken;
  final int missed;
  final int skipped;

  /// Share of logged doses that were taken (skipped on purpose is not counted); null when none were logged.
  final double? adherencePct;

  factory SupplementRow.fromJson(Map<String, dynamic> j) => SupplementRow(
      name: _str(j['name']) ?? '', taken: _int(j['taken']) ?? 0, missed: _int(j['missed']) ?? 0, skipped: _int(j['skipped']) ?? 0, adherencePct: _num(j['logged_adherence_pct']));
}

class LifestyleSection {
  const LifestyleSection({
    this.stepDaysLogged = 0,
    this.avgSteps,
    this.maxSteps,
    this.stepDaysOnTarget = 0,
    this.cardioSessions = 0,
    this.cardioMinutes,
    this.cardioKm,
    this.hydrationDays = 0,
    this.avgHydrationMl,
    this.avgHydrationPctOfTarget,
    this.nutritionDays = 0,
    this.avgPlannedProteinG,
    this.avgEatenProteinG,
    this.avgProteinTargetG,
    this.supplements = const [],
    this.valueKind = 'estimated',
  });

  final int stepDaysLogged;
  final double? avgSteps;
  final double? maxSteps;
  final int stepDaysOnTarget;
  final int cardioSessions;
  final double? cardioMinutes;
  final double? cardioKm;
  final int hydrationDays;
  final double? avgHydrationMl;
  final double? avgHydrationPctOfTarget;
  final int nutritionDays;
  final double? avgPlannedProteinG;
  final double? avgEatenProteinG;
  final double? avgProteinTargetG;
  final List<SupplementRow> supplements;
  final String valueKind;

  factory LifestyleSection.fromJson(Map<String, dynamic> j) {
    final steps = _map(j['steps']);
    final cardio = _map(j['cardio']);
    final hyd = _map(j['hydration']);
    final nut = _map(j['nutrition']);
    return LifestyleSection(
      stepDaysLogged: _int(steps['days_logged']) ?? 0,
      avgSteps: _num(steps['avg_steps']),
      maxSteps: _num(steps['max_steps']),
      stepDaysOnTarget: _int(steps['days_on_target']) ?? 0,
      cardioSessions: _int(cardio['sessions']) ?? 0,
      cardioMinutes: _num(cardio['total_minutes']),
      cardioKm: _num(cardio['total_km']),
      hydrationDays: _int(hyd['days_logged']) ?? 0,
      avgHydrationMl: _num(hyd['avg_ml']),
      avgHydrationPctOfTarget: _num(hyd['avg_pct_of_target']),
      nutritionDays: _int(nut['days_planned']) ?? 0,
      avgPlannedProteinG: _num(nut['avg_planned_protein_g']),
      avgEatenProteinG: _num(nut['avg_eaten_protein_g']),
      avgProteinTargetG: _num(nut['avg_protein_target_g']),
      supplements: _list(j['supplements'], SupplementRow.fromJson),
      valueKind: _str(j['value_kind']) ?? 'estimated',
    );
  }
}

class GoalRow {
  const GoalRow({required this.title, this.type, this.status, this.targetMetric, this.targetValue, this.startValue, this.currentValue, this.progressPct, this.progressStatus});

  final String title;
  final String? type;
  final String? status;
  final String? targetMetric;
  final double? targetValue;
  final double? startValue;
  final double? currentValue;
  final double? progressPct;
  final String? progressStatus;

  factory GoalRow.fromJson(Map<String, dynamic> j) => GoalRow(
      title: _str(j['title']) ?? '',
      type: _str(j['type']),
      status: _str(j['goal_status']),
      targetMetric: _str(j['target_metric']),
      targetValue: _num(j['target_value']),
      startValue: _num(j['start_value']),
      currentValue: _num(j['current_value']),
      progressPct: _num(j['progress_pct']),
      progressStatus: _str(j['progress_status']));
}

class MilestoneRow {
  const MilestoneRow({required this.goal, required this.title, this.targetValue, this.isReached = false});

  final String goal;
  final String title;
  final double? targetValue;
  final bool isReached;

  factory MilestoneRow.fromJson(Map<String, dynamic> j) =>
      MilestoneRow(goal: _str(j['goal']) ?? '', title: _str(j['title']) ?? '', targetValue: _num(j['target_value']), isReached: _bool(j['is_reached']));
}

class GoalsSection {
  const GoalsSection({this.goals = const [], this.milestones = const []});

  final List<GoalRow> goals;
  final List<MilestoneRow> milestones;

  factory GoalsSection.fromJson(Map<String, dynamic> j) => GoalsSection(goals: _list(j['goals'], GoalRow.fromJson), milestones: _list(j['milestones'], MilestoneRow.fromJson));
}

class SplitPeriod {
  const SplitPeriod({required this.name, this.pattern, this.startDate, this.endDate, this.durationDays});

  final String name;
  final String? pattern;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? durationDays;

  factory SplitPeriod.fromJson(Map<String, dynamic> j) =>
      SplitPeriod(name: _str(j['name']) ?? '', pattern: _str(j['pattern']), startDate: _date(j['start_date']), endDate: _date(j['end_date']), durationDays: _int(j['duration_days']));
}

class BreakRow {
  const BreakRow({required this.title, this.reason, this.mode, this.status, this.startDate, this.endDate, this.daysInPeriod});

  final String title;
  final String? reason;
  final String? mode;
  final String? status;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? daysInPeriod;

  factory BreakRow.fromJson(Map<String, dynamic> j) => BreakRow(
      title: _str(j['title']) ?? '',
      reason: _str(j['reason']),
      mode: _str(j['mode']),
      status: _str(j['status']),
      startDate: _date(j['start_date']),
      endDate: _date(j['end_date']),
      daysInPeriod: _int(j['days_in_period']));
}

class DeloadRow {
  const DeloadRow({this.startDate, this.endDate, this.status, this.reason});

  final DateTime? startDate;
  final DateTime? endDate;
  final String? status;
  final String? reason;

  factory DeloadRow.fromJson(Map<String, dynamic> j) => DeloadRow(startDate: _date(j['start_date']), endDate: _date(j['end_date']), status: _str(j['status']), reason: _str(j['reason']));
}

class ContextSection {
  const ContextSection({this.splits = const [], this.breaks = const [], this.deloads = const []});

  final List<SplitPeriod> splits;
  final List<BreakRow> breaks;
  final List<DeloadRow> deloads;

  factory ContextSection.fromJson(Map<String, dynamic> j) =>
      ContextSection(splits: _list(j['splits'], SplitPeriod.fromJson), breaks: _list(j['breaks'], BreakRow.fromJson), deloads: _list(j['deloads'], DeloadRow.fromJson));
}

/// A cautious statement taken from the figures (never advice or a diagnosis).
class Observation {
  const Observation({required this.code, required this.text});

  final String code;
  final String text;

  factory Observation.fromJson(Map<String, dynamic> j) => Observation(code: _str(j['code']) ?? '', text: _str(j['text']) ?? '');
}

class ComparisonMetric {
  const ComparisonMetric({required this.key, this.current, this.previous, this.changePct});

  final String key;
  final double? current;
  final double? previous;

  /// Null when the previous value is missing or zero.
  final double? changePct;

  factory ComparisonMetric.fromJson(Map<String, dynamic> j) => ComparisonMetric(key: _str(j['key']) ?? '', current: _num(j['current']), previous: _num(j['previous']), changePct: _num(j['change_pct']));
}

class Comparison {
  const Comparison({required this.previousPeriod, this.metrics = const []});

  final ReportPeriodInfo previousPeriod;
  final List<ComparisonMetric> metrics;

  factory Comparison.fromJson(Map<String, dynamic> j) => Comparison(previousPeriod: ReportPeriodInfo.fromJson(_map(j['previous_period'])), metrics: _list(j['metrics'], ComparisonMetric.fromJson));
}

class ReportSummary {
  const ReportSummary({
    required this.period,
    required this.training,
    required this.strength,
    required this.body,
    required this.muscles,
    required this.injuries,
    required this.recovery,
    required this.lifestyle,
    required this.goals,
    required this.context,
    required this.observations,
    this.comparison,
  });

  final ReportPeriodInfo period;
  final TrainingSection training;
  final StrengthSection strength;
  final BodySection body;
  final MusclesSection muscles;
  final InjuriesSection injuries;
  final RecoverySection recovery;
  final LifestyleSection lifestyle;
  final GoalsSection goals;
  final ContextSection context;
  final List<Observation> observations;

  /// Present only when the previous period was asked for.
  final Comparison? comparison;

  /// Throws [FormatException] when [json] is not a summary (no `period` and no `training`).
  factory ReportSummary.fromJson(Map<String, dynamic> j) {
    if (j['period'] is! Map || j['training'] is! Map) throw const FormatException('not a report summary');
    return ReportSummary(
      period: ReportPeriodInfo.fromJson(_map(j['period'])),
      training: TrainingSection.fromJson(_map(j['training'])),
      strength: StrengthSection.fromJson(_map(j['strength'])),
      body: BodySection.fromJson(_map(j['body'])),
      muscles: MusclesSection.fromJson(_map(j['muscles'])),
      injuries: InjuriesSection.fromJson(_map(j['injuries'])),
      recovery: RecoverySection.fromJson(_map(j['recovery'])),
      lifestyle: LifestyleSection.fromJson(_map(j['lifestyle'])),
      goals: GoalsSection.fromJson(_map(j['goals'])),
      context: ContextSection.fromJson(_map(j['context'])),
      observations: _list(j['observations'], Observation.fromJson),
      comparison: j['comparison'] is Map ? Comparison.fromJson(_map(j['comparison'])) : null,
    );
  }
}
