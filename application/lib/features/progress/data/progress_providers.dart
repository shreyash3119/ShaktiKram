import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';
import '../../../core/insights/insight_providers.dart';
import '../../../core/insights/insight_repository.dart';
import '../../../core/sync/sync_status.dart';
import 'progress_insights.dart';
import 'progress_models.dart';
import 'progress_repository.dart';

final progressRepositoryProvider = Provider<ProgressRepository>((ref) => ProgressRepository(ref.read(localStoreProvider)));

T _reload<T>(Ref ref, T Function(ProgressRepository repo) read) {
  ref.watch(dataRevisionProvider);
  return read(ref.watch(progressRepositoryProvider));
}

// ---- Synced records (SQLite) ----

final personalRecordsProvider = FutureProvider<List<PersonalRecord>>((ref) => _reload(ref, (r) => r.personalRecords()));

final achievementsProvider = FutureProvider<List<Achievement>>((ref) => _reload(ref, (r) => r.achievements()));

final goalsProvider = FutureProvider<List<Goal>>((ref) => _reload(ref, (r) => r.goals()));

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
