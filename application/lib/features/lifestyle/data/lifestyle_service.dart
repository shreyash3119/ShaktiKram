import '../../../core/auth/uuid.dart';
import '../../../core/sync/change_writer.dart';
import '../../../core/time/local_stamp.dart';
import 'lifestyle_repository.dart';

const bodySides = ['left', 'right', 'both', 'not_applicable'];
const cardioActivities = ['walking', 'running', 'cycling', 'treadmill', 'stairmaster', 'elliptical', 'custom'];
const mealCategories = ['breakfast', 'lunch', 'dinner', 'snack'];

/// Everything Lifestyle writes. Each call is one atomic local step queued through the outbox, so it works offline and
/// survives a restart. Values are checked here against the same limits as the database so the server never has to
/// refuse a normal entry. Nothing is calculated here that the backend also calculates.
class LifestyleService {
  LifestyleService({required this.writer, required this.repository, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ChangeWriter writer;
  final LifestyleRepository repository;
  final DateTime Function() _clock;

  String get today => localStampOf(_clock()).localDate;

  static void _rating(String name, int? v) {
    if (v != null && (v < 1 || v > 5)) throw ArgumentError('$name must be between 1 and 5.');
  }

  static void _positive(String name, num? v) {
    if (v != null && v <= 0) throw ArgumentError('$name must be more than zero.');
  }

  static void _oneOf(String name, String? v, List<String> allowed) {
    if (v != null && !allowed.contains(v)) throw ArgumentError('$name is not one of: ${allowed.join(', ')}.');
  }

  // ---- Check-in (one per day: saving again edits it) ----

  Future<String> saveCheckin({
    String? localDate,
    int? energy,
    int? sleepQuality,
    int? soreness,
    int? fatigue,
    int? motivation,
    int? stress,
    bool painFlag = false,
    String? notes,
  }) async {
    for (final e in {'Energy': energy, 'Sleep quality': sleepQuality, 'Soreness': soreness, 'Fatigue': fatigue, 'Motivation': motivation, 'Stress': stress}.entries) {
      _rating(e.key, e.value);
    }
    final date = localDate ?? today;
    final existing = await repository.checkinFor(date);
    final body = {
      'energy': energy,
      'sleep_quality': sleepQuality,
      'soreness': soreness,
      'fatigue': fatigue,
      'motivation': motivation,
      'stress': stress,
      'pain_flag': painFlag,
      'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
    };
    return writer.upsert('daily_checkins', {'local_date': date, ...body}, id: existing?.id);
  }

  // ---- Sleep ----

  /// Logs sleep from bed and wake times (duration is worked out) or from [durationSeconds] alone (then [wakeAt] defaults
  /// to now). The record's day is the day of waking.
  Future<String> logSleep({DateTime? sleepAt, DateTime? wakeAt, int? durationSeconds, int? quality, bool isNap = false, String? notes}) async {
    _rating('Sleep quality', quality);
    var wake = wakeAt;
    var duration = durationSeconds;
    if (sleepAt != null && wakeAt != null) {
      if (!wakeAt.isAfter(sleepAt)) throw ArgumentError('Wake time must be after bed time.');
      duration = wakeAt.difference(sleepAt).inSeconds;
    }
    if (duration == null) throw ArgumentError('Give bed and wake times, or a duration.');
    if (duration <= 0 || duration > 86400) throw ArgumentError('Sleep must be between 1 second and 24 hours.');
    wake ??= _clock();
    return writer.upsert('sleep_logs', {
      'local_date': localStampOf(wake).localDate,
      if (sleepAt != null) 'sleep_at': sleepAt.toUtc().toIso8601String(),
      if (sleepAt != null || wakeAt != null) 'wake_at': wake.toUtc().toIso8601String(),
      'duration_s': duration,
      if (quality != null) 'quality': quality,
      'is_nap': isNap,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  Future<void> editSleep(String id, {int? quality, String? notes}) {
    _rating('Sleep quality', quality);
    return writer.apply([
      PendingChange.upsert('sleep_logs', {if (quality != null) 'quality': quality, if (notes != null) 'notes': notes.trim().isEmpty ? null : notes.trim()}, id: id),
    ]);
  }

  Future<void> deleteSleep(String id) => writer.delete('sleep_logs', id);

  // ---- Steps (one per day: saving again edits it) ----

  Future<String> setSteps(int steps, {String? localDate, int? targetSteps, String source = 'manual'}) async {
    if (steps < 0) throw ArgumentError('Steps cannot be negative.');
    _positive('Step target', targetSteps);
    _oneOf('Source', source, const ['manual', 'device_import', 'estimate']);
    final date = localDate ?? today;
    final existing = await repository.stepsFor(date);
    return writer.upsert('daily_steps', {
      'local_date': date,
      'steps': steps,
      'source': source,
      if (targetSteps != null) 'target_steps': targetSteps,
    }, id: existing?.id);
  }

  // ---- Water ----

  Future<String> addWater(int amountMl) {
    if (amountMl <= 0) throw ArgumentError('Water must be more than zero.');
    return writer.upsert('water_logs', {...localStampOf(_clock()).toPayload(), 'amount_ml': amountMl});
  }

  Future<void> deleteWater(String id) => writer.delete('water_logs', id);

  // ---- Cardio ----

  Future<String> logCardio({
    required String activity,
    String? customActivity,
    required int durationSeconds,
    double? distanceM,
    double? caloriesKcal,
    String? intensity,
    String? notes,
    DateTime? at,
  }) {
    _oneOf('Activity', activity, cardioActivities);
    _oneOf('Intensity', intensity, const ['low', 'moderate', 'high']);
    if (durationSeconds <= 0) throw ArgumentError('Duration must be more than zero.');
    if (distanceM != null && distanceM < 0) throw ArgumentError('Distance cannot be negative.');
    if (caloriesKcal != null && caloriesKcal < 0) throw ArgumentError('Calories cannot be negative.');
    if (activity == 'custom' && (customActivity == null || customActivity.trim().isEmpty)) throw ArgumentError('Name the activity.');
    return writer.upsert('cardio_sessions', {
      ...localStampOf(at ?? _clock()).toPayload(),
      'activity': activity,
      if (activity == 'custom') 'custom_activity': customActivity!.trim(),
      'duration_s': durationSeconds,
      if (distanceM != null) 'distance_m': distanceM,
      if (caloriesKcal != null) 'calories_kcal': caloriesKcal,
      if (intensity != null) 'intensity': intensity,
      'source': 'manual',
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  // ---- Body measurements ----

  Future<String> logMeasurement({required String type, required double value, String? method, String? customLabel, String? customUnit, String? side, String? notes}) {
    _oneOf('Measurement', type, const ['weight', 'body_fat', 'muscle_mass', 'waist', 'chest', 'arm', 'thigh', 'custom']);
    _oneOf('Method', method, const ['manual', 'smart_scale_bia', 'skinfold', 'circumference_estimate']);
    _oneOf('Side', side, bodySides);
    if (value <= 0) throw ArgumentError('A measurement must be more than zero.');
    if (type == 'body_fat' && value >= 100) throw ArgumentError('Body fat must be under 100%.');
    if (type == 'body_fat' && method == null) throw ArgumentError('Say how body fat was measured.');
    if (type == 'custom' && ((customLabel ?? '').trim().isEmpty || (customUnit ?? '').trim().isEmpty)) throw ArgumentError('Give the custom measurement a name and unit.');
    return writer.upsert('body_measurements', {
      ...localStampOf(_clock()).toPayload(),
      'measurement_type': type,
      'value': value,
      'source': 'manual',
      if (method != null) 'method': method,
      if (type == 'custom') 'custom_label': customLabel!.trim(),
      if (type == 'custom') 'custom_unit': customUnit!.trim(),
      if (side != null) 'side': side,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  // ---- Injuries, pain, restrictions ----

  Future<String> addInjury({required String name, required String bodyRegionId, String side = 'not_applicable', String? injuryType, String? severity, String? startDate, String? notes}) {
    if (name.trim().isEmpty) throw ArgumentError('Give the injury a name.');
    _oneOf('Side', side, bodySides);
    _oneOf('Severity', severity, const ['mild', 'moderate', 'severe']);
    return writer.upsert('injuries', {
      'name': name.trim(),
      'body_region_id': bodyRegionId,
      'side': side,
      'start_date': startDate ?? today,
      'status': 'active',
      if (injuryType != null && injuryType.trim().isNotEmpty) 'injury_type': injuryType.trim(),
      if (severity != null) 'severity': severity,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  /// Adds a dated update to an injury and moves the injury's own status/severity to match. Resolving sets the
  /// resolved date (today unless given), which the database requires and which cannot be before the start date.
  Future<void> updateInjury(String injuryId, {String? note, String? severity, String? status, String? resolvedOn}) async {
    _oneOf('Severity', severity, const ['mild', 'moderate', 'severe']);
    _oneOf('Status', status, const ['active', 'recovering', 'resolved']);
    if (note == null && severity == null && status == null) throw ArgumentError('Add a note, severity or status.');
    final injury = await repository.injury(injuryId);
    if (injury == null) throw StateError('That injury is not on this phone.');
    final resolved = status == 'resolved' ? (resolvedOn ?? today) : null;
    if (resolved != null && resolved.compareTo(injury.startDate) < 0) throw ArgumentError('An injury cannot be resolved before it started.');
    await writer.apply([
      PendingChange.upsert('injury_updates', {
        ...localStampOf(_clock()).toPayload(),
        'injury_id': injuryId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (severity != null) 'severity': severity,
        if (status != null) 'status': status,
      }),
      PendingChange.upsert('injuries', {
        if (severity != null) 'severity': severity,
        if (status != null) 'status': status,
        if (resolved != null) 'resolved_on': resolved,
      }, id: injuryId),
    ]);
  }

  Future<String> logPain({
    required String bodyRegionId,
    required int level,
    String side = 'not_applicable',
    String? painType,
    String effectOnTraining = 'none',
    String? injuryId,
    String? checkinId,
    String? notes,
  }) {
    if (level < 0 || level > 10) throw ArgumentError('Pain level must be between 0 and 10.');
    _oneOf('Side', side, bodySides);
    _oneOf('Effect on training', effectOnTraining, const ['none', 'minor', 'limited_movement', 'stopped_training']);
    return writer.upsert('pain_entries', {
      ...localStampOf(_clock()).toPayload(),
      'body_region_id': bodyRegionId,
      'side': side,
      'level': level,
      'effect_on_training': effectOnTraining,
      if (painType != null && painType.trim().isNotEmpty) 'pain_type': painType.trim(),
      if (injuryId != null) 'injury_id': injuryId,
      if (checkinId != null) 'checkin_id': checkinId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  Future<String> addRestriction({required String kind, String? exerciseId, String? movement, String? injuryId, String source = 'self', String? note, String? activeFrom, String? activeTo}) {
    _oneOf('Kind', kind, const ['uncomfortable', 'avoid', 'modify']);
    _oneOf('Source', source, const ['self', 'professional']);
    if (exerciseId == null && (movement == null || movement.trim().isEmpty)) throw ArgumentError('Pick an exercise or name a movement.');
    final from = activeFrom ?? today;
    if (activeTo != null && activeTo.compareTo(from) < 0) throw ArgumentError('The end date cannot be before the start date.');
    return writer.upsert('exercise_restrictions', {
      'kind': kind,
      'source': source,
      'active_from': from,
      if (activeTo != null) 'active_to': activeTo,
      if (exerciseId != null) 'exercise_id': exerciseId,
      if (movement != null && movement.trim().isNotEmpty) 'movement': movement.trim(),
      if (injuryId != null) 'injury_id': injuryId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  /// Ends a restriction today (it stays in the record).
  Future<void> endRestriction(String id) => writer.apply([PendingChange.upsert('exercise_restrictions', {'active_to': today}, id: id)]);

  // ---- Supplements ----

  /// Adds a supplement and its first dose/schedule. The two records are queued together; the phase follows the
  /// supplement in the outbox.
  Future<String> addSupplement({required String name, String? category, String? notes, double? doseAmount, String? doseUnit, int timesPerDay = 1, List<int> daysOfWeek = const []}) async {
    if (name.trim().isEmpty) throw ArgumentError('Give the supplement a name.');
    _checkPhase(doseAmount, timesPerDay, daysOfWeek);
    final taken = await repository.supplements();
    if (taken.any((s) => s.name.trim().toLowerCase() == name.trim().toLowerCase())) throw ArgumentError('A supplement with that name already exists.');
    final supplement = PendingChange.upsert('supplements', {
      'name': name.trim(),
      if (category != null && category.trim().isNotEmpty) 'category': category.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    final phase = PendingChange.newVersion('supplement_phases', {
      'entity_id': supplement.id,
      'status': 'active',
      'times_per_day': timesPerDay,
      'days_of_week': daysOfWeek,
      if (doseAmount != null) 'dose_amount': doseAmount,
      if (doseUnit != null && doseUnit.trim().isNotEmpty) 'dose_unit': doseUnit.trim(),
    });
    await writer.apply([supplement, phase]);
    return supplement.id;
  }

  /// Changes dose, schedule or status by opening a new phase version (history is kept).
  Future<void> changeSupplementPhase(String supplementId, {String? status, double? doseAmount, String? doseUnit, int? timesPerDay, List<int>? daysOfWeek, String? reason}) async {
    _oneOf('Status', status, const ['active', 'paused', 'stopped']);
    final current = await repository.currentPhase(supplementId);
    final times = timesPerDay ?? current?.timesPerDay ?? 1;
    final days = daysOfWeek ?? current?.daysOfWeek ?? const <int>[];
    final dose = doseAmount ?? current?.doseAmount;
    _checkPhase(dose, times, days);
    await writer.apply([
      PendingChange.newVersion('supplement_phases', {
        'entity_id': supplementId,
        'status': status ?? current?.status ?? 'active',
        'times_per_day': times,
        'days_of_week': days,
        if (dose != null) 'dose_amount': dose,
        if ((doseUnit ?? current?.doseUnit) != null) 'dose_unit': doseUnit ?? current?.doseUnit,
      }, reason: reason),
    ]);
  }

  static void _checkPhase(double? dose, int times, List<int> days) {
    _positive('Dose', dose);
    if (times < 1) throw ArgumentError('Times per day must be at least 1.');
    if (days.any((d) => d < 1 || d > 7)) throw ArgumentError('Days must be 1 (Monday) to 7 (Sunday).');
  }

  Future<String> logSupplement(String supplementId, {String outcome = 'taken', double? quantity, String? unit, String? notes}) async {
    _oneOf('Outcome', outcome, const ['taken', 'missed', 'skipped']);
    if (quantity != null && quantity < 0) throw ArgumentError('Quantity cannot be negative.');
    final phase = await repository.currentPhase(supplementId);
    return writer.upsert('supplement_logs', {
      ...localStampOf(_clock()).toPayload(),
      'supplement_id': supplementId,
      if (phase != null) 'phase_id': phase.id,
      'outcome': outcome,
      if (quantity != null) 'quantity': quantity,
      if (unit != null) 'unit': unit,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  // ---- Meals ----

  Future<String> saveMeal({
    String? id,
    required String title,
    required String category,
    double? caloriesKcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fibreG,
    bool isEstimate = false,
    String? notes,
  }) {
    if (title.trim().isEmpty) throw ArgumentError('Give the meal a name.');
    _oneOf('Category', category, mealCategories);
    for (final v in [caloriesKcal, proteinG, carbsG, fatG, fibreG]) {
      if (v != null && v < 0) throw ArgumentError('Nutrition values cannot be negative.');
    }
    return writer.upsert('meals', {
      'title': title.trim(),
      'category': category,
      if (caloriesKcal != null) 'calories_kcal': caloriesKcal,
      if (proteinG != null) 'protein_g': proteinG,
      if (carbsG != null) 'carbs_g': carbsG,
      if (fatG != null) 'fat_g': fatG,
      if (fibreG != null) 'fibre_g': fibreG,
      'nutrition_is_estimate': isEstimate,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    }, id: id);
  }

  Future<String> planMeal({required String slot, required String mealId, String? localDate, double servings = 1}) {
    _oneOf('Slot', slot, mealCategories);
    if (servings <= 0) throw ArgumentError('Servings must be more than zero.');
    return writer.upsert('meal_plan_entries', {'local_date': localDate ?? today, 'slot': slot, 'meal_id': mealId, 'servings': servings, 'status': 'planned'});
  }

  /// Marks a planned meal eaten, or replaced by another meal (which must be named).
  Future<void> setMealStatus(String entryId, {required String status, String? replacedByMealId}) {
    _oneOf('Status', status, const ['planned', 'eaten', 'replaced']);
    if (status == 'replaced' && replacedByMealId == null) throw ArgumentError('Say which meal replaced it.');
    return writer.apply([
      PendingChange.upsert('meal_plan_entries', {'status': status, 'replaced_by_meal_id': status == 'replaced' ? replacedByMealId : null}, id: entryId),
    ]);
  }

  /// Logs a meal you ate without planning it: a plan entry for today already marked eaten.
  Future<String> logMealEaten({required String slot, required String mealId, double servings = 1}) {
    _oneOf('Slot', slot, mealCategories);
    if (servings <= 0) throw ArgumentError('Servings must be more than zero.');
    return writer.upsert('meal_plan_entries', {'local_date': today, 'slot': slot, 'meal_id': mealId, 'servings': servings, 'status': 'eaten'});
  }

  // ---- Targets ----

  /// Sets new personal targets as a new version (earlier targets stay in the history).
  Future<String> setTargets({double? proteinG, double? caloriesKcal, int? waterMl, int? stepTarget, String? reason}) async {
    _positive('Protein', proteinG);
    _positive('Calories', caloriesKcal);
    _positive('Water', waterMl);
    _positive('Step target', stepTarget);
    final current = await repository.currentTargets();
    // A new version replaces the old one, so values not given are carried over from it.
    final protein = proteinG ?? current?.proteinG;
    final calories = caloriesKcal ?? current?.caloriesKcal;
    final water = waterMl ?? current?.waterMl;
    final steps = stepTarget ?? current?.stepTarget;
    return writer.newVersion('personal_targets', {
      'entity_id': current?.entityId ?? newUuidV7(),
      if (protein != null) 'protein_g': protein,
      if (calories != null) 'calories_kcal': calories,
      if (water != null) 'water_ml': water,
      if (steps != null) 'step_target': steps,
    }, reason: reason);
  }
}
