/// Typed views over the records the Training screens use. Each `fromRecord` reads a server-shaped row (the maps the
/// local store holds). Numbers may arrive as numbers or as text, so they are read defensively.
library;

double? _double(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

class Exercise {
  const Exercise({required this.id, required this.name, this.category, this.equipmentId, this.notes, this.isCustom = true});

  final String id;
  final String name;
  final String? category;
  final String? equipmentId;
  final String? notes;
  final bool isCustom;

  factory Exercise.fromRecord(Map<String, dynamic> r) => Exercise(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        category: r['category'] as String?,
        equipmentId: r['equipment_id'] as String?,
        notes: r['notes'] as String?,
        isCustom: r['is_custom'] != false,
      );
}

class TemplateVersion {
  const TemplateVersion({required this.id, required this.templateId, required this.version, required this.name, this.effectiveFrom, this.effectiveTo});

  final String id;
  final String templateId;
  final int version;
  final String name;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;

  bool get isCurrent => effectiveTo == null;

  factory TemplateVersion.fromRecord(Map<String, dynamic> r) => TemplateVersion(
        id: r['id'] as String,
        templateId: r['entity_id'] as String,
        version: _int(r['version']) ?? 1,
        name: (r['name'] as String?) ?? '',
        effectiveFrom: _time(r['effective_from']),
        effectiveTo: _time(r['effective_to']),
      );
}

/// One exercise of a template version, with its prescription (sets, rep range, weight, rest, effort targets).
class TemplateExercise {
  const TemplateExercise({
    required this.id,
    required this.templateVersionId,
    required this.exerciseId,
    required this.position,
    this.targetSets = 3,
    this.repMin,
    this.repMax,
    this.startWeightKg,
    this.restSeconds,
    this.rirTarget,
    this.rpeTarget,
    this.warmupGuidance,
    this.notes,
  });

  final String id;
  final String templateVersionId;
  final String exerciseId;
  final int position;
  final int targetSets;
  final int? repMin;
  final int? repMax;
  final double? startWeightKg;
  final int? restSeconds;
  final int? rirTarget;
  final double? rpeTarget;
  final String? warmupGuidance;
  final String? notes;

  factory TemplateExercise.fromRecord(Map<String, dynamic> r) => TemplateExercise(
        id: r['id'] as String,
        templateVersionId: r['template_version_id'] as String,
        exerciseId: r['exercise_id'] as String,
        position: _int(r['position']) ?? 1,
        targetSets: _int(r['target_sets']) ?? 3,
        repMin: _int(r['rep_min']),
        repMax: _int(r['rep_max']),
        startWeightKg: _double(r['start_weight_kg']),
        restSeconds: _int(r['rest_s']),
        rirTarget: _int(r['rir_target']),
        rpeTarget: _double(r['rpe_target']),
        warmupGuidance: r['warmup_guidance'] as String?,
        notes: r['notes'] as String?,
      );
}

class SplitDay {
  const SplitDay({required this.id, required this.position, required this.label, this.isRest = false, this.templateId});

  final String id;
  final int position;
  final String label;
  final bool isRest;
  final String? templateId;

  factory SplitDay.fromRecord(Map<String, dynamic> r) => SplitDay(
        id: r['id'] as String,
        position: _int(r['position']) ?? 1,
        label: (r['label'] as String?) ?? '',
        isRest: r['is_rest'] == true,
        templateId: r['template_id'] as String?,
      );
}

/// The split that is active now, with its current version and days.
class ActiveSplit {
  const ActiveSplit({required this.splitId, required this.versionId, required this.name, required this.pattern, this.cycleLengthDays, required this.days});

  final String splitId;
  final String versionId;
  final String name;
  final String pattern;
  final int? cycleLengthDays;
  final List<SplitDay> days;
}

class ScheduleEntry {
  const ScheduleEntry({
    required this.id,
    required this.localDate,
    this.isRestDay = false,
    this.splitVersionId,
    this.splitDayId,
    this.templateVersionId,
    this.status = 'planned',
    this.sessionId,
  });

  final String id;
  final String localDate;
  final bool isRestDay;
  final String? splitVersionId;
  final String? splitDayId;
  final String? templateVersionId;
  final String status;
  final String? sessionId;

  factory ScheduleEntry.fromRecord(Map<String, dynamic> r) => ScheduleEntry(
        id: r['id'] as String,
        localDate: (r['local_date'] as String?) ?? '',
        isRestDay: r['is_rest_day'] == true,
        splitVersionId: r['split_version_id'] as String?,
        splitDayId: r['split_day_id'] as String?,
        templateVersionId: r['template_version_id'] as String?,
        status: (r['status'] as String?) ?? 'planned',
        sessionId: r['session_id'] as String?,
      );
}

class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.localDate,
    this.name,
    required this.status,
    this.scheduleEntryId,
    this.splitVersionId,
    this.splitDayId,
    this.templateVersionId,
    this.pausedSeconds = 0,
    this.notes,
    this.postNotes,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String localDate;
  final String? name;

  /// `in_progress`, `paused`, `completed` or `abandoned`.
  final String status;
  final String? scheduleEntryId;
  final String? splitVersionId;
  final String? splitDayId;
  final String? templateVersionId;
  final int pausedSeconds;
  final String? notes;
  final String? postNotes;

  bool get isActive => status == 'in_progress' || status == 'paused';

  factory WorkoutSession.fromRecord(Map<String, dynamic> r) => WorkoutSession(
        id: r['id'] as String,
        startedAt: _time(r['occurred_at']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        endedAt: _time(r['ended_at']),
        localDate: (r['local_date'] as String?) ?? '',
        name: r['name'] as String?,
        status: (r['status'] as String?) ?? 'in_progress',
        scheduleEntryId: r['schedule_entry_id'] as String?,
        splitVersionId: r['split_version_id'] as String?,
        splitDayId: r['split_day_id'] as String?,
        templateVersionId: r['template_version_id'] as String?,
        pausedSeconds: _int(r['paused_seconds']) ?? 0,
        notes: r['notes'] as String?,
        postNotes: r['post_notes'] as String?,
      );
}

class SessionExercise {
  const SessionExercise({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.position,
    required this.status,
    this.skipReason,
    this.templateExerciseId,
    this.prescription,
    this.notes,
  });

  final String id;
  final String sessionId;
  final String exerciseId;
  final int position;

  /// `done`, `skipped` or `added`.
  final String status;
  final String? skipReason;
  final String? templateExerciseId;

  /// The prescription copied by the server when the exercise came from a template. Null until it has synced.
  final Map<String, dynamic>? prescription;
  final String? notes;

  bool get isSkipped => status == 'skipped';

  factory SessionExercise.fromRecord(Map<String, dynamic> r) => SessionExercise(
        id: r['id'] as String,
        sessionId: r['session_id'] as String,
        exerciseId: r['exercise_id'] as String,
        position: _int(r['position']) ?? 1,
        status: (r['status'] as String?) ?? 'done',
        skipReason: r['skip_reason'] as String?,
        templateExerciseId: r['template_exercise_id'] as String?,
        prescription: r['prescription_snapshot'] is Map ? Map<String, dynamic>.from(r['prescription_snapshot'] as Map) : null,
        notes: r['notes'] as String?,
      );
}

class LoggedSet {
  const LoggedSet({
    required this.id,
    required this.sessionExerciseId,
    required this.setNumber,
    required this.setType,
    this.weightKg,
    this.reps,
    this.completed = true,
    this.rir,
    this.rpe,
    this.restSeconds,
    this.notes,
    this.occurredAt,
  });

  final String id;
  final String sessionExerciseId;
  final int setNumber;

  /// `warmup` or `working`.
  final String setType;
  final double? weightKg;
  final int? reps;
  final bool completed;
  final int? rir;
  final double? rpe;
  final int? restSeconds;
  final String? notes;
  final DateTime? occurredAt;

  bool get isWorking => setType == 'working';

  factory LoggedSet.fromRecord(Map<String, dynamic> r) => LoggedSet(
        id: r['id'] as String,
        sessionExerciseId: r['session_exercise_id'] as String,
        setNumber: _int(r['set_number']) ?? 1,
        setType: (r['set_type'] as String?) ?? 'working',
        weightKg: _double(r['weight_kg']),
        reps: _int(r['reps']),
        completed: r['completed'] != false,
        rir: _int(r['rir']),
        rpe: _double(r['rpe']),
        restSeconds: _int(r['rest_s']),
        notes: r['notes'] as String?,
        occurredAt: _time(r['occurred_at']),
      );
}

/// Totals for one session, worked out from the sets held on the phone with the same rules as the backend view
/// `v_session_summary`: only completed working sets count towards sets, reps and volume, and paused time is not
/// part of the duration. Display only.
class SessionSummary {
  const SessionSummary({
    required this.durationSeconds,
    required this.exercisesDone,
    required this.exercisesSkipped,
    required this.workingSets,
    required this.totalReps,
    required this.volumeKg,
  });

  final int? durationSeconds;
  final int exercisesDone;
  final int exercisesSkipped;
  final int workingSets;
  final int totalReps;
  final double volumeKg;
}

/// What was done for an exercise the last time it was trained (shown while logging).
class PreviousPerformance {
  const PreviousPerformance({required this.sessionId, required this.localDate, required this.sets});

  final String sessionId;
  final String localDate;
  final List<LoggedSet> sets;

  List<LoggedSet> get workingSets => [for (final s in sets) if (s.isWorking && s.completed) s];
}
