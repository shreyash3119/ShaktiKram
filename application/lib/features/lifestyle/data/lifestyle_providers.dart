import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';
import '../../../core/sync/change_writer.dart';
import '../../../core/sync/sync_status.dart';
import 'lifestyle_models.dart';
import 'lifestyle_repository.dart';
import 'lifestyle_service.dart';

final lifestyleRepositoryProvider = Provider<LifestyleRepository>((ref) => LifestyleRepository(ref.read(localStoreProvider)));

final lifestyleServiceProvider = Provider<LifestyleService>((ref) {
  return LifestyleService(writer: ref.read(changeWriterProvider), repository: ref.read(lifestyleRepositoryProvider));
});

/// Reads that reload whenever local data changes (a save, or rows pulled from the server).
T _reload<T>(Ref ref, T Function(LifestyleRepository repo) read) {
  ref.watch(dataRevisionProvider);
  return read(ref.watch(lifestyleRepositoryProvider));
}

final bodyRegionsProvider = FutureProvider<List<BodyRegion>>((ref) => _reload(ref, (r) => r.bodyRegions()));

final daySummaryProvider = FutureProvider.family<DaySummary, String>((ref, localDate) => _reload(ref, (r) => r.daySummary(localDate)));

final checkinProvider = FutureProvider.family<DailyCheckin?, String>((ref, localDate) => _reload(ref, (r) => r.checkinFor(localDate)));

final sleepForProvider = FutureProvider.family<List<SleepLog>, String>((ref, localDate) => _reload(ref, (r) => r.sleepFor(localDate)));

final recentSleepProvider = FutureProvider<List<SleepLog>>((ref) => _reload(ref, (r) => r.recentSleep()));

final stepsForProvider = FutureProvider.family<DailySteps?, String>((ref, localDate) => _reload(ref, (r) => r.stepsFor(localDate)));

final waterForProvider = FutureProvider.family<List<WaterLog>, String>((ref, localDate) => _reload(ref, (r) => r.waterFor(localDate)));

final recentCardioProvider = FutureProvider<List<CardioSession>>((ref) => _reload(ref, (r) => r.recentCardio()));

final injuriesProvider = FutureProvider<List<Injury>>((ref) => _reload(ref, (r) => r.injuries()));

final recentPainProvider = FutureProvider<List<PainEntry>>((ref) => _reload(ref, (r) => r.recentPain()));

final restrictionsProvider = FutureProvider<List<ExerciseRestriction>>((ref) => _reload(ref, (r) => r.restrictions()));

final supplementsProvider = FutureProvider<List<Supplement>>((ref) => _reload(ref, (r) => r.supplements()));

final supplementPhaseProvider = FutureProvider.family<SupplementPhase?, String>((ref, supplementId) => _reload(ref, (r) => r.currentPhase(supplementId)));

final supplementLogsForProvider = FutureProvider.family<List<SupplementLog>, String>((ref, localDate) => _reload(ref, (r) => r.supplementLogsFor(localDate)));

final mealsProvider = FutureProvider<List<Meal>>((ref) => _reload(ref, (r) => r.meals()));

final mealPlanForProvider = FutureProvider.family<List<MealPlanEntry>, String>((ref, localDate) => _reload(ref, (r) => r.mealPlanFor(localDate)));

final targetsProvider = FutureProvider<PersonalTargets?>((ref) => _reload(ref, (r) => r.currentTargets()));
