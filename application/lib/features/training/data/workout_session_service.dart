import '../../../core/sync/change_writer.dart';
import '../../../core/time/local_stamp.dart';
import 'training_repository.dart';

/// A workout is already running; finish or discard it first.
class SessionAlreadyActive implements Exception {
  const SessionAlreadyActive(this.sessionId);

  final String sessionId;

  @override
  String toString() => 'A workout is already in progress.';
}

/// Everything a workout needs to write: start, add and skip exercises, log, correct and remove sets, complete or
/// discard. Every call is one atomic local step queued through the outbox, so it works offline and survives a restart.
/// Values are checked here against the same limits as the database, so the server never has to refuse a normal entry.
class WorkoutSessionService {
  WorkoutSessionService({required this.writer, required this.repository, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ChangeWriter writer;
  final TrainingRepository repository;
  final DateTime Function() _clock;

  static const _session = 'workout_sessions';
  static const _exercise = 'session_exercises';
  static const _set = 'sets';

  /// Starts a workout. With [templateVersionId] its exercises are added in the template's order. Returns the session id.
  /// Throws [SessionAlreadyActive] when another workout is in progress.
  Future<String> startSession({
    String? name,
    String? scheduleEntryId,
    String? splitVersionId,
    String? splitDayId,
    String? templateVersionId,
  }) async {
    final active = await repository.activeSession();
    if (active != null) throw SessionAlreadyActive(active.id);

    final stamp = localStampOf(_clock());
    final session = PendingChange.upsert(_session, {
      ...stamp.toPayload(),
      'status': 'in_progress',
      'paused_seconds': 0,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (scheduleEntryId != null) 'schedule_entry_id': scheduleEntryId,
      if (splitVersionId != null) 'split_version_id': splitVersionId,
      if (splitDayId != null) 'split_day_id': splitDayId,
      if (templateVersionId != null) 'template_version_id': templateVersionId,
    });
    final changes = <PendingChange>[session];
    if (templateVersionId != null) {
      for (final te in await repository.templateExercises(templateVersionId)) {
        changes.add(PendingChange.upsert(_exercise, {
          'session_id': session.id,
          'exercise_id': te.exerciseId,
          'position': te.position,
          'status': 'done',
          'template_exercise_id': te.id,
        }));
      }
    }
    await writer.apply(changes);
    return session.id;
  }

  /// Adds an exercise that was not in the plan, at the end. Returns the session exercise id.
  Future<String> addExercise(String sessionId, String exerciseId) async {
    final existing = await repository.sessionExercises(sessionId);
    final next = existing.isEmpty ? 1 : existing.map((e) => e.position).reduce((a, b) => a > b ? a : b) + 1;
    final change = PendingChange.upsert(_exercise, {
      'session_id': sessionId,
      'exercise_id': exerciseId,
      'position': next,
      'status': 'added',
    });
    await writer.apply([change]);
    return change.id;
  }

  /// Marks an exercise as skipped, with the reason.
  Future<void> skipExercise(String sessionExerciseId, {String? reason}) => writer.apply([
        PendingChange.upsert(_exercise, {
          'status': 'skipped',
          'skip_reason': (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
        }, id: sessionExerciseId),
      ]);

  /// Undoes a skip. An exercise that came from the plan goes back to `done`, an added one to `added`.
  Future<void> restoreExercise(String sessionExerciseId) async {
    final record = await repository.sessionExerciseById(sessionExerciseId);
    await writer.apply([
      PendingChange.upsert(_exercise, {
        'status': record?.templateExerciseId == null ? 'added' : 'done',
        'skip_reason': null,
      }, id: sessionExerciseId),
    ]);
  }

  /// Removes an exercise and every set logged for it.
  Future<void> removeExercise(String sessionExerciseId) async {
    final sets = await repository.sets(sessionExerciseId);
    await writer.apply([
      for (final s in sets) PendingChange.delete(_set, s.id),
      PendingChange.delete(_exercise, sessionExerciseId),
    ]);
  }

  /// Logs a set. The set number is the next free one for its type. Returns the set id.
  Future<String> logSet(
    String sessionExerciseId, {
    double? weightKg,
    int? reps,
    String setType = 'working',
    bool completed = true,
    int? rir,
    double? rpe,
    int? restSeconds,
    String? notes,
  }) async {
    _checkSetValues(setType: setType, weightKg: weightKg, reps: reps, rir: rir, rpe: rpe, restSeconds: restSeconds);
    final existing = await repository.sets(sessionExerciseId);
    final numbers = [for (final s in existing) if (s.setType == setType) s.setNumber];
    final next = numbers.isEmpty ? 1 : numbers.reduce((a, b) => a > b ? a : b) + 1;
    final change = PendingChange.upsert(_set, {
      ...localStampOf(_clock()).toPayload(),
      'session_exercise_id': sessionExerciseId,
      'set_number': next,
      'set_type': setType,
      'completed': completed,
      if (weightKg != null) 'weight_kg': weightKg,
      if (reps != null) 'reps': reps,
      if (rir != null) 'rir': rir,
      if (rpe != null) 'rpe': rpe,
      if (restSeconds != null) 'rest_s': restSeconds,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    await writer.apply([change]);
    return change.id;
  }

  /// Corrects a logged set. Only the values given are changed.
  Future<void> editSet(
    String setId, {
    double? weightKg,
    int? reps,
    bool? completed,
    int? rir,
    double? rpe,
    int? restSeconds,
    String? notes,
  }) {
    _checkSetValues(weightKg: weightKg, reps: reps, rir: rir, rpe: rpe, restSeconds: restSeconds);
    final changes = <String, dynamic>{
      if (weightKg != null) 'weight_kg': weightKg,
      if (reps != null) 'reps': reps,
      if (completed != null) 'completed': completed,
      if (rir != null) 'rir': rir,
      if (rpe != null) 'rpe': rpe,
      if (restSeconds != null) 'rest_s': restSeconds,
      if (notes != null) 'notes': notes.trim().isEmpty ? null : notes.trim(),
    };
    if (changes.isEmpty) return Future.value();
    return writer.apply([PendingChange.upsert(_set, changes, id: setId)]);
  }

  Future<void> deleteSet(String setId) => writer.apply([PendingChange.delete(_set, setId)]);

  /// Pauses or resumes. When resuming, [addPausedSeconds] is the time spent paused, added to the session's total.
  Future<void> setPaused(String sessionId, {required bool paused, int addPausedSeconds = 0}) async {
    final session = await repository.session(sessionId);
    if (session == null) return;
    await writer.apply([
      PendingChange.upsert(_session, {
        'status': paused ? 'paused' : 'in_progress',
        if (addPausedSeconds > 0) 'paused_seconds': session.pausedSeconds + addPausedSeconds,
      }, id: sessionId),
    ]);
  }

  /// Saves notes written during the workout.
  Future<void> setNotes(String sessionId, String notes) => writer.apply([
        PendingChange.upsert(_session, {'notes': notes.trim().isEmpty ? null : notes.trim()}, id: sessionId),
      ]);

  /// Finishes the workout. Exercises with no sets logged are marked skipped (reason "Not done") unless
  /// [markUntouchedAsSkipped] is false. A linked schedule entry is marked completed.
  Future<void> completeSession(String sessionId, {String? postNotes, bool markUntouchedAsSkipped = true}) async {
    final session = await repository.session(sessionId);
    if (session == null) throw StateError('That workout is not on this phone.');
    var end = _clock().toUtc();
    if (end.isBefore(session.startedAt)) end = session.startedAt;

    final changes = <PendingChange>[];
    if (markUntouchedAsSkipped) {
      for (final e in await repository.sessionExercises(sessionId)) {
        if (e.isSkipped) continue;
        if ((await repository.sets(e.id)).isEmpty) {
          changes.add(PendingChange.upsert(_exercise, {'status': 'skipped', 'skip_reason': 'Not done'}, id: e.id));
        }
      }
    }
    changes.add(PendingChange.upsert(_session, {
      'status': 'completed',
      'ended_at': end.toIso8601String(),
      if (postNotes != null && postNotes.trim().isNotEmpty) 'post_notes': postNotes.trim(),
    }, id: sessionId));
    if (session.scheduleEntryId != null) {
      changes.add(PendingChange.upsert('schedule_entries', {'status': 'completed', 'session_id': sessionId}, id: session.scheduleEntryId));
    }
    await writer.apply(changes);
  }

  /// Throws the workout away: its sets, exercises and the session itself are soft-deleted.
  Future<void> discardSession(String sessionId) async {
    final changes = <PendingChange>[];
    for (final e in await repository.sessionExercises(sessionId)) {
      for (final s in await repository.sets(e.id)) {
        changes.add(PendingChange.delete(_set, s.id));
      }
      changes.add(PendingChange.delete(_exercise, e.id));
    }
    changes.add(PendingChange.delete(_session, sessionId));
    await writer.apply(changes);
  }

  void _checkSetValues({String setType = 'working', double? weightKg, int? reps, int? rir, double? rpe, int? restSeconds}) {
    if (setType != 'working' && setType != 'warmup') throw ArgumentError('A set is either a warm-up or a working set.');
    if (weightKg != null && (weightKg < 0 || weightKg > 9999.99)) throw ArgumentError('Weight must be between 0 and 9999 kg.');
    if (reps != null && (reps < 0 || reps > 32767)) throw ArgumentError('Reps cannot be negative.');
    if (rir != null && (rir < 0 || rir > 10)) throw ArgumentError('Reps in reserve must be between 0 and 10.');
    if (rpe != null && (rpe < 1 || rpe > 10 || (rpe * 2) != (rpe * 2).roundToDouble())) {
      throw ArgumentError('Effort (RPE) must be between 1 and 10 in steps of 0.5.');
    }
    if (restSeconds != null && restSeconds < 0) throw ArgumentError('Rest cannot be negative.');
  }
}
