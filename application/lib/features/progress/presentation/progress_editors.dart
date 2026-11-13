import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/editor_sheet.dart';
import '../../training/data/training_models.dart';
import '../../training/data/training_providers.dart';
import '../../training/presentation/training_management_screens.dart' show pickExercise;
import '../data/progress_models.dart';
import '../data/progress_providers.dart';
import '../data/progress_service.dart';

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

const _decimal = TextInputType.numberWithOptions(decimal: true);

String _typeLabel(String t) {
  final s = t.replaceAll('_', ' ');
  return '${s[0].toUpperCase()}${s.substring(1)}';
}

String _day(DateTime d) => formatDay(d);

Future<String?> _pickDate(BuildContext context, String? initial, {DateTime? first}) async {
  final start = DateTime.tryParse(initial ?? '') ?? DateTime.now();
  final picked = await showDatePicker(context: context, initialDate: start, firstDate: first ?? DateTime(2000), lastDate: DateTime(2100));
  return picked == null ? null : _day(picked);
}

// ---------------------------------------------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------------------------------------------

/// Creates a goal (no [goal]) or edits one.
Future<void> showGoalEditor(BuildContext context, {Goal? goal}) =>
    showEditorSheet<void>(context, title: goal == null ? 'New goal' : 'Edit goal', builder: (_) => _GoalEditor(goal: goal));

class _GoalEditor extends ConsumerStatefulWidget {
  const _GoalEditor({this.goal});

  final Goal? goal;

  @override
  ConsumerState<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends ConsumerState<_GoalEditor> {
  late String _title = widget.goal?.title ?? '';
  late String _description = widget.goal?.description ?? '';
  late String? _type = widget.goal?.type;
  late String _target = widget.goal?.targetValue == null ? '' : _plain(widget.goal!.targetValue!);
  late String _unit = widget.goal?.targetUnit ?? '';
  late String _start = widget.goal?.startDate ?? _day(DateTime.now());
  late String? _end = widget.goal?.targetDate;
  // `manual`, one of [measuredMetrics], `est_1rm` or `max_reps`.
  late String _metric = _metricOf(widget.goal?.targetMetric);
  String? _exerciseId;
  String? _error;
  bool _busy = false;

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  String _metricOf(String? m) {
    if (m == null || m.isEmpty) return 'manual';
    if (m.startsWith('est_1rm:')) {
      _exerciseId = m.substring(8);
      return 'est_1rm';
    }
    if (m.startsWith('max_reps:')) {
      _exerciseId = m.substring(9);
      return 'max_reps';
    }
    return measuredMetrics.containsKey(m) ? m : 'manual';
  }

  String? get _metricValue => switch (_metric) {
        'manual' => null,
        'est_1rm' => _exerciseId == null ? null : 'est_1rm:$_exerciseId',
        'max_reps' => _exerciseId == null ? null : 'max_reps:$_exerciseId',
        _ => _metric,
      };

  String get _unitValue => switch (_metric) {
        'manual' => _unit,
        'est_1rm' => 'kg',
        'max_reps' => 'reps',
        _ => measuredMetrics[_metric]?.$2 ?? _unit,
      };

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if ((_metric == 'est_1rm' || _metric == 'max_reps') && _exerciseId == null) throw ArgumentError('Choose the exercise this goal is about.');
      if (_type == null) throw ArgumentError('Choose a goal type.');
      final target = _target.trim().isEmpty ? null : _num(_target);
      if (_target.trim().isNotEmpty && target == null) throw ArgumentError('The target must be a number.');
      final service = ref.read(progressServiceProvider);
      final g = widget.goal;
      if (g == null) {
        await service.createGoal(type: _type!, title: _title, description: _description, targetMetric: _metricValue, targetValue: target, targetUnit: _unitValue, startDate: _start, targetDate: _end);
      } else {
        await service.updateGoal(g.id, type: _type!, title: _title, description: _description, targetMetric: _metricValue, targetValue: target, targetUnit: _unitValue, startDate: _start, targetDate: _end);
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
    final names = ref.watch(exerciseNamesProvider);
    final metrics = <(String, String)>[
      ('manual', 'I enter the values'),
      for (final e in measuredMetrics.entries) (e.key, e.value.$1),
      ('est_1rm', 'Estimated 1RM of an exercise'),
      ('max_reps', 'Most reps of an exercise'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const FieldLabel('Title'),
      FieldBox(initial: _title, hint: 'e.g. Bench press 100 kg', fieldKey: const Key('goal-title'), onChanged: (v) => _title = v),
      const SizedBox(height: 12),
      const FieldLabel('Type'),
      ChoiceWrap(options: [for (final t in goalTypes) (t, _typeLabel(t))], selected: {if (_type != null) _type!}, onToggle: (t) => setState(() => _type = t)),
      const SizedBox(height: 12),
      const FieldLabel('How is it measured?'),
      ChoiceWrap(options: metrics, selected: {_metric}, onToggle: (m) => setState(() => _metric = m)),
      if (_metric == 'est_1rm' || _metric == 'max_reps') ...[
        const SizedBox(height: 10),
        AppButton(_exerciseId == null ? 'Choose the exercise' : 'Exercise: ${names[_exerciseId] ?? 'chosen'}', height: 46, onPressed: () async {
          final id = await pickExercise(context);
          if (id != null && mounted) setState(() => _exerciseId = id);
        }),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FieldLabel('Target'),
          FieldBox(initial: _target, hint: 'e.g. 80', keyboard: _decimal, fieldKey: const Key('goal-target'), onChanged: (v) => _target = v),
        ])),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FieldLabel('Unit'),
          _metric == 'manual' ? FieldBox(initial: _unit, hint: 'kg, reps…', onChanged: (v) => _unit = v) : InnerTile(padding: const EdgeInsets.all(16), child: Text(_unitValue.isEmpty ? '–' : _unitValue)),
        ])),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: AppButton('Start: $_start', height: 46, onPressed: () async {
          final d = await _pickDate(context, _start);
          if (d != null && mounted) setState(() => _start = d);
        })),
        const SizedBox(width: 10),
        Expanded(child: AppButton(_end == null ? 'No deadline' : 'By: $_end', height: 46, onPressed: () async {
          final d = await _pickDate(context, _end ?? _start, first: DateTime.tryParse(_start));
          if (d != null && mounted) setState(() => _end = d);
        })),
      ]),
      if (_end != null) ...[
        const SizedBox(height: 6),
        LinkText('Remove deadline', onTap: () => setState(() => _end = null)),
      ],
      const SizedBox(height: 12),
      const FieldLabel('Notes (optional)'),
      FieldBox(initial: _description, onChanged: (v) => _description = v),
      const SizedBox(height: 16),
      FormError(_error),
      AppButton.primary('Save goal', onPressed: _busy ? null : _save),
    ]);
  }
}

/// Everything you can do with one goal: change it, record progress, manage milestones, pause, complete or archive.
Future<void> showGoalActions(BuildContext context, Goal goal) =>
    showEditorSheet<void>(context, title: goal.title, builder: (_) => _GoalActions(goalId: goal.id));

class _GoalActions extends ConsumerStatefulWidget {
  const _GoalActions({required this.goalId});

  final String goalId;

  @override
  ConsumerState<_GoalActions> createState() => _GoalActionsState();
}

class _GoalActionsState extends ConsumerState<_GoalActions> {
  String _value = '';
  String _note = '';
  String? _error;

  Future<void> _run(Future<void> Function() action, {bool close = false}) async {
    try {
      await action();
      if (close && mounted) Navigator.of(context).pop();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = saveErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = [for (final g in ref.watch(allGoalsProvider).valueOrNull ?? const <Goal>[]) if (g.id == widget.goalId) g].firstOrNull;
    if (goal == null) return const MutedText('This goal is not on this phone.');
    final service = ref.read(progressServiceProvider);
    final milestones = ref.watch(milestonesProvider(goal.id)).valueOrNull ?? const <Milestone>[];
    final metric = goal.targetMetric;
    final manual = metric == null || metric.isEmpty || !(measuredMetrics.containsKey(metric) || metric.startsWith('est_1rm:') || metric.startsWith('max_reps:'));
    final open = goal.status == 'active' || goal.status == 'paused';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MutedText('${_typeLabel(goal.type)} · ${_typeLabel(goal.status == 'abandoned' ? 'archived' : goal.status)}${goal.targetValue == null ? '' : ' · target ${goal.targetValue}${goal.targetUnit == null ? '' : ' ${goal.targetUnit}'}'}'),
      const SizedBox(height: 12),
      FormError(_error),
      AppButton.primary('Edit goal', onPressed: () {
        Navigator.of(context).pop();
        showGoalEditor(context, goal: goal);
      }),
      if (manual && open) ...[
        const SizedBox(height: 16),
        const FieldLabel('Record progress'),
        Row(children: [
          Expanded(child: FieldBox(hint: 'Value', keyboard: _decimal, fieldKey: const Key('progress-value'), onChanged: (v) => _value = v)),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: AppButton('Save', onPressed: () => _run(() async {
              final v = _num(_value);
              if (v == null) throw ArgumentError('Enter a number.');
              await service.addGoalProgress(goal.id, v, note: _note);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Progress saved.')));
            })),
          ),
        ]),
        const SizedBox(height: 6),
        const MutedText('This goal is not measured automatically, so progress comes from the values you record.'),
      ],
      const SizedBox(height: 16),
      const FieldLabel('Milestones'),
      if (milestones.isEmpty)
        const MutedText('No milestones yet.')
      else
        RowList([
          for (final m in milestones)
            RowItem(title: m.title, subtitle: 'Target ${m.targetValue}', chevron: true, onTap: () => showMilestoneEditor(context, goal.id, milestone: m)),
        ]),
      const SizedBox(height: 10),
      AppButton('Add a milestone', onPressed: () => showMilestoneEditor(context, goal.id)),
      const SizedBox(height: 16),
      if (goal.status == 'active') AppButton('Pause', onPressed: () => _run(() => service.setGoalStatus(goal.id, 'paused'), close: true)),
      if (goal.status == 'paused') AppButton('Resume', onPressed: () => _run(() => service.setGoalStatus(goal.id, 'active'), close: true)),
      if (!open) AppButton('Reopen this goal', onPressed: () => _run(() => service.setGoalStatus(goal.id, 'active'), close: true)),
      if (open) ...[
        const SizedBox(height: 10),
        AppButton('Mark as completed', onPressed: () => _run(() => service.setGoalStatus(goal.id, 'completed'), close: true)),
        const SizedBox(height: 10),
        AppButton('Archive', kind: ButtonKind.danger, onPressed: () async {
          final sure = await askChoice(context, title: 'Archive this goal?', body: 'It leaves your goals list. You can show archived goals and reopen it later.', choices: const [('keep', 'Keep it', ButtonKind.tonal), ('archive', 'Archive', ButtonKind.danger)]);
          if (sure == 'archive') await _run(() => service.setGoalStatus(goal.id, 'abandoned'), close: true);
        }),
      ],
    ]);
  }
}

/// Adds a milestone (no [milestone]) or edits or deletes one.
Future<void> showMilestoneEditor(BuildContext context, String goalId, {Milestone? milestone}) =>
    showEditorSheet<void>(context, title: milestone == null ? 'New milestone' : 'Edit milestone', builder: (_) => _MilestoneEditor(goalId: goalId, milestone: milestone));

class _MilestoneEditor extends ConsumerStatefulWidget {
  const _MilestoneEditor({required this.goalId, this.milestone});

  final String goalId;
  final Milestone? milestone;

  @override
  ConsumerState<_MilestoneEditor> createState() => _MilestoneEditorState();
}

class _MilestoneEditorState extends ConsumerState<_MilestoneEditor> {
  late String _title = widget.milestone?.title ?? '';
  late String _target = widget.milestone == null ? '' : widget.milestone!.targetValue.toString();
  late String _note = widget.milestone?.note ?? '';
  String? _error;

  Future<void> _save() async {
    try {
      final v = _num(_target);
      if (v == null) throw ArgumentError('Enter a number for the target.');
      final service = ref.read(progressServiceProvider);
      final m = widget.milestone;
      if (m == null) {
        await service.addMilestone(widget.goalId, title: _title, targetValue: v, note: _note);
      } else {
        await service.updateMilestone(m.id, title: _title, targetValue: v, note: _note);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = saveErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const FieldLabel('Title'),
      FieldBox(initial: _title, hint: 'e.g. 90 kg bench', fieldKey: const Key('milestone-title'), onChanged: (v) => _title = v),
      const SizedBox(height: 12),
      const FieldLabel('Target value'),
      FieldBox(initial: _target, keyboard: _decimal, fieldKey: const Key('milestone-target'), onChanged: (v) => _target = v),
      const SizedBox(height: 12),
      const FieldLabel('Note (optional)'),
      FieldBox(initial: _note, onChanged: (v) => _note = v),
      const SizedBox(height: 16),
      FormError(_error),
      AppButton.primary('Save milestone', onPressed: _save),
      if (widget.milestone != null) ...[
        const SizedBox(height: 10),
        AppButton('Delete milestone', kind: ButtonKind.danger, onPressed: () async {
          await ref.read(progressServiceProvider).deleteMilestone(widget.milestone!.id);
          if (context.mounted) Navigator.of(context).pop();
        }),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Muscle self-assessment
// ---------------------------------------------------------------------------------------------------------------

const _levelLabels = {1: 'Underdeveloped', 2: 'Below average', 3: 'Average', 4: 'Above average', 5: 'Well developed'};

/// Rate your muscles from 1 to 5. Your own opinion: it is never calculated, and earlier assessments are kept.
Future<void> showAssessmentSheet(BuildContext context) => showEditorSheet<void>(context, title: 'Rate your muscles', builder: (_) => const _AssessmentSheet());

class _AssessmentSheet extends ConsumerStatefulWidget {
  const _AssessmentSheet();

  @override
  ConsumerState<_AssessmentSheet> createState() => _AssessmentSheetState();
}

class _AssessmentSheetState extends ConsumerState<_AssessmentSheet> {
  final Map<String, int> _levels = {};
  bool _seeded = false;
  String _notes = '';
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(progressServiceProvider).saveAssessment(_levels, notes: _notes);
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
    final muscles = ref.watch(musclesProvider).valueOrNull ?? const <MuscleRef>[];
    final current = ref.watch(muscleRatingsProvider).rows;
    if (!_seeded && current.isNotEmpty) {
      _seeded = true;
      for (final r in current) {
        if (r.currentLevel != null) _levels[r.muscleId] = r.currentLevel!;
      }
    }
    String? group;
    final rows = <Widget>[];
    for (final m in muscles) {
      if (m.groupKey != group) {
        group = m.groupKey;
        rows.add(Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text('${group[0].toUpperCase()}${group.substring(1)}', style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w700))));
      }
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(m.label, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600))),
          for (var l = 1; l <= 5; l++)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                key: Key('rate-${m.key}-$l'),
                onTap: () => setState(() => _levels[m.id] == l ? _levels.remove(m.id) : _levels[m.id] = l),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _levels[m.id] == l ? p.primary : p.tile, borderRadius: BorderRadius.circular(10)),
                  child: Text('$l', style: TextStyle(color: _levels[m.id] == l ? p.onPrimary : p.text, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MutedText('1 = ${_levelLabels[1]}, 3 = ${_levelLabels[3]}, 5 = ${_levelLabels[5]}. Tap a number again to clear it. Rate only the muscles you want to.'),
      if (muscles.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: MutedText('The muscle list has not loaded on this phone yet.')),
      ...rows,
      const SizedBox(height: 12),
      const FieldLabel('Notes (optional)'),
      FieldBox(onChanged: (v) => _notes = v),
      const SizedBox(height: 16),
      FormError(_error),
      AppButton.primary('Save assessment', onPressed: _busy ? null : _save),
    ]);
  }
}
