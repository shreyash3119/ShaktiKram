import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';
import '../../../core/sync/change_writer.dart';
import '../../../core/sync/sync_status.dart';
import 'training_management_service.dart';
import 'training_models.dart';
import 'training_repository.dart';
import 'workout_session_service.dart';

final trainingRepositoryProvider = Provider<TrainingRepository>((ref) => TrainingRepository(ref.read(localStoreProvider)));

final workoutSessionServiceProvider = Provider<WorkoutSessionService>((ref) {
  return WorkoutSessionService(writer: ref.read(changeWriterProvider), repository: ref.read(trainingRepositoryProvider));
});

final trainingManagementServiceProvider = Provider<TrainingManagementService>((ref) {
  return TrainingManagementService(writer: ref.read(changeWriterProvider), repository: ref.read(trainingRepositoryProvider));
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

/// The schedule entries for the seven days starting [firstLocalDate] (`YYYY-MM-DD`); a day with none is null.
final scheduleWeekProvider = FutureProvider.family<List<ScheduleEntry?>, String>((ref, firstLocalDate) async {
  ref.watch(dataRevisionProvider);
  final repo = ref.watch(trainingRepositoryProvider);
  final start = DateTime.parse(firstLocalDate);
  String two(int n) => n.toString().padLeft(2, '0');
  final out = <ScheduleEntry?>[];
  for (var i = 0; i < 7; i++) {
    final d = DateTime.utc(start.year, start.month, start.day + i);
    out.add(await repo.scheduleFor('${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}'));
  }
  return out;
});

/// Every split that is not archived, each with its newest version and days.
final splitsProvider = FutureProvider<List<ActiveSplit>>((ref) => _reload(ref, (r) => r.splits()));

final musclesProvider = FutureProvider<List<MuscleRef>>((ref) => _reload(ref, (r) => r.muscles()));

final equipmentProvider = FutureProvider<List<EquipmentRef>>((ref) => _reload(ref, (r) => r.equipment()));

final exerciseMusclesProvider =
    FutureProvider.family<List<({String muscleId, String role})>, String>((ref, exerciseId) => _reload(ref, (r) => r.exerciseMuscles(exerciseId)));

/// Finished workouts, newest first, each marked with whether it counts (it has logged working sets).
final finishedSessionsProvider = FutureProvider<List<({WorkoutSession session, bool counted})>>((ref) => _reload(ref, (r) => r.finishedSessions(limit: 60)));

/// The schedule entries from [range.from] to [range.to], by date.
final scheduleRangeProvider = FutureProvider.family<List<ScheduleEntry>, ({String from, String to})>((ref, range) => _reload(ref, (r) => r.scheduleBetween(range.from, range.to)));

/// What is planned for one day, resolved against the split day and template it points to. The template is the newest
/// version of the day's template, so a template edited after the day was scheduled is the one that starts.
class TodayPlan {
  const TodayPlan({this.entry, this.day, this.template});

  final ScheduleEntry? entry;
  final SplitDay? day;
  final TemplateVersion? template;

  bool get isRest => entry?.isRestDay == true;
  bool get hasPlan => entry != null && (isRest || day != null || template != null);

  /// What to call the planned workout.
  String? get title => isRest ? 'Rest day' : (day != null && day!.label.isNotEmpty ? day!.label : template?.name);
}

final todayPlanProvider = FutureProvider.family<TodayPlan, String>((ref, localDate) async {
  ref.watch(dataRevisionProvider);
  final repo = ref.watch(trainingRepositoryProvider);
  final entry = await repo.scheduleFor(localDate);
  if (entry == null) return const TodayPlan();
  final day = entry.splitDayId == null ? null : await repo.splitDay(entry.splitDayId!);
  TemplateVersion? template = day?.templateId == null ? null : await repo.currentVersionOfTemplate(day!.templateId!);
  template ??= entry.templateVersionId == null ? null : await repo.templateVersion(entry.templateVersionId!);
  return TodayPlan(entry: entry, day: day, template: template);
});

final exerciseLinksProvider = FutureProvider<Map<String, List<({String muscleId, String role})>>>((ref) => _reload(ref, (r) => r.exerciseMuscleLinks()));

final splitDayLabelsProvider = FutureProvider<Map<String, String>>((ref) => _reload(ref, (r) => r.splitDayLabels()));
