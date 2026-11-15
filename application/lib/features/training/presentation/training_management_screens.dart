import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/editor_sheet.dart';
import '../data/training_management_service.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';
import 'training_editor_widgets.dart';

export 'training_exercise_screens.dart'
    show showExerciseEditor, showExerciseDetail;

int? _int(String s) => int.tryParse(s.trim());

// double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

// const _decimal = TextInputType.numberWithOptions(decimal: true);

/// Lets the person pick one exercise (not in [exclude]); returns its id.
Future<String?> pickExercise(
  BuildContext context, {
  Set<String> exclude = const {},
}) => showEditorSheet<String>(
  context,
  title: 'Choose an exercise',
  builder: (_) => _ExercisePicker(exclude: exclude),
);

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
    final all =
        ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[];
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final e in all)
        if (!e.isInactive &&
            !widget.exclude.contains(e.id) &&
            (q.isEmpty || e.name.toLowerCase().contains(q)))
          e,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldBox(
          hint: 'Search exercises',
          fieldKey: const Key('picker-search'),
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty)
          MutedText(
            all.isEmpty
                ? 'No exercises yet. Add one from the Exercises tab.'
                : 'No exercise matches that search.',
          )
        else
          RowList([
            for (final e in shown)
              RowItem(
                title: e.name,
                subtitle: e.category,
                onTap: () => Navigator.of(context).pop(e.id),
              ),
          ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Templates
// ---------------------------------------------------------------------------------------------------------------

class _Line {
  _Line(
    this.exerciseId, {
    this.sets = '3',
    this.repMin = '',
    this.repMax = '',
    this.rest = '',
    this.startWeightKg,
  });

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
    showEditorSheet<void>(
      context,
      title: templateId == null ? 'New template' : 'Edit template',
      builder: (_) => _TemplateEditor(templateId: templateId),
    );

class _TemplateEditor extends ConsumerStatefulWidget {
  const _TemplateEditor({this.templateId});

  final String? templateId;

  @override
  ConsumerState<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends ConsumerState<_TemplateEditor> {
  String _name = '';
  final String _description = '';
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
    final lines =
        version == null
            ? const <TemplateExercise>[]
            : await repo.templateExercises(version.id);
    if (!mounted) return;
    setState(() {
      _name = version?.name ?? '';
      for (final l in lines) {
        _lines.add(
          _Line(
            l.exerciseId,
            sets: '${l.targetSets}',
            repMin: l.repMin?.toString() ?? '',
            repMax: l.repMax?.toString() ?? '',
            rest: l.restSeconds?.toString() ?? '',
            startWeightKg: l.startWeightKg,
          ),
        );
      }
      _loaded = true;
    });
  }

  Future<void> _add() async {
    final id = await pickExercise(
      context,
      exclude: {for (final l in _lines) l.exerciseId},
    );
    if (id != null && mounted) setState(() => _lines.add(_Line(id)));
  }

  List<TemplateExerciseDraft> _drafts() => [
    for (final l in _lines)
      TemplateExerciseDraft(
        exerciseId: l.exerciseId,
        targetSets: _int(l.sets) ?? 0,
        repMin: _int(l.repMin),
        repMax: _int(l.repMax),
        restSeconds: _int(l.rest),
        startWeightKg: l.startWeightKg,
      ),
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
        await service.createTemplate(
          name: _name,
          description: _description,
          exercises: _drafts(),
        );
      } else {
        await service.updateTemplate(
          id,
          name: _name,
          description: _description,
          exercises: _drafts(),
        );
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
    final names = {
      for (final e
          in ref.watch(exerciseLibraryProvider).valueOrNull ??
              const <Exercise>[])
        e.id: e.name,
    };
    final totalSets = _lines.fold<int>(0, (n, l) => n + (_int(l.sets) ?? 0));
    Widget field(
      String label,
      String initial,
      ValueChanged<String> onChanged, {
      Key? key,
      String? suffix,
    }) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label),
          FieldBox(
            initial: initial,
            keyboard: TextInputType.number,
            height: 52,
            fieldKey: key,
            textAlign: TextAlign.start,
            suffix: suffix,
            onChanged: onChanged,
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Name'),
        FieldBox(
          initial: _name,
          hint: 'e.g. Push day',
          fieldKey: const Key('template-name'),
          textAlign: TextAlign.start,
          onChanged: (v) => _name = v,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'EXERCISES',
                style: TextStyle(
                  color: p.muted,
                  fontSize: 13.5,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            if (_lines.isNotEmpty)
              Text(
                '${_lines.length} ${_lines.length == 1 ? 'exercise' : 'exercises'} · $totalSets ${totalSets == 1 ? 'set' : 'sets'}',
                key: const Key('template-summary'),
                style: TextStyle(color: p.muted, fontSize: 14),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_lines.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: MutedText('No exercises yet.'),
          ),
        for (var i = 0; i < _lines.length; i++)
          Padding(
            key: ValueKey('line-${_lines[i].exerciseId}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: EditorPanel(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1}. ${names[_lines[i].exerciseId] ?? 'Exercise'}',
                          style: TextStyle(
                            color: p.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      SquareIconButton(
                        icon: Icons.arrow_upward,
                        tooltip: 'Move up',
                        onPressed:
                            i == 0
                                ? null
                                : () => setState(
                                  () =>
                                      _lines.insert(i - 1, _lines.removeAt(i)),
                                ),
                      ),
                      const SizedBox(width: 8),
                      SquareIconButton(
                        icon: Icons.arrow_downward,
                        tooltip: 'Move down',
                        onPressed:
                            i == _lines.length - 1
                                ? null
                                : () => setState(
                                  () =>
                                      _lines.insert(i + 1, _lines.removeAt(i)),
                                ),
                      ),
                      const SizedBox(width: 8),
                      SquareIconButton(
                        icon: Icons.close,
                        tooltip: 'Remove',
                        danger: true,
                        onPressed: () => setState(() => _lines.removeAt(i)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      field('Sets', _lines[i].sets, (v) => _lines[i].sets = v),
                      const SizedBox(width: 14),
                      field(
                        'Rest',
                        _lines[i].rest,
                        (v) => _lines[i].rest = v,
                        suffix: 's',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      field(
                        'Min reps',
                        _lines[i].repMin,
                        (v) => _lines[i].repMin = v,
                      ),
                      const SizedBox(width: 14),
                      field(
                        'Max reps',
                        _lines[i].repMax,
                        (v) => _lines[i].repMax = v,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        DashedButton('+ Add exercise', onPressed: _add),
        const SizedBox(height: 16),
        FormError(_error),
        AppButton.primary('Save template', onPressed: _busy ? null : _save),
        if (widget.templateId != null) ...[
          const SizedBox(height: 10),
          AppButton(
            'Duplicate',
            onPressed: () async {
              await ref
                  .read(trainingManagementServiceProvider)
                  .duplicateTemplate(widget.templateId!);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const SizedBox(height: 10),
          AppButton(
            'Delete template',
            kind: ButtonKind.danger,
            onPressed: () async {
              final sure = await askChoice(
                context,
                title: 'Delete this template?',
                body:
                    'Past workouts keep what they did. Splits that use it will have a day with no workout.',
                choices: const [
                  ('keep', 'Keep it', ButtonKind.tonal),
                  ('delete', 'Delete', ButtonKind.danger),
                ],
              );
              if (sure != 'delete' || !context.mounted) return;
              await ref
                  .read(trainingManagementServiceProvider)
                  .deleteTemplate(widget.templateId!);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ],
    );
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
    showEditorSheet<void>(
      context,
      title: split == null ? 'New split' : 'Edit split',
      builder: (_) => _SplitEditor(split: split),
    );

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
  late final List<_DayLine> _days = [
    for (final d in widget.split?.days ?? const <SplitDay>[])
      _DayLine(label: d.label, isRest: d.isRest, templateId: d.templateId),
  ];
  bool _activate = false;
  String? _error;
  bool _busy = false;

  Future<void> _pickTemplate(_DayLine day) async {
    final id = await showEditorSheet<String>(
      context,
      title: 'Choose a template',
      builder: (_) => const _TemplatePicker(),
    );
    if (id != null && mounted) {
      setState(() => day.templateId = id == '' ? null : id);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(trainingManagementServiceProvider);
      final drafts = [
        for (final d in _days)
          SplitDayDraft(
            label: d.label,
            isRest: d.isRest,
            templateId: d.isRest ? null : d.templateId,
          ),
      ];
      final existing = widget.split;
      if (existing == null) {
        await service.createSplit(
          name: _name,
          pattern: _pattern,
          notes: _notes,
          days: drafts,
          activate: _activate,
        );
      } else {
        await service.updateSplit(
          existing.splitId,
          name: _name,
          pattern: _pattern,
          notes: _notes,
          days: drafts,
        );
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
    final templates = {
      for (final t
          in ref.watch(currentTemplatesProvider).valueOrNull ??
              const <TemplateVersion>[])
        t.templateId: t.name,
    };
    final weekly = _pattern == 'fixed_weekly';
    final full = weekly && _days.length >= 7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Name'),
        FieldBox(
          initial: _name,
          hint: 'e.g. Push Pull Legs',
          fieldKey: const Key('split-name'),
          textAlign: TextAlign.start,
          onChanged: (v) => _name = v,
        ),
        const SizedBox(height: 18),
        const FieldLabel('How the days repeat'),
        PillTabs(
          labels: const ['Weekly', 'Rolling', 'Custom'],
          index: _patterns.indexOf(_pattern),
          container: true,
          onChanged: (i) => setState(() => _pattern = _patterns[i]),
        ),
        const SizedBox(height: 8),
        MutedText(
          weekly
              ? 'Day 1 is Monday, day 2 is Tuesday and so on, up to 7 days.'
              : 'The days repeat in order, one after another, whatever the weekday.',
          size: 15,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(child: FieldLabel('Days')),
            Text(
              weekly
                  ? '${_days.length} of 7'
                  : '${_days.length} ${_days.length == 1 ? 'day' : 'days'}',
              key: const Key('split-day-count'),
              style: TextStyle(color: p.muted, fontSize: 14),
            ),
          ],
        ),
        if (_days.isEmpty)
          EditorPanel(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Column(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.info_outline, color: p.link),
                ),
                const SizedBox(height: 12),
                Text(
                  'No days yet',
                  style: TextStyle(
                    color: p.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const MutedText(
                  'Add your first training or rest day.',
                  size: 15,
                ),
                const SizedBox(height: 16),
                DashedButton('+ Add day', onPressed: _addDay),
              ],
            ),
          ),
        for (var i = 0; i < _days.length; i++)
          Padding(
            key: ObjectKey(_days[i]),
            padding: const EdgeInsets.only(bottom: 12),
            child: EditorPanel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Day ${i + 1}',
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SquareIconButton(
                        icon: Icons.arrow_upward,
                        tooltip: 'Move up',
                        onPressed:
                            i == 0
                                ? null
                                : () => setState(
                                  () => _days.insert(i - 1, _days.removeAt(i)),
                                ),
                      ),
                      const SizedBox(width: 8),
                      SquareIconButton(
                        icon: Icons.arrow_downward,
                        tooltip: 'Move down',
                        onPressed:
                            i == _days.length - 1
                                ? null
                                : () => setState(
                                  () => _days.insert(i + 1, _days.removeAt(i)),
                                ),
                      ),
                      const SizedBox(width: 8),
                      SquareIconButton(
                        icon: Icons.close,
                        tooltip: 'Remove day',
                        danger: true,
                        onPressed: () => setState(() => _days.removeAt(i)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FieldBox(
                    initial: _days[i].label,
                    hint: 'Day name, e.g. Chest + Shoulders',
                    height: 48,
                    textAlign: TextAlign.start,
                    fieldKey: Key('day-name-$i'),
                    onChanged: (v) => _days[i].label = v,
                  ),
                  ToggleRow(
                    title: 'Rest day',
                    value: _days[i].isRest,
                    onChanged: (v) => setState(() => _days[i].isRest = v),
                  ),
                  if (!_days[i].isRest)
                    AppButton(
                      _days[i].templateId == null
                          ? 'Choose a template (optional)'
                          : 'Template: ${templates[_days[i].templateId] ?? 'removed'}',
                      height: 44,
                      onPressed: () => _pickTemplate(_days[i]),
                    ),
                ],
              ),
            ),
          ),
        if (_days.isNotEmpty) DashedButton('+ Add day', onPressed: full ? null : _addDay),
        const SizedBox(height: 18),
        const FieldLabel('Notes · optional'),
        FieldBox(
          initial: _notes,
          hint: 'Anything to remember about this split',
          height: 104,
          multiline: true,
          fieldKey: const Key('split-notes'),
          onChanged: (v) => _notes = v,
        ),
        if (widget.split == null) ...[
          const SizedBox(height: 14),
          EditorPanel(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: ToggleRow(
              title: 'Make this the active split',
              subtitle: 'The split you follow now. Only one is active.',
              value: _activate,
              onChanged: (v) => setState(() => _activate = v),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FormError(_error),
        AppButton.primary('Save split', onPressed: _busy ? null : _save),
      ],
    );
  }

  void _addDay() =>
      setState(() => _days.add(_DayLine(label: 'Day ${_days.length + 1}')));
}

class _TemplatePicker extends ConsumerWidget {
  const _TemplatePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates =
        ref.watch(currentTemplatesProvider).valueOrNull ??
        const <TemplateVersion>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (templates.isEmpty)
          const MutedText(
            'No templates yet. Create one from the Splits tab first.',
          )
        else
          RowList([
            for (final t in templates)
              RowItem(
                title: t.name,
                onTap: () => Navigator.of(context).pop(t.templateId),
              ),
          ]),
        const SizedBox(height: 10),
        AppButton(
          'No template for this day',
          onPressed: () => Navigator.of(context).pop(''),
        ),
      ],
    );
  }
}

/// What can be done with one split.
Future<void> showSplitActions(BuildContext context, ActiveSplit split) =>
    showEditorSheet<void>(
      context,
      title: split.name,
      builder: (_) => _SplitActions(split: split),
    );

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
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(saveErrorText(e))));
        }
      }
    }

    final active = split.status == 'active';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MutedText(
          '${split.days.length} days · ${split.pattern.replaceAll('_', ' ')} · ${active ? 'Active' : split.status}',
        ),
        const SizedBox(height: 12),
        RowList([
          for (final d in split.days)
            RowItem(
              title: 'Day ${d.position} · ${d.isRest ? 'Rest' : d.label}',
            ),
        ]),
        const SizedBox(height: 14),
        if (!active)
          AppButton.primary(
            'Make this the active split',
            onPressed: () => run(() => service.activateSplit(split.splitId)),
          ),
        if (active)
          AppButton(
            'Stop following this split',
            onPressed: () => run(() => service.deactivateSplit(split.splitId)),
          ),
        const SizedBox(height: 10),
        AppButton(
          'Edit',
          onPressed: () {
            Navigator.of(context).pop();
            showSplitEditor(context, split: split);
          },
        ),
        const SizedBox(height: 10),
        AppButton(
          'Duplicate',
          onPressed: () => run(() => service.duplicateSplit(split.splitId)),
        ),
        const SizedBox(height: 10),
        AppButton(
          'Archive',
          kind: ButtonKind.danger,
          onPressed: () async {
            final sure = await askChoice(
              context,
              title: 'Archive this split?',
              body:
                  'It leaves your list. Past workouts and the schedule keep it.',
              choices: const [
                ('keep', 'Keep it', ButtonKind.tonal),
                ('archive', 'Archive', ButtonKind.danger),
              ],
            );
            if (sure == 'archive') {
              await run(() => service.archiveSplit(split.splitId));
            }
          },
        ),
      ],
    );
  }
}
