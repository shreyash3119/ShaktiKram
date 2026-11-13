import '../../../core/db/local_store.dart';
import 'training_models.dart';

/// Reads training data from the local database. Nothing here talks to the server.
class TrainingRepository {
  TrainingRepository(this._store);

  final LocalStore _store;

  // ---- Exercises ----

  /// The exercise library, A to Z.
  Future<List<Exercise>> exercises() async {
    final rows = await _store.list('exercises');
    return [for (final r in rows) Exercise.fromRecord(r)]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<Exercise?> exercise(String id) async {
    final r = await _store.get('exercises', id);
    return r == null || r['deleted_at'] != null ? null : Exercise.fromRecord(r);
  }

  /// Muscle ids an exercise trains, primary first.
  Future<List<({String muscleId, String role})>> exerciseMuscles(String exerciseId) async {
    final rows = await _store.listByRef('exercise_muscles', 'exercise_id', exerciseId);
    final out = [for (final r in rows) (muscleId: r['muscle_id'] as String, role: (r['role'] as String?) ?? 'primary')];
    out.sort((a, b) => (a.role == 'primary' ? 0 : 1).compareTo(b.role == 'primary' ? 0 : 1));
    return out;
  }

  Future<List<MuscleRef>> muscles() async {
    final rows = await _store.list('muscles');
    return [for (final r in rows) MuscleRef.fromRecord(r)]..sort((a, b) {
        final g = a.groupKey.compareTo(b.groupKey);
        return g != 0 ? g : a.label.compareTo(b.label);
      });
  }

  Future<List<EquipmentRef>> equipment() async {
    final rows = await _store.list('equipment');
    return [for (final r in rows) EquipmentRef.fromRecord(r)]..sort((a, b) => a.label.compareTo(b.label));
  }

  /// The raw exercise-muscle rows of an exercise (id, muscle_id, role), for editing.
  Future<List<Map<String, dynamic>>> exerciseMuscleRows(String exerciseId) => _store.listByRef('exercise_muscles', 'exercise_id', exerciseId);

  /// For every exercise, the muscles it trains (used to filter the library by muscle group).
  Future<Map<String, List<({String muscleId, String role})>>> exerciseMuscleLinks() async {
    final out = <String, List<({String muscleId, String role})>>{};
    for (final r in await _store.list('exercise_muscles')) {
      out.putIfAbsent(r['exercise_id'] as String, () => []).add((muscleId: r['muscle_id'] as String, role: (r['role'] as String?) ?? 'primary'));
    }
    return out;
  }

  /// Names of every split day ever saved, by id. Old schedule entries point at days of earlier split versions.
  Future<Map<String, String>> splitDayLabels() async {
    final rows = await _store.list('split_days');
    return {for (final r in rows) r['id'] as String: ((r['is_rest'] == true) ? 'Rest' : ((r['label'] as String?) ?? 'Workout'))};
  }

  // ---- Templates ----

  /// The newest version of every template. The highest version number counts as current, so a version saved on this
  /// phone shows at once, before the server has closed the earlier one.
    Future<List<TemplateVersion>> currentTemplateVersions() async {
    final rows = await _store.list('template_versions');
    final latest = <String, TemplateVersion>{};

    for (final r in rows) {
      if (r['deleted_at'] != null) continue;

      final v = TemplateVersion.fromRecord(r);
      final template = await _store.get('workout_templates', v.templateId);

      // A deleted template must not appear in the current template list.
      if (template == null || template['deleted_at'] != null) continue;

      final seen = latest[v.templateId];
      if (seen == null || v.version > seen.version) {
        latest[v.templateId] = v;
      }
    }

    return latest.values.toList()
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
  }

  Future<TemplateVersion?> templateVersion(String id) async {
    final r = await _store.get('template_versions', id);
    return r == null || r['deleted_at'] != null ? null : TemplateVersion.fromRecord(r);
  }

  /// The current version of a template, or null.
  Future<TemplateVersion?> currentVersionOfTemplate(String templateId) async {
    final rows = await _store.listByRef('template_versions', 'entity_id', templateId);
    final versions = [for (final r in rows) TemplateVersion.fromRecord(r)]..sort((a, b) => b.version.compareTo(a.version));
    return versions.isEmpty ? null : versions.first;
  }

  Future<List<TemplateExercise>> templateExercises(String templateVersionId) async {
    final rows = await _store.listByRef('template_exercises', 'template_version_id', templateVersionId);
    return [for (final r in rows) TemplateExercise.fromRecord(r)]..sort((a, b) => a.position.compareTo(b.position));
  }

  // ---- Splits and schedule ----

  /// The active split with its current version and days (in day order), or null when none is active.
  Future<ActiveSplit?> activeSplit() async {
    final splits = await _store.list('splits');
    final active = splits.where((s) => s['status'] == 'active').toList();
    if (active.isEmpty) return null;
    return _splitWithDays(active.first['id'] as String, status: 'active');
  }

  /// Every split that is not archived or deleted, each with its newest version and days. Active first, then by name.
  Future<List<ActiveSplit>> splits({bool includeArchived = false}) async {
    final out = <ActiveSplit>[];
    for (final s in await _store.list('splits')) {
      final status = (s['status'] as String?) ?? 'draft';
      if (!includeArchived && status == 'archived') continue;
      final split = await _splitWithDays(s['id'] as String, status: status);
      if (split != null) out.add(split);
    }
    out.sort((a, b) {
      final byActive = (a.status == 'active' ? 0 : 1).compareTo(b.status == 'active' ? 0 : 1);
      return byActive != 0 ? byActive : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  Future<ActiveSplit?> _splitWithDays(String splitId, {required String status}) async {
    final versions = await _store.listByRef('split_versions', 'entity_id', splitId);
    if (versions.isEmpty) return null;
    versions.sort((a, b) => ((b['version'] as num?) ?? 0).compareTo((a['version'] as num?) ?? 0));
    final v = versions.first;
    final days = await _store.listByRef('split_days', 'split_version_id', v['id'] as String);
    return ActiveSplit(
      splitId: splitId,
      versionId: v['id'] as String,
      name: (v['name'] as String?) ?? '',
      pattern: (v['pattern'] as String?) ?? 'fixed_weekly',
      cycleLengthDays: (v['cycle_length_days'] as num?)?.toInt(),
      status: status,
      notes: v['notes'] as String?,
      days: [for (final d in days) SplitDay.fromRecord(d)]..sort((a, b) => a.position.compareTo(b.position)),
    );
  }

  /// Schedule entries from [fromDate] to [toDate] inclusive (`YYYY-MM-DD`), by date.
  Future<List<ScheduleEntry>> scheduleBetween(String fromDate, String toDate) async {
    final rows = await _store.list('schedule_entries');
    return [for (final r in rows) ScheduleEntry.fromRecord(r)].where((e) => e.localDate.compareTo(fromDate) >= 0 && e.localDate.compareTo(toDate) <= 0).toList()
      ..sort((a, b) => a.localDate.compareTo(b.localDate));
  }

  Future<SplitDay?> splitDay(String id) async {
    final r = await _store.get('split_days', id);
    return r == null || r['deleted_at'] != null ? null : SplitDay.fromRecord(r);
  }

  /// The schedule entry for a calendar day (`YYYY-MM-DD`), or null.
  Future<ScheduleEntry?> scheduleFor(String localDate) async {
    final rows = await _store.list('schedule_entries', localDate: localDate);
    return rows.isEmpty ? null : ScheduleEntry.fromRecord(rows.first);
  }

  Future<ScheduleEntry?> scheduleEntry(String id) async {
    final r = await _store.get('schedule_entries', id);
    return r == null || r['deleted_at'] != null ? null : ScheduleEntry.fromRecord(r);
  }

  // ---- Sessions ----

  /// Sessions, newest first. Abandoned ones are left out unless asked for.
  Future<List<WorkoutSession>> sessions({int? limit, bool includeAbandoned = false}) async {
    final rows = await _store.list('workout_sessions', limit: includeAbandoned ? limit : null);
    final all = [for (final r in rows) WorkoutSession.fromRecord(r)].where((s) => includeAbandoned || s.status != 'abandoned').toList();
    return limit == null || all.length <= limit ? all : all.sublist(0, limit);
  }

  Future<WorkoutSession?> session(String id) async {
    final r = await _store.get('workout_sessions', id);
    return r == null || r['deleted_at'] != null ? null : WorkoutSession.fromRecord(r);
  }

  /// The workout in progress (or paused), if any. When several exist, the newest.
  Future<WorkoutSession?> activeSession() async {
    for (final s in await sessions()) {
      if (s.isActive) return s;
    }
    return null;
  }

  Future<List<SessionExercise>> sessionExercises(String sessionId) async {
    final rows = await _store.listByRef('session_exercises', 'session_id', sessionId);
    return [for (final r in rows) SessionExercise.fromRecord(r)]..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<SessionExercise?> sessionExerciseById(String id) async {
    final r = await _store.get('session_exercises', id);
    return r == null || r['deleted_at'] != null ? null : SessionExercise.fromRecord(r);
  }

  /// Sets of one session exercise: warm-ups first, then working sets, each in set order.
  Future<List<LoggedSet>> sets(String sessionExerciseId) async {
    final rows = await _store.listByRef('sets', 'session_exercise_id', sessionExerciseId);
    return [for (final r in rows) LoggedSet.fromRecord(r)]
      ..sort((a, b) {
        final byType = (a.isWorking ? 1 : 0).compareTo(b.isWorking ? 1 : 0);
        return byType != 0 ? byType : a.setNumber.compareTo(b.setNumber);
      });
  }

  /// Whether a session has at least one completed working set. A workout with none does not count as a workout.
  Future<bool> hasLoggedSets(String sessionId) async {
    for (final e in await sessionExercises(sessionId)) {
      if (e.isSkipped) continue;
      for (final s in await sets(e.id)) {
        if (s.isWorking && s.completed) return true;
      }
    }
    return false;
  }

  /// Finished workouts, newest first, each marked with whether it counts (it has logged working sets).
  Future<List<({WorkoutSession session, bool counted})>> finishedSessions({int? limit}) async {
    final out = <({WorkoutSession session, bool counted})>[];
    for (final s in await sessions()) {
      if (s.status != 'completed') continue;
      out.add((session: s, counted: await hasLoggedSets(s.id)));
      if (limit != null && out.length >= limit) break;
    }
    return out;
  }

  Future<SessionSummary> summary(String sessionId) async {
    final session = await this.session(sessionId);
    final exercises = await sessionExercises(sessionId);
    var working = 0;
    var reps = 0;
    var volume = 0.0;
    for (final e in exercises.where((e) => !e.isSkipped)) {
      for (final s in await sets(e.id)) {
        if (!s.isWorking || !s.completed) continue;
        working++;
        reps += s.reps ?? 0;
        volume += (s.weightKg ?? 0) * (s.reps ?? 0);
      }
    }
    int? duration;
    final ended = session?.endedAt;
    if (session != null && ended != null) {
      final raw = ended.difference(session.startedAt).inSeconds - session.pausedSeconds;
      duration = raw < 0 ? 0 : raw;
    }
    return SessionSummary(
      durationSeconds: duration,
      exercisesDone: exercises.where((e) => e.status == 'done' || e.status == 'added').length,
      exercisesSkipped: exercises.where((e) => e.isSkipped).length,
      workingSets: working,
      totalReps: reps,
      volumeKg: volume,
    );
  }

  /// The sets from the most recent finished session (before [beforeSessionId]'s start, when given) that trained
  /// [exerciseId], or null if it was never trained.
  Future<PreviousPerformance?> previousPerformance(String exerciseId, {String? beforeSessionId}) async {
    final before = beforeSessionId == null ? null : await session(beforeSessionId);
    WorkoutSession? bestSession;
    SessionExercise? bestExercise;
    final links = await _store.listByRef('session_exercises', 'exercise_id', exerciseId);
    for (final link in links) {
      final se = SessionExercise.fromRecord(link);
      if (se.isSkipped || se.sessionId == beforeSessionId) continue;
      final s = await session(se.sessionId);
      if (s == null || s.status != 'completed') continue;
      if (before != null && !s.startedAt.isBefore(before.startedAt)) continue;
      if (bestSession == null || s.startedAt.isAfter(bestSession.startedAt)) {
        bestSession = s;
        bestExercise = se;
      }
    }
    if (bestSession == null || bestExercise == null) return null;
    return PreviousPerformance(sessionId: bestSession.id, localDate: bestSession.localDate, sets: await sets(bestExercise.id));
  }

  /// A session with its exercises, their sets and its totals, in one read (for the history and workout screens).
  Future<SessionDetail?> sessionDetail(String sessionId) async {
    final s = await session(sessionId);
    if (s == null) return null;
    final exercises = await sessionExercises(sessionId);
    return SessionDetail(
      session: s,
      exercises: [for (final e in exercises) SessionExerciseDetail(exercise: e, sets: await sets(e.id))],
      summary: await summary(sessionId),
    );
  }
}

class SessionExerciseDetail {
  const SessionExerciseDetail({required this.exercise, required this.sets});

  final SessionExercise exercise;
  final List<LoggedSet> sets;
}

class SessionDetail {
  const SessionDetail({required this.session, required this.exercises, required this.summary});

  final WorkoutSession session;
  final List<SessionExerciseDetail> exercises;
  final SessionSummary summary;
}
