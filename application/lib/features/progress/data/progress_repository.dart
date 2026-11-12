import '../../../core/db/local_store.dart';
import 'progress_models.dart';

/// Reads the synced Progress records from the local database. The server-calculated parts (trends, goal progress,
/// briefing) are not here: they come through the insight cache (`progress_insights.dart`).
class ProgressRepository {
  ProgressRepository(this._store);

  final LocalStore _store;

  /// Newest first. [exerciseId] limits to one exercise.
  Future<List<PersonalRecord>> personalRecords({String? exerciseId, int? limit}) async {
    final rows = await _store.list('personal_records');
    final all = [for (final r in rows) PersonalRecord.fromRecord(r)].where((p) => exerciseId == null || p.exerciseId == exerciseId).toList()
      ..sort((a, b) => b.achievedOn.compareTo(a.achievedOn));
    return limit != null && all.length > limit ? all.sublist(0, limit) : all;
  }

  Future<List<Achievement>> achievements() async {
    final rows = await _store.list('achievements');
    return [for (final r in rows) Achievement.fromRecord(r)]..sort((a, b) => b.achievedOn.compareTo(a.achievedOn));
  }

  /// Goals that are not abandoned or replaced, active ones first.
  Future<List<Goal>> goals({bool includeEnded = false}) async {
    final rows = await _store.list('goals');
    const order = {'active': 0, 'paused': 1, 'completed': 2, 'abandoned': 3, 'replaced': 4};
    return [for (final r in rows) Goal.fromRecord(r)].where((g) => includeEnded || (g.status != 'abandoned' && g.status != 'replaced')).toList()
      ..sort((a, b) {
        final c = (order[a.status] ?? 9).compareTo(order[b.status] ?? 9);
        return c != 0 ? c : b.startDate.compareTo(a.startDate);
      });
  }

  Future<List<Milestone>> milestones(String goalId) async {
    final rows = await _store.listByRef('milestones', 'goal_id', goalId);
    return [for (final r in rows) Milestone.fromRecord(r)]..sort((a, b) => a.targetValue.compareTo(b.targetValue));
  }
}
