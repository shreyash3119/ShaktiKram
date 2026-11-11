import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';
import '../../../core/sync/change_writer.dart';
import '../../../core/sync/sync_status.dart';
import 'training_models.dart';
import 'training_repository.dart';
import 'workout_session_service.dart';

final trainingRepositoryProvider = Provider<TrainingRepository>((ref) => TrainingRepository(ref.read(localStoreProvider)));

final workoutSessionServiceProvider = Provider<WorkoutSessionService>((ref) {
  return WorkoutSessionService(writer: ref.read(changeWriterProvider), repository: ref.read(trainingRepositoryProvider));
});

/// Reads that reload whenever local data changes (a save, or rows pulled from the server).
T _reload<T>(Ref ref, T Function(TrainingRepository repo) read) {
  ref.watch(dataRevisionProvider);
  return read(ref.watch(trainingRepositoryProvider));
}

final exerciseLibraryProvider = FutureProvider<List<Exercise>>((ref) => _reload(ref, (r) => r.exercises()));

final currentTemplatesProvider = FutureProvider<List<TemplateVersion>>((ref) => _reload(ref, (r) => r.currentTemplateVersions()));

final activeSplitProvider = FutureProvider<ActiveSplit?>((ref) => _reload(ref, (r) => r.activeSplit()));

final activeSessionProvider = FutureProvider<WorkoutSession?>((ref) => _reload(ref, (r) => r.activeSession()));

final recentSessionsProvider = FutureProvider<List<WorkoutSession>>((ref) => _reload(ref, (r) => r.sessions(limit: 30)));

final sessionDetailProvider =
    FutureProvider.family<SessionDetail?, String>((ref, sessionId) => _reload(ref, (r) => r.sessionDetail(sessionId)));

final previousPerformanceProvider = FutureProvider.family<PreviousPerformance?, ({String exerciseId, String? beforeSessionId})>(
  (ref, key) => _reload(ref, (r) => r.previousPerformance(key.exerciseId, beforeSessionId: key.beforeSessionId)),
);

final templateExercisesProvider =
    FutureProvider.family<List<TemplateExercise>, String>((ref, templateVersionId) => _reload(ref, (r) => r.templateExercises(templateVersionId)));
