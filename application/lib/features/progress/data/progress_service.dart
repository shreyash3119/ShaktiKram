import '../../../core/sync/change_writer.dart';
import '../../../core/time/local_stamp.dart';
import '../../training/data/training_management_service.dart' show ManagementError;
import 'progress_repository.dart';

/// Goal types the database accepts.
const goalTypes = ['cutting', 'bulking', 'maintenance', 'strength', 'muscle_development', 'body_composition', 'exercise_performance', 'consistency'];

/// Goal statuses the database accepts.
const goalStatuses = ['active', 'paused', 'completed', 'abandoned', 'replaced'];

/// What the server can measure for a goal by itself (`goals.target_metric`). Anything else is tracked by manual entries.
const measuredMetrics = {
  'body_weight_kg': ('Body weight', 'kg'),
  'body_fat_pct': ('Body fat', '%'),
  'waist_cm': ('Waist', 'cm'),
  'chest_cm': ('Chest', 'cm'),
  'arm_cm': ('Arm', 'cm'),
  'thigh_cm': ('Thigh', 'cm'),
  'consistency_pct': ('Weekly consistency', '%'),
};

/// Writes goals, their milestones and manual progress, and muscle self-assessments. Calculations (progress, status,
/// priorities) stay on the server; this only records what the person entered.
class ProgressService {
  ProgressService({required this.writer, required this.repository, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ChangeWriter writer;
  final ProgressRepository repository;
  final DateTime Function() _clock;

  // ---- Goals ----

  Future<String> createGoal({
    required String type,
    required String title,
    String? description,
    String? targetMetric,
    double? targetValue,
    String? targetUnit,
    String? startDate,
    String? targetDate,
  }) async {
    final fields = _checkGoal(type: type, title: title, targetValue: targetValue, startDate: startDate ?? formatDay(_clock()), targetDate: targetDate);
    return writer.upsert('goals', {
      'type': type,
      'title': fields.title,
      'status': 'active',
      'start_date': startDate ?? formatDay(_clock()),
      if (_has(description)) 'description': description!.trim(),
      if (_has(targetMetric)) 'target_metric': targetMetric!.trim(),
      if (targetValue != null) 'target_value': targetValue,
      if (_has(targetUnit)) 'target_unit': targetUnit!.trim(),
      if (_has(targetDate)) 'target_date': targetDate,
    });
  }

  /// Changes a goal's details. Its status is changed with [setGoalStatus].
  Future<void> updateGoal(
    String goalId, {
    required String type,
    required String title,
    String? description,
    String? targetMetric,
    double? targetValue,
    String? targetUnit,
    required String startDate,
    String? targetDate,
  }) async {
    final fields = _checkGoal(type: type, title: title, targetValue: targetValue, startDate: startDate, targetDate: targetDate);
    await writer.upsert('goals', {
      'type': type,
      'title': fields.title,
      'start_date': startDate,
      'description': _has(description) ? description!.trim() : null,
      'target_metric': _has(targetMetric) ? targetMetric!.trim() : null,
      'target_value': targetValue,
      'target_unit': _has(targetUnit) ? targetUnit!.trim() : null,
      'target_date': _has(targetDate) ? targetDate : null,
    }, id: goalId);
  }

  /// Pauses, resumes, completes or archives (`abandoned`) a goal. Nothing is deleted.
  Future<void> setGoalStatus(String goalId, String status, {String? reason}) async {
    if (!goalStatuses.contains(status)) throw const ManagementError('That status is not valid for a goal.');
    await writer.upsert('goals', {'status': status}, id: goalId, reason: _has(reason) ? reason!.trim() : null);
  }

  _GoalFields _checkGoal({required String type, required String title, double? targetValue, required String startDate, String? targetDate}) {
    final clean = title.trim();
    if (clean.isEmpty) throw const ManagementError('Give the goal a title.');
    if (!goalTypes.contains(type)) throw const ManagementError('Choose a goal type.');
    if (DateTime.tryParse(startDate) == null) throw const ManagementError('The start date is not valid.');
    if (_has(targetDate)) {
      final end = DateTime.tryParse(targetDate!);
      if (end == null) throw const ManagementError('The target date is not valid.');
      if (end.isBefore(DateTime.parse(startDate))) throw const ManagementError('The target date cannot be before the start date.');
    }
    if (targetValue != null && (targetValue.isNaN || targetValue.isInfinite || targetValue < 0)) throw const ManagementError('The target must be a number of zero or more.');
    return _GoalFields(clean);
  }

  // ---- Manual progress and milestones ----

  /// Records a value for a goal the app cannot measure itself.
  Future<String> addGoalProgress(String goalId, double value, {String? localDate, String? note}) async {
    if (value.isNaN || value.isInfinite) throw const ManagementError('Enter a number.');
    final date = localDate ?? formatDay(_clock());
    if (DateTime.tryParse(date) == null) throw const ManagementError('The date is not valid.');
    return writer.upsert('goal_progress', {'goal_id': goalId, 'local_date': date, 'value': value, if (_has(note)) 'note': note!.trim()});
  }

  Future<String> addMilestone(String goalId, {required String title, required double targetValue, String? note}) async {
    _checkMilestone(title, targetValue);
    return writer.upsert('milestones', {'goal_id': goalId, 'title': title.trim(), 'target_value': targetValue, if (_has(note)) 'note': note!.trim()});
  }

  Future<void> updateMilestone(String milestoneId, {required String title, required double targetValue, String? note}) async {
    _checkMilestone(title, targetValue);
    await writer.upsert('milestones', {'title': title.trim(), 'target_value': targetValue, 'note': _has(note) ? note!.trim() : null}, id: milestoneId);
  }

  Future<void> deleteMilestone(String milestoneId) => writer.delete('milestones', milestoneId);

  void _checkMilestone(String title, double value) {
    if (title.trim().isEmpty) throw const ManagementError('Give the milestone a title.');
    if (value.isNaN || value.isInfinite) throw const ManagementError('Enter a number for the target.');
  }

  // ---- Muscle self-assessment ----

  /// Saves one self-assessment: a level from 1 to 5 for each muscle you rated. Earlier assessments are kept.
  Future<String> saveAssessment(Map<String, int> levelsByMuscleId, {String? notes}) async {
    if (levelsByMuscleId.isEmpty) throw const ManagementError('Rate at least one muscle.');
    for (final l in levelsByMuscleId.values) {
      if (l < 1 || l > 5) throw const ManagementError('Ratings are from 1 to 5.');
    }
    final assessment = PendingChange.upsert('muscle_assessments', {...localStampOf(_clock()).toPayload(), if (_has(notes)) 'notes': notes!.trim()});
    await writer.apply([
      assessment,
      for (final e in levelsByMuscleId.entries) PendingChange.upsert('muscle_assessment_items', {'assessment_id': assessment.id, 'muscle_id': e.key, 'level': e.value}),
    ]);
    return assessment.id;
  }

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;
}

class _GoalFields {
  const _GoalFields(this.title);

  final String title;
}

String formatDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
