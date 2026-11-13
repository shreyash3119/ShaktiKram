import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/editor_sheet.dart';
import '../data/training_management_service.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';

int? _int(String s) => int.tryParse(s.trim());

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

const _decimal = TextInputType.numberWithOptions(decimal: true);

String _label(Map<String, String> byId, String? id) => id == null ? '' : (byId[id] ?? '');

// ---------------------------------------------------------------------------------------------------------------
// Exercises
// ---------------------------------------------------------------------------------------------------------------

/// Adds an exercise (no [exercise]) or edits one.
Future<void> showExerciseEditor(BuildContext context, {Exercise? exercise}) =>
    showEditorSheet<void>(context, title: exercise == null ? 'Add exercise' : 'Edit exercise', builder: (_) => _ExerciseEditor(exercise: exercise));

class _ExerciseEditor extends ConsumerStatefulWidget {
  const _ExerciseEditor({this.exercise});

  final Exercise? exercise;

  @override
  ConsumerState<_ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends ConsumerState<_ExerciseEditor> {
  late String _name = widget.exercise?.name ?? '';
  late String _notes = widget.exercise?.notes ?? '';
  late String? _category = widget.exercise?.category;
  late String? _equipment = widget.exercise?.equipmentId;
  final Set<String> _primary = {};
  final Set<String> _secondary = {};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.exercise;
    if (e != null) {
      ref.read(trainingRepositoryProvider).exerciseMuscles(e.id).then((rows) {
        if (!mounted) return;
        setState(() {
          for (final r in rows) {
            (r.role == 'primary' ? _primary : _secondary).add(r.muscleId);
          }
        });
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(trainingManagementServiceProvider);
      final e = widget.exercise;
      if (e == null) {
        await service.createExercise(name: _name, category: _category, equipmentId: _equipment, notes: _notes, primaryMuscleIds: _primary.toList(), secondaryMuscleIds: _secondary.toList());
      } else {
        await service.updateExercise(e.id, name: _name, category: _category, equipmentId: _equipment, notes: _notes, primaryMuscleIds: _primary.toList(), secondaryMuscleIds: _secondary.toList());
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = saveErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muscles = ref.watch(musclesProvider).valueOrNull ?? const <MuscleRef>[];
    final equipment = ref.watch(equipmentProvider).valueOrNull ?? const <EquipmentRef>[];
    final options = [for (final m in muscles) (m.id, m.label)];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const FieldLabel('Name'),
      FieldBox(initial: _name, hint: 'e.g. Incline dumbbell press', fieldKey: const Key('exercise-name'), onChanged: (v) => _name = v),
      const SizedBox(height: 12),
      const FieldLabel('Category'),
      PillTabs(
        labels: const ['Not set', 'Compound', 'Isolation'],
        index: _category == null ? 0 : (_category == 'compound' ? 1 : 2),
        onChanged: (i) => setState(() => _category = i == 0 ? null : (i == 1 ? 'compound' : 'isolation')),
      ),
      const SizedBox(height: 12),
      const FieldLabel('Main muscles (at least one)'),
      ChoiceWrap(
        options: options,
        selected: _primary,
        onToggle: (id) => setState(() {
          if (!_primary.remove(id)) {
            _primary.add(id);
            _secondary.remove(id);
          }
        }),
      ),
      const SizedBox(height: 12),
      const FieldLabel('Helping muscles (optional)'),
      ChoiceWrap(
        options: options,
        selected: _secondary,
        onToggle: (id) => setState(() {
          if (!_secondary.remove(id)) {
            _secondary.add(id);
            _primary.remove(id);
          }
        }),
      ),
      if (equipment.isNotEmpty) ...[
        const SizedBox(height: 12),
        const FieldLabel('Equipment (optional)'),
        ChoiceWrap(options: [for (final q in equipment) (q.id, q.label)], selected: {if (_equipment != null) _equipment!}, onToggle: (id) => setState(() => _equipment = _equipment == id ? null : id)),
      ],
      const SizedBox(height: 12),
      const FieldLabel('Notes (optional)'),
      FieldBox(initial: _notes, hint: 'Setup, cues, machine number…', onChanged: (v) => _notes = v),
      const SizedBox(height: 16),
      FormError(_error),
      AppButton.primary('Save exercise', onPressed: _busy ? null : _save),
    ]);
  }
}

/// What the app knows about an exercise, with edit and deactivate.
Future<void> showExerciseDetail(BuildContext context, String exerciseId) =>
    showEditorSheet<void>(context, title: 'Exercise', builder: (_) => _ExerciseDetail(exerciseId: exerciseId));

class _ExerciseDetail extends ConsumerWidget {
  const _ExerciseDetail({required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final exercise = [for (final e in ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[]) if (e.id == exerciseId) e].firstOrNull;
    if (exercise == null) return const MutedText('This exercise is not on this phone.');
    final muscles = {for (final m in ref.watch(musclesProvider).valueOrNull ?? const <MuscleRef>[]) m.id: m.label};
    final equipment = {for (final q in ref.watch(equipmentProvider).valueOrNull ?? const <EquipmentRef>[]) q.id: q.label};
    final links = ref.watch(exerciseMusclesProvider(exerciseId)).valueOrNull ?? const <({String muscleId, String role})>[];
    String names(String role) => [for (final l in links) if (l.role == role) _label(muscles, l.muscleId)].where((t) => t.isNotEmpty).join(', ');
    Widget line(String k, String v) => v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 110, child: Text(k, style: TextStyle(color: p.muted, fontSize: 14))),
              Expanded(child: Text(v, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600))),
            ]),
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(exercise.name, style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      line('Category', exercise.category == null ? '' : '${exercise.category![0].toUpperCase()}${exercise.category!.substring(1)}'),
      line('Main muscles', names('primary')),
      line('Helping', names('secondary')),
      line('Equipment', _label(equipment, exercise.equipmentId)),
      line('Notes', exercise.notes ?? ''),
      line('Status', exercise.isInactive ? 'Not in use since ${exercise.removedOn}' : 'In use'),
      const SizedBox(height: 8),
      AppButton.primary('Edit', onPressed: () {
        Navigator.of(context).pop();
        showExerciseEditor(context, exercise: exercise);
      }),
      const SizedBox(height: 10),
      AppButton(exercise.isInactive ? 'Use this exercise again' : 'Stop using this exercise', onPressed: () async {
        await ref.read(trainingManagementServiceProvider).setExerciseInactive(exercise.id, !exercise.isInactive);
        if (context.mounted) Navigator.of(context).pop();
      }),
      const SizedBox(height: 8),
      const MutedText('Past workouts keep the exercise either way. Nothing is deleted.'),
    ]);
  }
}

/// Lets the person pick one exercise (not in [exclude]); returns its id.
Future<String?> pickExercise(BuildContext context, {Set<String> exclude = const {}}) =>
    showEditorSheet<String>(context, title: 'Choose an exercise', builder: (_) => _ExercisePicker(exclude: exclude));

class _ExercisePicker extends ConsumerStatefulWidget {
  const _ExercisePicker({required this.exclude});

  final Set<String> exclude;

  @override
  ConsumerState<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends ConsumerState<_ExercisePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[];
    final q = _q.trim().toLowerCase();
    final shown = [for (final e in all) if (!e.isInactive && !widget.exclude.contains(e.id) && (q.isEmpty || e.name.toLowerCase().contains(q))) e];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldBox(hint: 'Search exercises', fieldKey: const Key('picker-search'), onChanged: (v) => setState(() => _q = v)),
      const SizedBox(height: 10),
      if (shown.isEmpty)
        MutedText(all.isEmpty ? 'No exercises yet. Add one from the Exercises tab.' : 'No exercise matches that search.')
      else
        RowList([for (final e in shown) RowItem(title: e.name, subtitle: e.category, onTap: () => Navigator.of(context).pop(e.id))]),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------------------------------------------

class _Line {
  _Line(this.exerciseId, {this.sets = '3', this.repMin = '', this.repMax = '', this.rest = '', this.startWeightKg});

  final String exerciseId;

  /// Kept as it was when editing, so a change to sets or reps does not drop the starting weight.
  final double? startWeightKg;
  String sets;
  String repMin;
  String repMax;
  String rest;
}

/// Creates a template (no [templateId]) or edits one; an edit is saved as a new version.
Future<void> showTemplateEditor(BuildContext context, {String? templateId}) =>
    showEditorSheet<void>(context, title: templateId == null ? 'New template' : 'Edit template', builder: (_) => _TemplateEditor(templateId: templateId));

class _TemplateEditor extends ConsumerStatefulWidget {
  const _TemplateEditor({this.templateId});

  final String? templateId;

  @override
  ConsumerState<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends ConsumerState<_TemplateEditor> {
  String _name = '';
  String _description = '';
  final List<_Line> _lines = [];
  bool _loaded = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final id = widget.templateId;
    if (id == null) {
      _loaded = true;
    } else {
      _load(id);
    }
  }

  Future<void> _load(String id) async {
    final repo = ref.read(trainingRepositoryProvider);
    final version = await repo.currentVersionOfTemplate(id);
    final lines = version == null ? const <TemplateExercise>[] : await repo.templateExercises(version.id);
    if (!mounted) return;
    setState(() {
      _name = version?.name ?? '';
      for (final l in lines) {
        _lines.add(_Line(l.exerciseId, sets: '${l.targetSets}', repMin: l.repMin?.toString() ?? '', repMax: l.repMax?.toString() ?? '', rest: l.restSeconds?.toString() ?? '', startWeightKg: l.startWeightKg));
      }
      _loaded = true;
    });
  }

  Future<void> _add() async {
    final id = await pickExercise(context, exclude: {for (final l in _lines) l.exerciseId});
    if (id != null && mounted) setState(() => _lines.add(_Line(id)));
  }

  List<TemplateExerciseDraft> _drafts() => [
        for (final l in _lines)
          TemplateExerciseDraft(exerciseId: l.exerciseId, targetSets: _int(l.sets) ?? 0, repMin: _int(l.repMin), repMax: _int(l.repMax), restSeconds: _int(l.rest), startWeightKg: l.startWeightKg),
      ];

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(trainingManagementServiceProvider);
      final id = widget.templateId;
      if (id == null) {
        await service.createTemplate(name: _name, description: _description, exercises: _drafts());
      } else {
        await service.updateTemplate(id, name: _name, description: _description, exercises: _drafts());
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = saveErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (!_loaded) return const MutedText('Loading…');
    final names = {for (final e in ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[]) e.id: e.name};
    Widget small(String hint, String initial, ValueChanged<String> onChanged, {Key? key}) =>
        Expanded(child: FieldBox(initial: initial, hint: hint, keyboard: TextInputType.number, height: 48, fieldKey: key, onChanged: onChanged));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const FieldLabel('Name'),
      FieldBox(initial: _name, hint: 'e.g. Push day', fieldKey: const Key('template-name'), onChanged: (v) => _name = v),
      const SizedBox(height: 12),
      const FieldLabel('Exercises'),
      if (_lines.isEmpty) const MutedText('No exercises yet.'),
      for (var i = 0; i < _lines.length; i++)
        Padding(
          key: ValueKey('line-${_lines[i].exerciseId}'),
          padding: const EdgeInsets.only(bottom: 12),
          child: InnerTile(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${i + 1}. ${names[_lines[i].exerciseId] ?? 'Exercise'}', style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700))),
                IconButton(tooltip: 'Move up', onPressed: i == 0 ? null : () => setState(() => _lines.insert(i - 1, _lines.removeAt(i))), icon: const Icon(Icons.arrow_upward, size: 20)),
                IconButton(tooltip: 'Move down', onPressed: i == _lines.length - 1 ? null : () => setState(() => _lines.insert(i + 1, _lines.removeAt(i))), icon: const Icon(Icons.arrow_downward, size: 20)),
                IconButton(tooltip: 'Remove', onPressed: () => setState(() => _lines.removeAt(i)), icon: Icon(Icons.close, size: 20, color: p.red)),
              ]),
              Row(children: [
                small('Sets', _lines[i].sets, (v) => _lines[i].sets = v),
                const SizedBox(width: 8),
                small('Reps min', _lines[i].repMin, (v) => _lines[i].repMin = v),
                const SizedBox(width: 8),
                small('Reps max', _lines[i].repMax, (v) => _lines[i].repMax = v),
                const SizedBox(width: 8),
                small('Rest s', _lines[i].rest, (v) => _lines[i].rest = v),
              ]),
            ]),
          ),
        ),
      AppButton('Add exercise', onPressed: _add),
      const SizedBox(height: 16),
      FormError(_error),
      AppButton.primary('Save template', onPressed: _busy ? null : _save),
      if (widget.templateId != null) ...[
        const SizedBox(height: 10),
        AppButton('Duplicate', onPressed: () async {
          await ref.read(trainingManagementServiceProvider).duplicateTemplate(widget.templateId!);
          if (context.mounted) Navigator.of(context).pop();
        }),
        const SizedBox(height: 10),
        AppButton('Delete template', kind: ButtonKind.danger, onPressed: () async {
          final sure = await askChoice(context, title: 'Delete this template?', body: 'Past workouts keep what they did. Splits that use it will have a day with no workout.', choices: const [('keep', 'Keep it', ButtonKind.tonal), ('delete', 'Delete', ButtonKind.danger)]);
          if (sure != 'delete' || !context.mounted) return;
          await ref.read(trainingManagementServiceProvider).deleteTemplate(widget.templateId!);
          if (context.mounted) Navigator.of(context).pop();
        }),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Splits
// ---------------------------------------------------------------------------------------------------------------

class _DayLine {
  _DayLine({this.label = '', this.isRest = false, this.templateId});

  String label;
  bool isRest;
  String? templateId;
}

/// Creates a split (no [split]) or edits one; an edit is saved as a new version.
Future<void> showSplitEditor(BuildContext context, {ActiveSplit? split}) =>
    showEditorSheet<void>(context, title: split == null ? 'New split' : 'Edit split', builder: (_) => _SplitEditor(split: split));

class _SplitEditor extends ConsumerStatefulWidget {
  const _SplitEditor({this.split});

  final ActiveSplit? split;

  @override
  ConsumerState<_SplitEditor> createState() => _SplitEditorState();
}

class _SplitEditorState extends ConsumerState<_SplitEditor> {
  static const _patterns = ['fixed_weekly', 'rolling', 'custom'];
  late String _name = widget.split?.name ?? '';
  late String _pattern = widget.split?.pattern ?? 'fixed_weekly';
  late String _notes = widget.split?.notes ?? '';
  late final List<_DayLine> _days = [for (final d in widget.split?.days ?? const <SplitDay>[]) _DayLine(label: d.label, isRest: d.isRest, templateId: d.templateId)];
  bool _activate = false;
  String? _error;
  bool _busy = false;

  Future<void> _pickTemplate(_DayLine day) async {
    final id = await showEditorSheet<String>(context, title: 'Choose a template', builder: (_) => const _TemplatePicker());
    if (id != null && mounted) setState(() => day.templateId = id == '' ? null : id);
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(trainingManagementServiceProvider);
      final drafts = [for (final d in _days) SplitDayDraft(label: d.label, isRest: d.isRest, templateId: d.isRest ? null : d.templateId)];
      final existing = widget.split;
      if (existing == null) {
        await service.createSplit(name: _name, pattern: _pattern, notes: _notes, days: drafts, activate: _activate);
      } else {
        await service.updateSplit(existing.splitId, name: _name, pattern: _pattern, notes: _notes, days: drafts);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = saveErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final templates = {for (final t in ref.watch(currentTemplatesProvider).valueOrNull ?? const <TemplateVersion>[]) t.templateId: t.name};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const FieldLabel('Name'),
      FieldBox(initial: _name, hint: 'e.g. Push Pull Legs', fieldKey: const Key('split-name'), onChanged: (v) => _name = v),
      const SizedBox(height: 12),
      const FieldLabel('How the days repeat'),
      PillTabs(labels: const ['Weekly', 'Rolling', 'Custom'], index: _patterns.indexOf(_pattern), onChanged: (i) => setState(() => _pattern = _patterns[i])),
      const SizedBox(height: 6),
      MutedText(_pattern == 'fixed_weekly' ? 'Day 1 is Monday, day 2 Tuesday and so on (up to 7 days).' : 'The days repeat in order, one after another, whatever the weekday.'),
      const SizedBox(height: 12),
      const FieldLabel('Days'),
      if (_days.isEmpty) const MutedText('No days yet. Add your first day.'),
      for (var i = 0; i < _days.length; i++)
        Padding(
          key: ObjectKey(_days[i]),
          padding: const EdgeInsets.only(bottom: 12),
          child: InnerTile(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Day ${i + 1}', style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w700))),
                IconButton(tooltip: 'Move up', onPressed: i == 0 ? null : () => setState(() => _days.insert(i - 1, _days.removeAt(i))), icon: const Icon(Icons.arrow_upward, size: 20)),
                IconButton(tooltip: 'Move down', onPressed: i == _days.length - 1 ? null : () => setState(() => _days.insert(i + 1, _days.removeAt(i))), icon: const Icon(Icons.arrow_downward, size: 20)),
                IconButton(tooltip: 'Remove day', onPressed: () => setState(() => _days.removeAt(i)), icon: Icon(Icons.close, size: 20, color: p.red)),
              ]),
              FieldBox(initial: _days[i].label, hint: 'Day name, e.g. Chest + Shoulders', height: 48, fieldKey: Key('day-name-$i'), onChanged: (v) => _days[i].label = v),
              ToggleRow(title: 'Rest day', value: _days[i].isRest, onChanged: (v) => setState(() => _days[i].isRest = v)),
              if (!_days[i].isRest)
                AppButton(_days[i].templateId == null ? 'Choose a template (optional)' : 'Template: ${templates[_days[i].templateId] ?? 'removed'}', height: 44, onPressed: () => _pickTemplate(_days[i])),
            ]),
          ),
        ),
      AppButton('Add day', onPressed: () => setState(() => _days.add(_DayLine(label: 'Day ${_days.length + 1}')))),
      const SizedBox(height: 12),
      const FieldLabel('Notes (optional)'),
      FieldBox(initial: _notes, onChanged: (v) => _notes = v),
      if (widget.split == null) ToggleRow(title: 'Make this the active split', subtitle: 'The split you follow now. Only one is active.', value: _activate, onChanged: (v) => setState(() => _activate = v)),
      const SizedBox(height: 12),
      FormError(_error),
      AppButton.primary('Save split', onPressed: _busy ? null : _save),
    ]);
  }
}

class _TemplatePicker extends ConsumerWidget {
  const _TemplatePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(currentTemplatesProvider).valueOrNull ?? const <TemplateVersion>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (templates.isEmpty) const MutedText('No templates yet. Create one from the Splits tab first.') else RowList([for (final t in templates) RowItem(title: t.name, onTap: () => Navigator.of(context).pop(t.templateId))]),
      const SizedBox(height: 10),
      AppButton('No template for this day', onPressed: () => Navigator.of(context).pop('')),
    ]);
  }
}

/// What can be done with one split.
Future<void> showSplitActions(BuildContext context, ActiveSplit split) =>
    showEditorSheet<void>(context, title: split.name, builder: (_) => _SplitActions(split: split));

class _SplitActions extends ConsumerWidget {
  const _SplitActions({required this.split});

  final ActiveSplit split;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(trainingManagementServiceProvider);
    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
        if (context.mounted) Navigator.of(context).pop();
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saveErrorText(e))));
      }
    }

    final active = split.status == 'active';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MutedText('${split.days.length} days · ${split.pattern.replaceAll('_', ' ')} · ${active ? 'Active' : split.status}'),
      const SizedBox(height: 12),
      RowList([for (final d in split.days) RowItem(title: 'Day ${d.position} · ${d.isRest ? 'Rest' : d.label}')]),
      const SizedBox(height: 14),
      if (!active) AppButton.primary('Make this the active split', onPressed: () => run(() => service.activateSplit(split.splitId))),
      if (active) AppButton('Stop following this split', onPressed: () => run(() => service.deactivateSplit(split.splitId))),
      const SizedBox(height: 10),
      AppButton('Edit', onPressed: () {
        Navigator.of(context).pop();
        showSplitEditor(context, split: split);
      }),
      const SizedBox(height: 10),
      AppButton('Duplicate', onPressed: () => run(() => service.duplicateSplit(split.splitId))),
      const SizedBox(height: 10),
      AppButton('Archive', kind: ButtonKind.danger, onPressed: () async {
        final sure = await askChoice(context, title: 'Archive this split?', body: 'It leaves your list. Past workouts and the schedule keep it.', choices: const [('keep', 'Keep it', ButtonKind.tonal), ('archive', 'Archive', ButtonKind.danger)]);
        if (sure == 'archive') await run(() => service.archiveSplit(split.splitId));
      }),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Schedule
// ---------------------------------------------------------------------------------------------------------------

/// Plans one date from the active split, as a rest day, or clears it.
Future<void> showScheduleDaySheet(BuildContext context, String localDate, String dateText) =>
    showEditorSheet<void>(context, title: dateText, builder: (_) => _ScheduleDaySheet(localDate: localDate));

class _ScheduleDaySheet extends ConsumerWidget {
  const _ScheduleDaySheet({required this.localDate});

  final String localDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(activeSplitProvider).valueOrNull;
    final plan = ref.watch(todayPlanProvider(localDate)).valueOrNull;
    final service = ref.read(trainingManagementServiceProvider);
    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
        if (context.mounted) Navigator.of(context).pop();
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saveErrorText(e))));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MutedText(plan?.hasPlan == true ? 'Planned: ${plan!.title ?? 'Workout'}${plan.entry!.status == 'planned' ? '' : ' (${plan.entry!.status})'}' : 'Nothing is planned for this day.'),
      const SizedBox(height: 12),
      if (split == null)
        const MutedText('Create a split and make it active to plan workout days from it. You can still mark a rest day.')
      else ...[
        const FieldLabel('Plan a day from your active split'),
        RowList([for (final d in split.days) RowItem(title: d.isRest ? 'Rest · ${d.label}' : d.label, subtitle: 'Day ${d.position}', onTap: () => run(() => service.setScheduleDay(localDate, split: split, day: d)))]),
      ],
      const SizedBox(height: 12),
      AppButton('Mark as a rest day', onPressed: () => run(() => service.setScheduleDay(localDate, split: split, rest: true))),
      if (plan?.hasPlan == true) ...[
        const SizedBox(height: 10),
        AppButton('Clear this day', kind: ButtonKind.danger, onPressed: () => run(() => service.clearScheduleDay(localDate))),
      ],
    ]);
  }
}
