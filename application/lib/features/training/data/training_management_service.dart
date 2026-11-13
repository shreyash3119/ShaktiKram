import '../../../core/errors/user_facing_error.dart';
import '../../../core/sync/change_writer.dart';
import 'training_models.dart';
import 'training_repository.dart';

/// A value the person typed is not acceptable. The message is written for the person.
class ManagementError implements UserFacingError {
  const ManagementError(this.message);

  @override
  final String message;

  @override
  String toString() => message;
}

/// One exercise line of a template being saved.
class TemplateExerciseDraft {
  const TemplateExerciseDraft({required this.exerciseId, this.targetSets = 3, this.repMin, this.repMax, this.restSeconds, this.startWeightKg, this.notes});

  final String exerciseId;
  final int targetSets;
  final int? repMin;
  final int? repMax;
  final int? restSeconds;
  final double? startWeightKg;
  final String? notes;
}

/// One day of a split being saved. A rest day has no template.
class SplitDayDraft {
  const SplitDayDraft({required this.label, this.isRest = false, this.templateId});

  final String label;
  final bool isRest;
  final String? templateId;
}

/// What one calendar day of a plan holds.
class PlannedDay {
  const PlannedDay({required this.localDate, required this.day});

  final String localDate;
  final SplitDay day;
}

String _two(int n) => n.toString().padLeft(2, '0');

String formatLocalDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// Works out which split day falls on which date, without writing anything.
///  - `fixed_weekly`: day 1 is Monday, day 2 Tuesday and so on; weekdays after the last day get nothing.
///  - `rolling` and `custom`: the days repeat in order from [from], one per date.
/// Dates before [from] are never returned.
List<PlannedDay> planDays(ActiveSplit split, String from, int count) {
  if (split.days.isEmpty || count <= 0) return const [];
  final start = DateTime.parse(from);
  final out = <PlannedDay>[];
  for (var i = 0; i < count; i++) {
    final d = DateTime.utc(start.year, start.month, start.day + i);
    final SplitDay? day;
    if (split.pattern == 'fixed_weekly') {
      final index = d.weekday - 1;
      day = index < split.days.length ? split.days[index] : null;
    } else {
      day = split.days[i % split.days.length];
    }
    if (day != null) out.add(PlannedDay(localDate: formatLocalDate(d), day: day));
  }
  return out;
}

/// Everything that manages the training plan: exercises, templates, splits and the schedule. Each call is one atomic
/// local step through the outbox, so it works offline. Rules are checked here so a normal entry is never refused by
/// the server: names are not blank, an exercise name is not used twice, rep ranges make sense.
class TrainingManagementService {
  TrainingManagementService({required this.writer, required this.repository, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final ChangeWriter writer;
  final TrainingRepository repository;
  final DateTime Function() _clock;

  // ---- Exercises ----

  /// Adds an exercise of your own. [primaryMuscleIds] needs at least one muscle. Returns the exercise id.
  Future<String> createExercise({
    required String name,
    String? category,
    String? equipmentId,
    String? notes,
    required List<String> primaryMuscleIds,
    List<String> secondaryMuscleIds = const [],
  }) async {
    final clean = await _checkExercise(name: name, category: category, primary: primaryMuscleIds);
    final exercise = PendingChange.upsert('exercises', {
      'name': clean,
      'is_custom': true,
      if (category != null) 'category': category,
      if (equipmentId != null) 'equipment_id': equipmentId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    await writer.apply([exercise, ..._muscleRows(exercise.id, primaryMuscleIds, secondaryMuscleIds)]);
    return exercise.id;
  }

  /// Changes an exercise's name, category, equipment, notes and muscles. Past workouts keep pointing at it.
  Future<void> updateExercise(
    String exerciseId, {
    required String name,
    String? category,
    String? equipmentId,
    String? notes,
    required List<String> primaryMuscleIds,
    List<String> secondaryMuscleIds = const [],
  }) async {
    final clean = await _checkExercise(name: name, category: category, primary: primaryMuscleIds, ignoreId: exerciseId);
    final changes = <PendingChange>[
      PendingChange.upsert('exercises', {
        'name': clean,
        'category': category,
        'equipment_id': equipmentId,
        'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      }, id: exerciseId),
    ];
    final wanted = {for (final m in primaryMuscleIds) m: 'primary', for (final m in secondaryMuscleIds) if (!primaryMuscleIds.contains(m)) m: 'secondary'};
    final existing = await repository.exerciseMuscleRows(exerciseId);
    for (final row in existing) {
      final muscleId = row['muscle_id'] as String;
      final role = wanted[muscleId];
      if (role == null) {
        changes.add(PendingChange.delete('exercise_muscles', row['id'] as String));
      } else {
        if (row['role'] != role) changes.add(PendingChange.upsert('exercise_muscles', {'role': role}, id: row['id'] as String));
        wanted.remove(muscleId);
      }
    }
    for (final e in wanted.entries) {
      changes.add(PendingChange.upsert('exercise_muscles', {'exercise_id': exerciseId, 'muscle_id': e.key, 'role': e.value}));
    }
    await writer.apply(changes);
  }

  /// Takes an exercise out of use (or back into use). Nothing is deleted, so past workouts keep their exercise.
  Future<void> setExerciseInactive(String exerciseId, bool inactive) =>
      writer.apply([PendingChange.upsert('exercises', {'removed_on': inactive ? formatLocalDate(_clock()) : null}, id: exerciseId)]);

  Future<String> _checkExercise({required String name, String? category, required List<String> primary, String? ignoreId}) async {
    final clean = name.trim();
    if (clean.isEmpty) throw const ManagementError('Give the exercise a name.');
    if (clean.length > 120) throw const ManagementError('The name is too long. Keep it under 120 characters.');
    if (category != null && category != 'compound' && category != 'isolation') throw const ManagementError('Category is compound or isolation.');
    if (primary.isEmpty) throw const ManagementError('Choose at least one main muscle.');
    for (final e in await repository.exercises()) {
      if (e.id != ignoreId && e.name.trim().toLowerCase() == clean.toLowerCase()) throw ManagementError('You already have an exercise called "${e.name}".');
    }
    return clean;
  }

  List<PendingChange> _muscleRows(String exerciseId, List<String> primary, List<String> secondary) => [
        for (final m in primary) PendingChange.upsert('exercise_muscles', {'exercise_id': exerciseId, 'muscle_id': m, 'role': 'primary'}),
        for (final m in secondary)
          if (!primary.contains(m)) PendingChange.upsert('exercise_muscles', {'exercise_id': exerciseId, 'muscle_id': m, 'role': 'secondary'}),
      ];

  // ---- Templates ----

  /// Creates a template (version 1) with its exercises. Returns the template id.
  Future<String> createTemplate({required String name, String? description, required List<TemplateExerciseDraft> exercises, String? duplicatedFromId}) async {
    final clean = _checkTemplate(name, exercises);
    final template = PendingChange.upsert('workout_templates', {if (duplicatedFromId != null) 'duplicated_from_id': duplicatedFromId});
    final version = PendingChange.newVersion('template_versions', {'entity_id': template.id, 'name': clean, if (_has(description)) 'description': description!.trim()});
    await writer.apply([template, version, ..._templateRows(version.id, exercises)]);
    return template.id;
  }

  /// Saves a changed template as a new version. Workouts already done keep the version they used.
  Future<void> updateTemplate(String templateId, {required String name, String? description, required List<TemplateExerciseDraft> exercises, String? reason}) async {
    final clean = _checkTemplate(name, exercises);
    final version = PendingChange.newVersion('template_versions', {'entity_id': templateId, 'name': clean, if (_has(description)) 'description': description!.trim()}, reason: reason);
    await writer.apply([version, ..._templateRows(version.id, exercises)]);
  }

  /// Copies a template under a new name. Returns the new template id.
  Future<String> duplicateTemplate(String templateId) async {
    final current = await repository.currentVersionOfTemplate(templateId);
    if (current == null) throw const ManagementError('That template is not on this phone.');
    final lines = await repository.templateExercises(current.id);
    return createTemplate(
      name: '${current.name} (copy)',
      duplicatedFromId: templateId,
      exercises: [
        for (final l in lines)
          TemplateExerciseDraft(exerciseId: l.exerciseId, targetSets: l.targetSets, repMin: l.repMin, repMax: l.repMax, restSeconds: l.restSeconds, startWeightKg: l.startWeightKg, notes: l.notes),
      ],
    );
  }

  /// Removes a template from the list. Splits and past workouts that used it keep working.
  Future<void> deleteTemplate(String templateId) => writer.delete('workout_templates', templateId);

  String _checkTemplate(String name, List<TemplateExerciseDraft> exercises) {
    final clean = name.trim();
    if (clean.isEmpty) throw const ManagementError('Give the template a name.');
    if (exercises.isEmpty) throw const ManagementError('Add at least one exercise.');
    final seen = <String>{};
    for (final e in exercises) {
      if (!seen.add(e.exerciseId)) throw const ManagementError('An exercise is in the template twice.');
      if (e.targetSets < 1 || e.targetSets > 32) throw const ManagementError('Sets must be between 1 and 32.');
      final lo = e.repMin;
      final hi = e.repMax;
      if ((lo != null && lo < 1) || (hi != null && hi < 1)) throw const ManagementError('Reps must be at least 1.');
      if (lo != null && hi != null && hi < lo) throw const ManagementError('The top of the rep range cannot be below the bottom.');
      if ((e.restSeconds ?? 0) < 0) throw const ManagementError('Rest cannot be negative.');
      if ((e.startWeightKg ?? 0) < 0) throw const ManagementError('Weight cannot be negative.');
    }
    return clean;
  }

  List<PendingChange> _templateRows(String versionId, List<TemplateExerciseDraft> exercises) => [
        for (var i = 0; i < exercises.length; i++)
          PendingChange.upsert('template_exercises', {
            'template_version_id': versionId,
            'exercise_id': exercises[i].exerciseId,
            'position': i + 1,
            'target_sets': exercises[i].targetSets,
            if (exercises[i].repMin != null) 'rep_min': exercises[i].repMin,
            if (exercises[i].repMax != null) 'rep_max': exercises[i].repMax,
            if (exercises[i].restSeconds != null) 'rest_s': exercises[i].restSeconds,
            if (exercises[i].startWeightKg != null) 'start_weight_kg': exercises[i].startWeightKg,
            if (_has(exercises[i].notes)) 'notes': exercises[i].notes!.trim(),
          }),
      ];

  // ---- Splits ----

  /// Creates a split with its days. With [activate] it becomes the active split (the previous one is made inactive).
  Future<String> createSplit({required String name, String pattern = 'fixed_weekly', String? notes, required List<SplitDayDraft> days, bool activate = false}) async {
    final clean = _checkSplit(name, pattern, days);
    final split = PendingChange.upsert('splits', {'status': 'draft'});
    final version = PendingChange.newVersion('split_versions', {
      'entity_id': split.id,
      'name': clean,
      'pattern': pattern,
      'cycle_length_days': days.length,
      if (_has(notes)) 'notes': notes!.trim(),
    });
    final changes = <PendingChange>[split, version, ..._dayRows(version.id, days)];
    if (activate) changes.addAll(await _activation(split.id));
    await writer.apply(changes);
    return split.id;
  }

  /// Saves a changed split as a new version with the given days. Past workouts and schedule entries keep their version.
  Future<void> updateSplit(String splitId, {required String name, String pattern = 'fixed_weekly', String? notes, required List<SplitDayDraft> days, String? reason}) async {
    final clean = _checkSplit(name, pattern, days);
    final version = PendingChange.newVersion('split_versions', {
      'entity_id': splitId,
      'name': clean,
      'pattern': pattern,
      'cycle_length_days': days.length,
      if (_has(notes)) 'notes': notes!.trim(),
    }, reason: reason);
    await writer.apply([version, ..._dayRows(version.id, days)]);
  }

  /// Makes a split the active one. The active split, if another, becomes inactive first.
  Future<void> activateSplit(String splitId) async => writer.apply(await _activation(splitId));

  Future<void> deactivateSplit(String splitId) => writer.apply([PendingChange.upsert('splits', {'status': 'inactive'}, id: splitId)]);

  /// Archives a split: it leaves the list but past workouts keep it.
  Future<void> archiveSplit(String splitId) => writer.apply([PendingChange.upsert('splits', {'status': 'archived'}, id: splitId)]);

  Future<String> duplicateSplit(String splitId) async {
    final all = await repository.splits(includeArchived: true);
    final source = all.where((s) => s.splitId == splitId).firstOrNull;
    if (source == null) throw const ManagementError('That split is not on this phone.');
    return createSplit(
      name: '${source.name} (copy)',
      pattern: source.pattern,
      notes: source.notes,
      days: [for (final d in source.days) SplitDayDraft(label: d.label, isRest: d.isRest, templateId: d.templateId)],
    );
  }

  Future<List<PendingChange>> _activation(String splitId) async {
    final out = <PendingChange>[];
    for (final s in await repository.splits()) {
      if (s.status == 'active' && s.splitId != splitId) out.add(PendingChange.upsert('splits', {'status': 'inactive'}, id: s.splitId));
    }
    out.add(PendingChange.upsert('splits', {'status': 'active'}, id: splitId));
    return out;
  }

  String _checkSplit(String name, String pattern, List<SplitDayDraft> days) {
    final clean = name.trim();
    if (clean.isEmpty) throw const ManagementError('Give the split a name.');
    if (pattern != 'fixed_weekly' && pattern != 'rolling' && pattern != 'custom') throw const ManagementError('Choose weekly, rolling or custom.');
    if (days.isEmpty) throw const ManagementError('Add at least one day.');
    if (days.length > 14) throw const ManagementError('A split can have up to 14 days.');
    if (pattern == 'fixed_weekly' && days.length > 7) throw const ManagementError('A weekly split has at most 7 days.');
    for (final d in days) {
      if (d.label.trim().isEmpty) throw const ManagementError('Every day needs a name.');
      if (d.isRest && d.templateId != null) throw const ManagementError('A rest day cannot have a workout.');
    }
    return clean;
  }

  List<PendingChange> _dayRows(String versionId, List<SplitDayDraft> days) => [
        for (var i = 0; i < days.length; i++)
          PendingChange.upsert('split_days', {
            'split_version_id': versionId,
            'position': i + 1,
            'label': days[i].label.trim(),
            'is_rest': days[i].isRest,
            if (!days[i].isRest && days[i].templateId != null) 'template_id': days[i].templateId,
          }),
      ];

  // ---- Schedule ----

  /// Plans [localDate]: a workout day of the active split, or a rest day (when [day] is null). A date that already has
  /// an unfinished entry is replaced. A finished one is left alone.
  Future<void> setScheduleDay(String localDate, {ActiveSplit? split, SplitDay? day, bool rest = false}) async {
    final changes = await _scheduleChanges(localDate, split: split, day: day, rest: rest);
    if (changes != null) await writer.apply(changes);
  }

  /// Clears a planned day. A finished one stays.
  Future<void> clearScheduleDay(String localDate) async {
    final existing = await repository.scheduleFor(localDate);
    if (existing == null) return;
    if (existing.status == 'completed') throw const ManagementError('That workout is already done, so it stays on the schedule.');
    await writer.delete('schedule_entries', existing.id);
  }

  /// Fills [days] dates from [from] following the split's pattern. Dates that already have an entry are left alone.
  /// Returns how many days were planned.
  Future<int> planFromSplit(ActiveSplit split, String from, int days) async {
    final changes = <PendingChange>[];
    for (final p in planDays(split, from, days)) {
      if (await repository.scheduleFor(p.localDate) != null) continue;
      final c = await _scheduleChanges(p.localDate, split: split, day: p.day);
      if (c != null) changes.addAll(c);
    }
    if (changes.isNotEmpty) await writer.apply(changes);
    return changes.where((c) => c.action == 'upsert').length;
  }

  Future<List<PendingChange>?> _scheduleChanges(String localDate, {ActiveSplit? split, SplitDay? day, bool rest = false}) async {
    if (DateTime.tryParse(localDate) == null) throw const ManagementError('That date is not valid.');
    final existing = await repository.scheduleFor(localDate);
    if (existing != null && existing.status == 'completed') throw const ManagementError('That workout is already done, so it stays on the schedule.');
    final changes = <PendingChange>[if (existing != null) PendingChange.delete('schedule_entries', existing.id)];
    if (rest || day == null || day.isRest) {
      changes.add(PendingChange.upsert('schedule_entries', {
        'local_date': localDate,
        'is_rest_day': true,
        'status': 'planned',
        if (split != null) 'split_version_id': split.versionId,
        if (day != null) 'split_day_id': day.id,
      }));
    } else {
      if (split == null) throw const ManagementError('There is no active split to plan from.');
      final template = day.templateId == null ? null : await repository.currentVersionOfTemplate(day.templateId!);
      changes.add(PendingChange.upsert('schedule_entries', {
        'local_date': localDate,
        'is_rest_day': false,
        'status': 'planned',
        'split_version_id': split.versionId,
        'split_day_id': day.id,
        if (template != null) 'template_version_id': template.id,
      }));
    }
    return changes;
  }

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;
}
