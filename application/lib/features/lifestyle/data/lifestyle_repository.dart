import '../../../core/db/local_store.dart';
import 'lifestyle_models.dart';

/// Reads Lifestyle data from the local database. Nothing here talks to the server.
class LifestyleRepository {
  LifestyleRepository(this._store);

  final LocalStore _store;

  Future<List<BodyRegion>> bodyRegions() async {
    final rows = await _store.list('body_regions');
    return [for (final r in rows) BodyRegion.fromRecord(r)]..sort((a, b) => a.name.compareTo(b.name));
  }

  // ---- Daily records ----

  Future<DailyCheckin?> checkinFor(String localDate) async {
    final rows = await _store.list('daily_checkins', localDate: localDate);
    return rows.isEmpty ? null : DailyCheckin.fromRecord(rows.first);
  }

  /// Sleep logs that ended on [localDate] (the night before, plus naps).
  Future<List<SleepLog>> sleepFor(String localDate) async {
    final rows = await _store.list('sleep_logs', localDate: localDate);
    return [for (final r in rows) SleepLog.fromRecord(r)];
  }

  Future<List<SleepLog>> recentSleep({int limit = 14}) async {
    final rows = await _store.list('sleep_logs', limit: limit);
    return [for (final r in rows) SleepLog.fromRecord(r)]..sort((a, b) => b.localDate.compareTo(a.localDate));
  }

  Future<DailySteps?> stepsFor(String localDate) async {
    final rows = await _store.list('daily_steps', localDate: localDate);
    return rows.isEmpty ? null : DailySteps.fromRecord(rows.first);
  }

  Future<List<DailySteps>> recentSteps({int limit = 14}) async {
    final rows = await _store.list('daily_steps', limit: limit);
    return [for (final r in rows) DailySteps.fromRecord(r)]..sort((a, b) => b.localDate.compareTo(a.localDate));
  }

  Future<List<WaterLog>> waterFor(String localDate) async {
    final rows = await _store.list('water_logs', localDate: localDate);
    return [for (final r in rows) WaterLog.fromRecord(r)]..sort((a, b) => (a.occurredAt?.millisecondsSinceEpoch ?? 0).compareTo(b.occurredAt?.millisecondsSinceEpoch ?? 0));
  }

  Future<List<CardioSession>> cardioFor(String localDate) async {
    final rows = await _store.list('cardio_sessions', localDate: localDate);
    return [for (final r in rows) CardioSession.fromRecord(r)];
  }

  Future<List<CardioSession>> recentCardio({int limit = 20}) async {
    final rows = await _store.list('cardio_sessions', limit: limit);
    return [for (final r in rows) CardioSession.fromRecord(r)]..sort((a, b) => b.localDate.compareTo(a.localDate));
  }

  Future<List<BodyMeasurement>> measurements({String? type, int limit = 30}) async {
    final rows = await _store.list('body_measurements', limit: type == null ? limit : null);
    final all = [for (final r in rows) BodyMeasurement.fromRecord(r)].where((m) => type == null || m.type == type).toList()
      ..sort((a, b) => (b.occurredAt?.millisecondsSinceEpoch ?? 0).compareTo(a.occurredAt?.millisecondsSinceEpoch ?? 0));
    return all.length > limit ? all.sublist(0, limit) : all;
  }

  // ---- Injuries, pain, restrictions ----

  /// Injuries that are not resolved, newest first; pass [includeResolved] for the whole record.
  Future<List<Injury>> injuries({bool includeResolved = false}) async {
    final rows = await _store.list('injuries');
    return [for (final r in rows) Injury.fromRecord(r)].where((i) => includeResolved || !i.isResolved).toList()
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
  }

  Future<Injury?> injury(String id) async {
    final r = await _store.get('injuries', id);
    return r == null || r['deleted_at'] != null ? null : Injury.fromRecord(r);
  }

  Future<List<PainEntry>> recentPain({int limit = 20}) async {
    final rows = await _store.list('pain_entries', limit: limit);
    return [for (final r in rows) PainEntry.fromRecord(r)]..sort((a, b) => (b.occurredAt?.millisecondsSinceEpoch ?? 0).compareTo(a.occurredAt?.millisecondsSinceEpoch ?? 0));
  }

  /// Restrictions in force on [localDate] (default: all not yet ended).
  Future<List<ExerciseRestriction>> restrictions({String? onDate}) async {
    final rows = await _store.list('exercise_restrictions');
    return [for (final r in rows) ExerciseRestriction.fromRecord(r)]
        .where((r) => onDate == null ? r.activeTo == null : (r.activeFrom.compareTo(onDate) <= 0 && (r.activeTo == null || r.activeTo!.compareTo(onDate) >= 0)))
        .toList();
  }

  // ---- Supplements ----

  Future<List<Supplement>> supplements() async {
    final rows = await _store.list('supplements');
    return [for (final r in rows) Supplement.fromRecord(r)]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// The latest phase (dose and schedule) of a supplement, or null. The highest version is the current one, including a
  /// change still waiting to sync.
  Future<SupplementPhase?> currentPhase(String supplementId) async {
    final rows = await _store.listByRef('supplement_phases', 'entity_id', supplementId);
    final all = [for (final r in rows) SupplementPhase.fromRecord(r)]..sort((a, b) => b.version.compareTo(a.version));
    return all.isEmpty ? null : all.first;
  }

  Future<List<SupplementLog>> supplementLogsFor(String localDate) async {
    final rows = await _store.list('supplement_logs', localDate: localDate);
    return [for (final r in rows) SupplementLog.fromRecord(r)];
  }

  // ---- Meals and targets ----

  Future<List<Meal>> meals() async {
    final rows = await _store.list('meals');
    return [for (final r in rows) Meal.fromRecord(r)]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  }

  Future<Meal?> meal(String id) async {
    final r = await _store.get('meals', id);
    return r == null || r['deleted_at'] != null ? null : Meal.fromRecord(r);
  }

  Future<List<MealPlanEntry>> mealPlanFor(String localDate) async {
    final rows = await _store.list('meal_plan_entries', localDate: localDate);
    const order = ['breakfast', 'lunch', 'dinner', 'snack'];
    return [for (final r in rows) MealPlanEntry.fromRecord(r)]..sort((a, b) => order.indexOf(a.slot).compareTo(order.indexOf(b.slot)));
  }

  Future<PersonalTargets?> currentTargets() async {
    final rows = await _store.list('personal_targets');
    final all = [for (final r in rows) PersonalTargets.fromRecord(r)]..sort((a, b) => b.version.compareTo(a.version));
    return all.isEmpty ? null : all.first;
  }

  // ---- A day at a glance ----

  Future<DaySummary> daySummary(String localDate) async {
    final sleep = await sleepFor(localDate);
    final water = await waterFor(localDate);
    final logs = await supplementLogsFor(localDate);
    final plan = await mealPlanFor(localDate);
    final cardio = await cardioFor(localDate);
    return DaySummary(
      localDate: localDate,
      checkin: await checkinFor(localDate),
      sleepSeconds: sleep.where((s) => !s.isNap).fold(0, (a, s) => a + s.durationSeconds),
      steps: await stepsFor(localDate),
      waterMl: water.fold(0, (a, w) => a + w.amountMl),
      supplementsTaken: logs.where((l) => l.outcome == 'taken').length,
      mealsEaten: plan.where((e) => e.status == 'eaten' || e.status == 'replaced').length,
      mealsPlanned: plan.length,
      cardioSeconds: cardio.fold(0, (a, c) => a + c.durationSeconds),
    );
  }
}
