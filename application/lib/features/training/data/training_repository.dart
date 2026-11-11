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

  // ---- Templates ----

  Future<List<TemplateVersion>> currentTemplateVersions() async {
    final rows = await _store.list('template_versions');
    return [for (final r in rows) TemplateVersion.fromRecord(r)].where((v) => v.isCurrent).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<TemplateVersion?> templateVersion(String id) async {
    final r = await _store.get('template_versions', id);
    return r == null || r['deleted_at'] != null ? null : TemplateVersion.fromRecord(r);
  }

  /// The current version of a template, or null.
  Future<TemplateVersion?> currentVersionOfTemplate(String templateId) async {
    final rows = await _store.listByRef('template_versions', 'entity_id', templateId);
    final versions = [for (final r in rows) TemplateVersion.fromRecord(r)].where((v) => v.isCurrent).toList();
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
    final splitId = active.first['id'] as String;
    final versions = await _store.listByRef('split_versions', 'entity_id', splitId);
    final current = versions.where((v) => v['effective_to'] == null).toList();
    if (current.isEmpty) return null;
    final v = current.first;
    final days = await _store.listByRef('split_days', 'split_version_id', v['id'] as String);
    return ActiveSplit(
      splitId: splitId,
      versionId: v['id'] as String,
      name: (v['name'] as String?) ?? '',
      pattern: (v['pattern'] as String?) ?? 'fixed_weekly',
      cycleLengthDays: (v['cycle_length_days'] as num?)?.toInt(),
      days: [for (final d in days) SplitDay.fromRecord(d)]..sort((a, b) => a.position.compareTo(b.position)),
    );
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
