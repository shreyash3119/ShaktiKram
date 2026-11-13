import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';
import '../../../core/insights/insight_providers.dart';
import '../../../core/insights/insight_repository.dart';
import '../../../core/sync/change_writer.dart';
import '../../../core/sync/sync_status.dart';
import '../../lifestyle/data/lifestyle_models.dart';
import '../../lifestyle/data/lifestyle_providers.dart';
import '../../training/data/training_providers.dart';
import 'progress_insights.dart';
import 'progress_models.dart';
import 'progress_repository.dart';
import 'progress_service.dart';

final progressRepositoryProvider = Provider<ProgressRepository>((ref) => ProgressRepository(ref.read(localStoreProvider)));

T _reload<T>(Ref ref, T Function(ProgressRepository repo) read) {
  ref.watch(dataRevisionProvider);
  return read(ref.watch(progressRepositoryProvider));
}

final progressServiceProvider = Provider<ProgressService>((ref) => ProgressService(writer: ref.read(changeWriterProvider), repository: ref.read(progressRepositoryProvider)));

// ---- Synced records (SQLite) ----

final personalRecordsProvider = FutureProvider<List<PersonalRecord>>((ref) => _reload(ref, (r) => r.personalRecords()));

final achievementsProvider = FutureProvider<List<Achievement>>((ref) => _reload(ref, (r) => r.achievements()));

final goalsProvider = FutureProvider<List<Goal>>((ref) => _reload(ref, (r) => r.goals()));

/// Every goal including archived and replaced ones, for the editor's "show archived" view.
final allGoalsProvider = FutureProvider<List<Goal>>((ref) => _reload(ref, (r) => r.goals(includeEnded: true)));

final milestonesProvider = FutureProvider.family<List<Milestone>, String>((ref, goalId) => _reload(ref, (r) => r.milestones(goalId)));

// ---- Server calculations (cached) ----

/// A cached server answer turned into typed rows, with the snapshot's age and error kept for the freshness label.
class InsightRows<T> {
  const InsightRows({required this.rows, required this.snapshot});

  final List<T> rows;
  final InsightSnapshot snapshot;
}

List<T> _rowsOf<T>(InsightSnapshot s, T Function(Map<String, dynamic>) parse) {
  final data = s.data;
  if (data is! List) return const [];
  return [for (final r in data) if (r is Map) parse(Map<String, dynamic>.from(r))];
}

InsightRows<T> _typed<T>(AsyncValue<InsightSnapshot> async, T Function(Map<String, dynamic>) parse) {
  final snap = async.valueOrNull ?? const InsightSnapshot.none();
  return InsightRows(rows: _rowsOf(snap, parse), snapshot: snap);
}

/// The briefing for [localDate]; null until the server has answered at least once.
class BriefingResult {
  const BriefingResult({this.briefing, required this.snapshot});

  final DailyBriefing? briefing;
  final InsightSnapshot snapshot;
}

final dailyBriefingProvider = Provider.family<BriefingResult, String>((ref, localDate) {
  final snap = ref.watch(insightProvider(dailyBriefingSpec(localDate))).valueOrNull ?? const InsightSnapshot.none();
  final data = snap.data;
  return BriefingResult(briefing: data is Map ? DailyBriefing.fromJson(Map<String, dynamic>.from(data)) : null, snapshot: snap);
});

final exerciseTrendsProvider = Provider<InsightRows<ExerciseTrend>>((ref) => _typed(ref.watch(insightProvider(exerciseTrendsSpec)), ExerciseTrend.fromJson));

final exerciseSessionBestProvider =
    Provider<InsightRows<ExerciseSessionBest>>((ref) => _typed(ref.watch(insightProvider(exerciseSessionBestSpec)), ExerciseSessionBest.fromJson));

final goalProgressProvider = Provider<InsightRows<GoalProgress>>((ref) => _typed(ref.watch(insightProvider(goalProgressSpec)), GoalProgress.fromJson));

final goalMilestonesProvider = Provider<InsightRows<MilestoneStatus>>((ref) => _typed(ref.watch(insightProvider(goalMilestonesSpec)), MilestoneStatus.fromJson));

final muscleExposureProvider = Provider<InsightRows<MuscleExposure>>((ref) => _typed(ref.watch(insightProvider(muscleExposureSpec)), MuscleExposure.fromJson));

final muscleRatingsProvider = Provider<InsightRows<MuscleRating>>((ref) => _typed(ref.watch(insightProvider(muscleRatingsSpec)), MuscleRating.fromJson));

final bodyCompositionProvider = Provider<InsightRows<BodyComposition>>((ref) => _typed(ref.watch(insightProvider(bodyCompositionSpec)), BodyComposition.fromJson));

final sessionSummariesProvider = Provider<InsightRows<SessionSummaryRow>>((ref) => _typed(ref.watch(insightProvider(sessionSummarySpec)), SessionSummaryRow.fromJson));

// ---- Local helpers shared by the Progress screens ----

/// Body measurements of [type] (`weight`, `waist`, ...) newest first; null means every type.
final measurementsProvider = FutureProvider.family<List<BodyMeasurement>, String?>((ref, type) {
  ref.watch(dataRevisionProvider);
  return ref.watch(lifestyleRepositoryProvider).measurements(type: type, limit: 400);
});

/// Exercise names by id, from the exercise library on the phone.
final exerciseNamesProvider = Provider<Map<String, String>>((ref) {
  return {for (final e in ref.watch(exerciseLibraryProvider).valueOrNull ?? const []) e.id: e.name};
});

/// Muscle labels by id, from the muscle reference data on the phone.
final muscleLabelsProvider = FutureProvider<Map<String, String>>((ref) async {
  ref.watch(dataRevisionProvider);
  final rows = await ref.read(localStoreProvider).list('muscles');
  return {for (final r in rows) r['id'] as String: (r['label'] as String?) ?? (r['key'] as String? ?? '')};
});

/// Achievements worth showing. A workout-count achievement found from a workout with no logged sets is hidden,
/// because an empty workout does not count.
final visibleAchievementsProvider = FutureProvider<List<Achievement>>((ref) async {
  final all = await ref.watch(achievementsProvider.future);
  final finished = await ref.watch(finishedSessionsProvider.future);
  final empty = {for (final f in finished) if (!f.counted) f.session.id};
  return [for (final a in all) if (!(a.supportingTable == 'workout_sessions' && empty.contains(a.supportingRecordId))) a];
});
