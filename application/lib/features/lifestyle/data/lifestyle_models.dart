/// Typed views over the Lifestyle records the screens use. Each `fromRecord` reads a server-shaped row (the maps the
/// local store holds). Numbers may arrive as numbers or as text, so they are read defensively.
library;

double? _double(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
int? _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

class BodyRegion {
  const BodyRegion({required this.id, required this.name});

  final String id;
  final String name;

  factory BodyRegion.fromRecord(Map<String, dynamic> r) => BodyRegion(id: r['id'] as String, name: (r['name'] as String?) ?? (r['code'] as String?) ?? '');
}

/// One check-in per day (the database allows only one). Ratings are 1 to 5.
class DailyCheckin {
  const DailyCheckin({
    required this.id,
    required this.localDate,
    this.energy,
    this.sleepQuality,
    this.soreness,
    this.fatigue,
    this.motivation,
    this.stress,
    this.painFlag = false,
    this.notes,
  });

  final String id;
  final String localDate;
  final int? energy;
  final int? sleepQuality;
  final int? soreness;
  final int? fatigue;
  final int? motivation;
  final int? stress;
  final bool painFlag;
  final String? notes;

  factory DailyCheckin.fromRecord(Map<String, dynamic> r) => DailyCheckin(
        id: r['id'] as String,
        localDate: (r['local_date'] as String?) ?? '',
        energy: _int(r['energy']),
        sleepQuality: _int(r['sleep_quality']),
        soreness: _int(r['soreness']),
        fatigue: _int(r['fatigue']),
        motivation: _int(r['motivation']),
        stress: _int(r['stress']),
        painFlag: r['pain_flag'] == true,
        notes: r['notes'] as String?,
      );
}

class SleepLog {
  const SleepLog({required this.id, required this.localDate, required this.durationSeconds, this.sleepAt, this.wakeAt, this.quality, this.isNap = false, this.notes});

  final String id;

  /// The day the person woke up.
  final String localDate;
  final int durationSeconds;
  final DateTime? sleepAt;
  final DateTime? wakeAt;
  final int? quality;
  final bool isNap;
  final String? notes;

  double get hours => durationSeconds / 3600;

  factory SleepLog.fromRecord(Map<String, dynamic> r) => SleepLog(
        id: r['id'] as String,
        localDate: (r['local_date'] as String?) ?? '',
        durationSeconds: _int(r['duration_s']) ?? 0,
        sleepAt: _time(r['sleep_at']),
        wakeAt: _time(r['wake_at']),
        quality: _int(r['quality']),
        isNap: r['is_nap'] == true,
        notes: r['notes'] as String?,
      );
}

class DailySteps {
  const DailySteps({required this.id, required this.localDate, required this.steps, this.targetSteps, this.source = 'manual'});

  final String id;
  final String localDate;
  final int steps;
  final int? targetSteps;
  final String source;

  factory DailySteps.fromRecord(Map<String, dynamic> r) => DailySteps(
        id: r['id'] as String,
        localDate: (r['local_date'] as String?) ?? '',
        steps: _int(r['steps']) ?? 0,
        targetSteps: _int(r['target_steps']),
        source: (r['source'] as String?) ?? 'manual',
      );
}

class WaterLog {
  const WaterLog({required this.id, required this.localDate, required this.amountMl, this.occurredAt});

  final String id;
  final String localDate;
  final int amountMl;
  final DateTime? occurredAt;

  factory WaterLog.fromRecord(Map<String, dynamic> r) => WaterLog(
        id: r['id'] as String,
        localDate: (r['local_date'] as String?) ?? '',
        amountMl: _int(r['amount_ml']) ?? 0,
        occurredAt: _time(r['occurred_at']),
      );
}

class CardioSession {
  const CardioSession({
    required this.id,
    required this.localDate,
    required this.activity,
    this.customActivity,
    required this.durationSeconds,
    this.distanceM,
    this.caloriesKcal,
    this.intensity,
    this.notes,
    this.occurredAt,
  });

  final String id;
  final String localDate;
  final String activity;
  final String? customActivity;
  final int durationSeconds;
  final double? distanceM;
  final double? caloriesKcal;
  final String? intensity;
  final String? notes;
  final DateTime? occurredAt;

  String get label => activity == 'custom' ? (customActivity ?? 'Cardio') : '${activity[0].toUpperCase()}${activity.substring(1)}';

  factory CardioSession.fromRecord(Map<String, dynamic> r) => CardioSession(
        id: r['id'] as String,
        localDate: (r['local_date'] as String?) ?? '',
        activity: (r['activity'] as String?) ?? 'custom',
        customActivity: r['custom_activity'] as String?,
        durationSeconds: _int(r['duration_s']) ?? 0,
        distanceM: _double(r['distance_m']),
        caloriesKcal: _double(r['calories_kcal']),
        intensity: r['intensity'] as String?,
        notes: r['notes'] as String?,
        occurredAt: _time(r['occurred_at']),
      );
}

class BodyMeasurement {
  const BodyMeasurement({required this.id, required this.localDate, required this.type, required this.value, this.method, this.customLabel, this.customUnit, this.occurredAt});

  final String id;
  final String localDate;
  final String type;
  final double value;
  final String? method;
  final String? customLabel;
  final String? customUnit;
  final DateTime? occurredAt;

  factory BodyMeasurement.fromRecord(Map<String, dynamic> r) => BodyMeasurement(
        id: r['id'] as String,
        localDate: (r['local_date'] as String?) ?? '',
        type: (r['measurement_type'] as String?) ?? '',
        value: _double(r['value']) ?? 0,
        method: r['method'] as String?,
        customLabel: r['custom_label'] as String?,
        customUnit: r['custom_unit'] as String?,
        occurredAt: _time(r['occurred_at']),
      );
}

class Injury {
  const Injury({required this.id, required this.name, required this.bodyRegionId, required this.side, required this.startDate, required this.status, this.severity, this.injuryType, this.notes, this.resolvedOn});

  final String id;
  final String name;
  final String bodyRegionId;
  final String side;
  final String startDate;
  final String status;
  final String? severity;
  final String? injuryType;
  final String? notes;
  final String? resolvedOn;

  bool get isResolved => status == 'resolved';

  factory Injury.fromRecord(Map<String, dynamic> r) => Injury(
        id: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        bodyRegionId: (r['body_region_id'] as String?) ?? '',
        side: (r['side'] as String?) ?? 'not_applicable',
        startDate: (r['start_date'] as String?) ?? '',
        status: (r['status'] as String?) ?? 'active',
        severity: r['severity'] as String?,
        injuryType: r['injury_type'] as String?,
        notes: r['notes'] as String?,
        resolvedOn: r['resolved_on'] as String?,
      );
}

class PainEntry {
  const PainEntry({required this.id, required this.localDate, required this.bodyRegionId, required this.side, required this.level, required this.effectOnTraining, this.painType, this.injuryId, this.notes, this.occurredAt});

  final String id;
  final String localDate;
  final String bodyRegionId;
  final String side;
  final int level;
  final String effectOnTraining;
  final String? painType;
  final String? injuryId;
  final String? notes;
  final DateTime? occurredAt;

  factory PainEntry.fromRecord(Map<String, dynamic> r) => PainEntry(
        id: r['id'] as String,
        localDate: (r['local_date'] as String?) ?? '',
        bodyRegionId: (r['body_region_id'] as String?) ?? '',
        side: (r['side'] as String?) ?? 'not_applicable',
        level: _int(r['level']) ?? 0,
        effectOnTraining: (r['effect_on_training'] as String?) ?? 'none',
        painType: r['pain_type'] as String?,
        injuryId: r['injury_id'] as String?,
        notes: r['notes'] as String?,
        occurredAt: _time(r['occurred_at']),
      );
}

class ExerciseRestriction {
  const ExerciseRestriction({required this.id, required this.kind, required this.source, required this.activeFrom, this.exerciseId, this.movement, this.injuryId, this.note, this.activeTo});

  final String id;

  /// `uncomfortable`, `avoid` or `modify`.
  final String kind;
  final String source;
  final String activeFrom;
  final String? activeTo;
  final String? exerciseId;
  final String? movement;
  final String? injuryId;
  final String? note;

  factory ExerciseRestriction.fromRecord(Map<String, dynamic> r) => ExerciseRestriction(
        id: r['id'] as String,
        kind: (r['kind'] as String?) ?? 'uncomfortable',
        source: (r['source'] as String?) ?? 'self',
        activeFrom: (r['active_from'] as String?) ?? '',
        activeTo: r['active_to'] as String?,
        exerciseId: r['exercise_id'] as String?,
        movement: r['movement'] as String?,
        injuryId: r['injury_id'] as String?,
        note: r['note'] as String?,
      );
}

class Supplement {
  const Supplement({required this.id, required this.name, this.category, this.notes});

  final String id;
  final String name;
  final String? category;
  final String? notes;

  factory Supplement.fromRecord(Map<String, dynamic> r) =>
      Supplement(id: r['id'] as String, name: (r['name'] as String?) ?? '', category: r['category'] as String?, notes: r['notes'] as String?);
}

class SupplementPhase {
  const SupplementPhase({
    required this.id,
    required this.supplementId,
    required this.version,
    required this.status,
    this.doseAmount,
    this.doseUnit,
    this.timesPerDay = 1,
    this.daysOfWeek = const [],
    this.effectiveTo,
  });

  final String id;
  final String supplementId;
  final int version;

  /// `active`, `paused` or `stopped`.
  final String status;
  final double? doseAmount;
  final String? doseUnit;
  final int timesPerDay;

  /// ISO weekdays (1 = Monday); empty means every day.
  final List<int> daysOfWeek;
  final DateTime? effectiveTo;

  bool get isCurrent => effectiveTo == null;

  factory SupplementPhase.fromRecord(Map<String, dynamic> r) => SupplementPhase(
        id: r['id'] as String,
        supplementId: r['entity_id'] as String,
        version: _int(r['version']) ?? 1,
        status: (r['status'] as String?) ?? 'active',
        doseAmount: _double(r['dose_amount']),
        doseUnit: r['dose_unit'] as String?,
        timesPerDay: _int(r['times_per_day']) ?? 1,
        daysOfWeek: r['days_of_week'] is List ? [for (final d in r['days_of_week'] as List) if (_int(d) != null) _int(d)!] : const [],
        effectiveTo: _time(r['effective_to']),
      );
}

class SupplementLog {
  const SupplementLog({required this.id, required this.supplementId, required this.outcome, required this.localDate, this.quantity, this.unit, this.occurredAt});

  final String id;
  final String supplementId;

  /// `taken`, `missed` or `skipped`.
  final String outcome;
  final String localDate;
  final double? quantity;
  final String? unit;
  final DateTime? occurredAt;

  factory SupplementLog.fromRecord(Map<String, dynamic> r) => SupplementLog(
        id: r['id'] as String,
        supplementId: (r['supplement_id'] as String?) ?? '',
        outcome: (r['outcome'] as String?) ?? 'taken',
        localDate: (r['local_date'] as String?) ?? '',
        quantity: _double(r['quantity']),
        unit: r['unit'] as String?,
        occurredAt: _time(r['occurred_at']),
      );
}

class Meal {
  const Meal({required this.id, required this.title, required this.category, this.caloriesKcal, this.proteinG, this.carbsG, this.fatG, this.fibreG, this.isEstimate = false, this.notes});

  final String id;
  final String title;
  final String category;
  final double? caloriesKcal;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fibreG;
  final bool isEstimate;
  final String? notes;

  factory Meal.fromRecord(Map<String, dynamic> r) => Meal(
        id: r['id'] as String,
        title: (r['title'] as String?) ?? '',
        category: (r['category'] as String?) ?? 'snack',
        caloriesKcal: _double(r['calories_kcal']),
        proteinG: _double(r['protein_g']),
        carbsG: _double(r['carbs_g']),
        fatG: _double(r['fat_g']),
        fibreG: _double(r['fibre_g']),
        isEstimate: r['nutrition_is_estimate'] == true,
        notes: r['notes'] as String?,
      );
}

class MealPlanEntry {
  const MealPlanEntry({required this.id, required this.localDate, required this.slot, required this.mealId, this.servings = 1, this.status = 'planned', this.replacedByMealId});

  final String id;
  final String localDate;

  /// `breakfast`, `lunch`, `dinner` or `snack`.
  final String slot;
  final String mealId;
  final double servings;

  /// `planned`, `eaten` or `replaced`.
  final String status;
  final String? replacedByMealId;

  factory MealPlanEntry.fromRecord(Map<String, dynamic> r) => MealPlanEntry(
        id: r['id'] as String,
        localDate: (r['local_date'] as String?) ?? '',
        slot: (r['slot'] as String?) ?? 'snack',
        mealId: (r['meal_id'] as String?) ?? '',
        servings: _double(r['servings']) ?? 1,
        status: (r['status'] as String?) ?? 'planned',
        replacedByMealId: r['replaced_by_meal_id'] as String?,
      );
}

/// The current personal targets (one version is open at a time).
class PersonalTargets {
  const PersonalTargets({required this.id, required this.entityId, required this.version, this.proteinG, this.caloriesKcal, this.waterMl, this.stepTarget});

  final String id;
  final String entityId;
  final int version;
  final double? proteinG;
  final double? caloriesKcal;
  final int? waterMl;
  final int? stepTarget;

  factory PersonalTargets.fromRecord(Map<String, dynamic> r) => PersonalTargets(
        id: r['id'] as String,
        entityId: r['entity_id'] as String,
        version: _int(r['version']) ?? 1,
        proteinG: _double(r['protein_g']),
        caloriesKcal: _double(r['calories_kcal']),
        waterMl: _int(r['water_ml']),
        stepTarget: _int(r['step_target']),
      );
}

/// What one day looks like, worked out from the records held on the phone. Display only: nothing here is a
/// readiness or recovery score (those come from the backend).
class DaySummary {
  const DaySummary({
    required this.localDate,
    this.checkin,
    this.sleepSeconds = 0,
    this.steps,
    this.waterMl = 0,
    this.supplementsTaken = 0,
    this.mealsEaten = 0,
    this.mealsPlanned = 0,
    this.cardioSeconds = 0,
  });

  final String localDate;
  final DailyCheckin? checkin;
  final int sleepSeconds;
  final DailySteps? steps;
  final int waterMl;
  final int supplementsTaken;
  final int mealsEaten;
  final int mealsPlanned;
  final int cardioSeconds;
}
