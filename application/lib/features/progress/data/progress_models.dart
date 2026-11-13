/// Typed views over what Progress and Home show. Two sources:
///  - records that arrive by sync and live in SQLite (personal records, achievements, goals, milestones), and
///  - answers the server calculates (daily briefing, trends, goal progress, ...) that the phone caches.
/// Server answers are read defensively: a missing field is null or empty, never a crash, and nothing is recalculated here.
library;

double? _double(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
String? _string(Object? v) => v is String ? v : null;
bool _bool(Object? v) => v == true;
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];
List<String> _strings(Object? v) => v is List ? [for (final e in v) if (e is String) e] : const [];

// ---- Synced records (SQLite) ----

class PersonalRecord {
  const PersonalRecord({required this.id, required this.kind, required this.value, required this.achievedOn, required this.sessionId, this.exerciseId, this.weightKg, this.reps, this.previousValue});

  final String id;

  /// `max_weight`, `best_reps_at_weight`, `est_1rm`, `session_volume` or `workout_volume`.
  final String kind;
  final double value;
  final String achievedOn;
  final String sessionId;
  final String? exerciseId;
  final double? weightKg;
  final int? reps;
  final double? previousValue;

  factory PersonalRecord.fromRecord(Map<String, dynamic> r) => PersonalRecord(
        id: r['id'] as String,
        kind: (r['kind'] as String?) ?? '',
        value: _double(r['value']) ?? 0,
        achievedOn: (r['achieved_on'] as String?) ?? '',
        sessionId: (r['session_id'] as String?) ?? '',
        exerciseId: r['exercise_id'] as String?,
        weightKg: _double(r['weight_kg']),
        reps: _int(r['reps']),
        previousValue: _double(r['previous_value']),
      );
}

class Achievement {
  const Achievement({required this.id, required this.kind, required this.threshold, required this.title, required this.achievedOn, this.supportingTable, this.supportingRecordId});

  final String id;

  /// `workouts_completed` or `streak`.
  final String kind;
  final int threshold;
  final String title;
  final String achievedOn;

  /// The record the server found this achievement from (for a workout count, the workout session).
  final String? supportingTable;
  final String? supportingRecordId;

  factory Achievement.fromRecord(Map<String, dynamic> r) => Achievement(
        id: r['id'] as String,
        kind: (r['kind'] as String?) ?? '',
        threshold: _int(r['threshold']) ?? 0,
        title: (r['title'] as String?) ?? '',
        achievedOn: (r['achieved_on'] as String?) ?? '',
        supportingTable: r['supporting_table'] as String?,
        supportingRecordId: r['supporting_record_id'] as String?,
      );
}

class Goal {
  const Goal({required this.id, required this.type, required this.title, required this.status, required this.startDate, this.description, this.targetMetric, this.targetValue, this.targetUnit, this.targetDate});

  final String id;
  final String type;
  final String title;

  /// `active`, `paused`, `completed`, `abandoned` or `replaced`.
  final String status;
  final String startDate;
  final String? description;
  final String? targetMetric;
  final double? targetValue;
  final String? targetUnit;
  final String? targetDate;

  factory Goal.fromRecord(Map<String, dynamic> r) => Goal(
        id: r['id'] as String,
        type: (r['type'] as String?) ?? '',
        title: (r['title'] as String?) ?? '',
        status: (r['status'] as String?) ?? 'active',
        startDate: (r['start_date'] as String?) ?? '',
        description: r['description'] as String?,
        targetMetric: r['target_metric'] as String?,
        targetValue: _double(r['target_value']),
        targetUnit: r['target_unit'] as String?,
        targetDate: r['target_date'] as String?,
      );
}

class Milestone {
  const Milestone({required this.id, required this.goalId, required this.title, required this.targetValue, this.note});

  final String id;
  final String goalId;
  final String title;
  final double targetValue;
  final String? note;

  factory Milestone.fromRecord(Map<String, dynamic> r) => Milestone(
        id: r['id'] as String,
        goalId: (r['goal_id'] as String?) ?? '',
        title: (r['title'] as String?) ?? '',
        targetValue: _double(r['target_value']) ?? 0,
        note: r['note'] as String?,
      );
}

// ---- Server view rows (cached) ----

class ExerciseTrend {
  const ExerciseTrend({required this.exerciseId, required this.signal, this.changePct, this.sessionsConsidered = 0, this.lastSessionDate});

  final String exerciseId;

  /// `improving`, `plateau`, `declining` or `insufficient_data`. An observation, not an instruction.
  final String signal;
  final double? changePct;
  final int sessionsConsidered;
  final String? lastSessionDate;

  factory ExerciseTrend.fromJson(Map<String, dynamic> r) => ExerciseTrend(
        exerciseId: (r['exercise_id'] as String?) ?? '',
        signal: (r['signal'] as String?) ?? 'insufficient_data',
        changePct: _double(r['change_pct']),
        sessionsConsidered: _int(r['sessions_considered']) ?? 0,
        lastSessionDate: _string(r['last_session_date']),
      );
}

/// One exercise in one session: the best estimated 1RM, heaviest weight, most reps and total volume.
class ExerciseSessionBest {
  const ExerciseSessionBest({required this.exerciseId, required this.sessionId, required this.localDate, this.bestE1rmKg, this.topWeightKg, this.maxReps, this.volumeKg});

  final String exerciseId;
  final String sessionId;
  final String localDate;
  final double? bestE1rmKg;
  final double? topWeightKg;
  final int? maxReps;
  final double? volumeKg;

  factory ExerciseSessionBest.fromJson(Map<String, dynamic> r) => ExerciseSessionBest(
        exerciseId: (r['exercise_id'] as String?) ?? '',
        sessionId: (r['session_id'] as String?) ?? '',
        localDate: (r['local_date'] as String?) ?? '',
        bestE1rmKg: _double(r['best_e1rm_kg']),
        topWeightKg: _double(r['top_weight_kg']),
        maxReps: _int(r['max_reps']),
        volumeKg: _double(r['volume_kg']),
      );
}

class GoalProgress {
  const GoalProgress({required this.goalId, required this.title, required this.goalStatus, required this.progressStatus, this.progressPct, this.expectedPct, this.reached = false, this.startValue, this.currentValue, this.targetValue, this.source, this.asOf});

  final String goalId;
  final String title;
  final String goalStatus;

  /// The server's reading: for example on track, behind or insufficient data (`calc_goal_progress`).
  final String progressStatus;
  final double? progressPct;
  final double? expectedPct;
  final bool reached;
  final double? startValue;
  final double? currentValue;
  final double? targetValue;
  final String? source;
  final String? asOf;

  factory GoalProgress.fromJson(Map<String, dynamic> r) => GoalProgress(
        goalId: (r['goal_id'] as String?) ?? '',
        title: (r['title'] as String?) ?? '',
        goalStatus: (r['goal_status'] as String?) ?? 'active',
        progressStatus: (r['progress_status'] as String?) ?? 'insufficient_data',
        progressPct: _double(r['progress_pct']),
        expectedPct: _double(r['expected_pct']),
        reached: _bool(r['reached']),
        startValue: _double(r['start_value']),
        currentValue: _double(r['current_value']),
        targetValue: _double(r['target_value']),
        source: _string(r['source']),
        asOf: _string(r['as_of']),
      );
}

class MilestoneStatus {
  const MilestoneStatus({required this.milestoneId, required this.goalId, required this.title, required this.targetValue, required this.isReached, this.currentValue});

  final String milestoneId;
  final String goalId;
  final String title;
  final double targetValue;
  final bool isReached;
  final double? currentValue;

  factory MilestoneStatus.fromJson(Map<String, dynamic> r) => MilestoneStatus(
        milestoneId: (r['milestone_id'] as String?) ?? '',
        goalId: (r['goal_id'] as String?) ?? '',
        title: (r['title'] as String?) ?? '',
        targetValue: _double(r['target_value']) ?? 0,
        isReached: _bool(r['is_reached']),
        currentValue: _double(r['current_value']),
      );
}

class MuscleExposure {
  const MuscleExposure({required this.weekStart, required this.muscleId, this.directSets = 0, this.indirectSets = 0, this.trainingDays = 0});

  final String weekStart;
  final String muscleId;
  final int directSets;
  final int indirectSets;
  final int trainingDays;

  factory MuscleExposure.fromJson(Map<String, dynamic> r) => MuscleExposure(
        weekStart: (r['week_start'] as String?) ?? '',
        muscleId: (r['muscle_id'] as String?) ?? '',
        directSets: _int(r['direct_sets']) ?? 0,
        indirectSets: _int(r['indirect_sets']) ?? 0,
        trainingDays: _int(r['training_days']) ?? 0,
      );
}

/// A muscle's own rating (the person's assessment, never calculated from training) and how it changed.
class MuscleRating {
  const MuscleRating({required this.muscleId, required this.muscleKey, this.groupKey, this.currentLevel, this.category, this.ratedOn, this.previousLevel, this.assessmentChange});

  final String muscleId;
  final String muscleKey;
  final String? groupKey;
  final int? currentLevel;
  final String? category;
  final String? ratedOn;
  final int? previousLevel;
  final String? assessmentChange;

  factory MuscleRating.fromJson(Map<String, dynamic> r) => MuscleRating(
        muscleId: (r['muscle_id'] as String?) ?? '',
        muscleKey: (r['muscle_key'] as String?) ?? '',
        groupKey: _string(r['group_key']),
        currentLevel: _int(r['current_level']),
        category: _string(r['category']),
        ratedOn: _string(r['rated_on']),
        previousLevel: _int(r['previous_level']),
        assessmentChange: _string(r['assessment_change']),
      );
}

class BodyComposition {
  const BodyComposition({required this.localDate, this.bodyFatPct, this.weightKg, this.fatMassKg, this.leanMassKg, this.method});

  final String localDate;
  final double? bodyFatPct;
  final double? weightKg;
  final double? fatMassKg;
  final double? leanMassKg;
  final String? method;

  /// Fat and lean mass are estimates derived from a body-fat reading; the server labels them so.
  factory BodyComposition.fromJson(Map<String, dynamic> r) => BodyComposition(
        localDate: (r['local_date'] as String?) ?? '',
        bodyFatPct: _double(r['body_fat_pct']),
        weightKg: _double(r['weight_kg']),
        fatMassKg: _double(r['fat_mass_kg']),
        leanMassKg: _double(r['lean_mass_kg']),
        method: _string(r['method']),
      );
}

// ---- The daily briefing (api_daily_briefing) ----

class BriefingPlan {
  const BriefingPlan({this.status, this.isRestDay = false, this.templateName, this.plannedExercises = 0, this.isBreakDay = false, this.activeSplit});

  final String? status;
  final bool isRestDay;
  final String? templateName;
  final int plannedExercises;
  final bool isBreakDay;
  final String? activeSplit;

  factory BriefingPlan.fromJson(Map<String, dynamic> j) => BriefingPlan(
        status: _string(j['status']),
        isRestDay: _bool(j['is_rest_day']),
        templateName: _string(j['template_name']),
        plannedExercises: _int(j['planned_exercises']) ?? 0,
        isBreakDay: _bool(j['is_break_day']),
        activeSplit: _string(j['active_split']),
      );
}

/// Readiness or deload result. `level` is the server's wording; `reasoning` is human-readable; `note` is the server's
/// reminder that this is decision support only. Shown as given.
class InsightLevel {
  const InsightLevel({required this.level, this.reasoning = const [], this.reasonCodes = const [], this.note, this.wellnessScore, this.valueKind});

  final String level;
  final List<String> reasoning;
  final List<String> reasonCodes;
  final String? note;
  final double? wellnessScore;
  final String? valueKind;

  factory InsightLevel.fromJson(Map<String, dynamic> j) => InsightLevel(
        level: (j['level'] as String?) ?? 'unknown',
        reasoning: _strings(j['reasoning']),
        reasonCodes: _strings(j['reason_codes']),
        note: _string(j['note']),
        wellnessScore: _double(j['wellness_score']),
        valueKind: _string(j['value_kind']),
      );
}

class BriefingContext {
  const BriefingContext({this.lastSessionDate, this.daysSinceLastSession, this.sessionsLast7Days});

  final String? lastSessionDate;
  final int? daysSinceLastSession;
  final int? sessionsLast7Days;

  factory BriefingContext.fromJson(Map<String, dynamic> j) =>
      BriefingContext(lastSessionDate: _string(j['last_session_date']), daysSinceLastSession: _int(j['days_since_last_session']), sessionsLast7Days: _int(j['sessions_last_7_days']));
}

class BriefingSupplement {
  const BriefingSupplement({required this.supplementId, required this.name, this.expectedDoses = 1, this.takenToday = 0});

  final String supplementId;
  final String name;
  final int expectedDoses;
  final int takenToday;

  factory BriefingSupplement.fromJson(Map<String, dynamic> j) => BriefingSupplement(
        supplementId: (j['supplement_id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        expectedDoses: _int(j['expected_doses']) ?? 1,
        takenToday: _int(j['taken_today']) ?? 0,
      );
}

class BriefingRecord {
  const BriefingRecord({required this.kind, required this.value, this.exercise, this.achievedOn});

  final String kind;
  final double value;
  final String? exercise;
  final String? achievedOn;

  factory BriefingRecord.fromJson(Map<String, dynamic> j) =>
      BriefingRecord(kind: (j['kind'] as String?) ?? '', value: _double(j['value']) ?? 0, exercise: _string(j['exercise']), achievedOn: _string(j['achieved_on']));
}

class BriefingTrend {
  const BriefingTrend({required this.exercise, required this.signal, this.changePct});

  final String exercise;
  final String signal;
  final double? changePct;

  factory BriefingTrend.fromJson(Map<String, dynamic> j) =>
      BriefingTrend(exercise: (j['exercise'] as String?) ?? '', signal: (j['signal'] as String?) ?? '', changePct: _double(j['change_pct']));
}

class BriefingWeakPoint {
  const BriefingWeakPoint({required this.muscleKey, this.category, this.priority, this.directSets28d = 0, this.suggestions = const []});

  final String muscleKey;
  final String? category;
  final String? priority;
  final int directSets28d;

  /// Exercise names the server suggests; the person decides whether any fit their split.
  final List<String> suggestions;

  factory BriefingWeakPoint.fromJson(Map<String, dynamic> j) => BriefingWeakPoint(
        muscleKey: (j['muscle_key'] as String?) ?? '',
        category: _string(j['category']),
        priority: _string(j['priority']),
        directSets28d: _int(j['direct_sets_28d']) ?? 0,
        suggestions: [for (final s in _maps(j['suggestions'])) if (_string(s['exercise_name']) != null) s['exercise_name'] as String],
      );
}

/// One call's worth of "today" from the server. Sections the server left out are null or empty.
class DailyBriefing {
  const DailyBriefing({
    required this.date,
    required this.plan,
    this.readiness,
    this.readinessContext,
    this.deload,
    this.restrictionWarnings = const [],
    this.nextTargets = const [],
    this.supplements = const [],
    this.hydrationMl,
    this.waterTargetMl,
    this.eatenProteinG,
    this.proteinTargetG,
    this.eatenCaloriesKcal,
    this.steps,
    this.stepTarget,
    this.reassessmentDue = false,
    this.nextReassessmentDate,
    this.goalCounts = const {},
    this.currentStreak,
    this.longestStreak,
    this.recentRecords = const [],
    this.trends = const [],
    this.weakPoints = const [],
  });

  final String date;
  final BriefingPlan plan;
  final InsightLevel? readiness;
  final BriefingContext? readinessContext;
  final InsightLevel? deload;
  final List<Map<String, dynamic>> restrictionWarnings;
  final List<Map<String, dynamic>> nextTargets;
  final List<BriefingSupplement> supplements;
  final int? hydrationMl;
  final int? waterTargetMl;
  final double? eatenProteinG;
  final double? proteinTargetG;
  final double? eatenCaloriesKcal;
  final int? steps;
  final int? stepTarget;
  final bool reassessmentDue;
  final String? nextReassessmentDate;

  /// Goal count by the server's progress status (for example `on_track: 2`).
  final Map<String, int> goalCounts;
  final int? currentStreak;
  final int? longestStreak;
  final List<BriefingRecord> recentRecords;
  final List<BriefingTrend> trends;
  final List<BriefingWeakPoint> weakPoints;

  factory DailyBriefing.fromJson(Map<String, dynamic> j) {
    final readiness = _map(j['readiness']);
    final hydration = _map(j['hydration']);
    final nutrition = _map(j['nutrition']);
    final steps = _map(j['steps']);
    final reassessment = _map(j['reassessment']);
    final streak = _map(j['streak']);
    final weak = j['weak_points'];
    final weakMaps = weak is List ? _maps(weak) : (weak is Map ? _maps(weak.values.toList()) : const <Map<String, dynamic>>[]);
    return DailyBriefing(
      date: (j['date'] as String?) ?? '',
      plan: BriefingPlan.fromJson(_map(j['plan'])),
      readiness: readiness.isEmpty ? null : InsightLevel.fromJson(readiness),
      readinessContext: _map(readiness['context']).isEmpty ? null : BriefingContext.fromJson(_map(readiness['context'])),
      deload: _map(j['deload']).isEmpty ? null : InsightLevel.fromJson(_map(j['deload'])),
      restrictionWarnings: _maps(j['restriction_warnings']),
      nextTargets: _maps(_map(j['next_targets'])['suggestions'] ?? j['next_targets']),
      supplements: [for (final s in _maps(j['supplements_today'])) BriefingSupplement.fromJson(s)],
      hydrationMl: _int(hydration['total_ml']),
      waterTargetMl: _int(j['water_target_ml']),
      eatenProteinG: _double(nutrition['eaten_protein_g']),
      proteinTargetG: _double(nutrition['protein_target_g']),
      eatenCaloriesKcal: _double(nutrition['eaten_calories_kcal']),
      steps: _int(steps['steps']),
      stepTarget: _int(steps['target']),
      reassessmentDue: _bool(reassessment['is_due']),
      nextReassessmentDate: _string(reassessment['next_due_date']),
      goalCounts: {for (final e in _map(j['goals']).entries) e.key: _int(e.value) ?? 0},
      currentStreak: _int(streak['current_streak']),
      longestStreak: _int(streak['longest_streak']),
      recentRecords: [for (final r in _maps(j['recent_records'])) BriefingRecord.fromJson(r)],
      trends: [for (final t in _maps(j['trends'])) BriefingTrend.fromJson(t)],
      weakPoints: [for (final w in weakMaps) BriefingWeakPoint.fromJson(w)],
    );
  }
}

/// One workout from `v_session_summary`: the server's totals for a session (paused time already removed from the duration).
class SessionSummaryRow {
  const SessionSummaryRow({required this.sessionId, required this.localDate, required this.status, this.durationSeconds, this.workingSets = 0, this.volumeKg = 0});

  final String sessionId;
  final String localDate;
  final String status;
  final int? durationSeconds;
  final int workingSets;
  final double volumeKg;

  /// A workout counts only when it was finished and has at least one logged working set.
  bool get counts => status == 'completed' && workingSets > 0;

  factory SessionSummaryRow.fromJson(Map<String, dynamic> r) => SessionSummaryRow(
        sessionId: (r['session_id'] as String?) ?? '',
        localDate: (r['local_date'] as String?) ?? '',
        status: (r['status'] as String?) ?? '',
        durationSeconds: _int(r['duration_s']),
        workingSets: _int(r['working_sets']) ?? 0,
        volumeKg: _double(r['volume_kg']) ?? 0,
      );
}
