import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/meters.dart';

/// Active workout. This is the design pass: sets, rest timer and tools work on the screen only.
/// Nothing is saved yet. Saving goes through the local outbox once the sync client exists.
/// Progression suggestions will come from the backend (decision F5); here "Previous" is placeholder data.
class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _SetData {
  _SetData({
    required this.id,
    required this.warmup,
    required this.prevKg,
    required this.prevReps,
    this.kg = '',
    this.reps = '',
    this.done = false,
  });

  final int id;
  final bool warmup;
  final String prevKg;
  final String prevReps;
  String kg;
  String reps;
  bool done;

  String get previous =>
      prevKg.isEmpty ? 'No previous data' : 'Previous $prevKg × $prevReps';
}

const _exercises = [
  ('Flat Bench Press', '4 × 6–8'),
  ('Incline Dumbbell Press', '3 × 8–10'),
  ('Cable Fly', '3 × 12–15'),
  ('Lateral Raise', '3 × 12–15'),
  ('Overhead Press', '3 × 8–10'),
  ('Triceps Pushdown', '3 × 10–12'),
  ('Face Pull', '3 × 15'),
];

const _totalSets = 24; // placeholder plan total
const _doneBefore = 7; // sets finished in earlier exercises (placeholder)

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  final Map<int, List<_SetData>> _byExercise = {};
  Timer? _ticker;
  int _exercise = 1;
  int _elapsed = 42 * 60 + 10;
  int _restLeft = 72;
  int _nextId = 100;
  int _rir = 2;
  int _rpe = 8;
  bool _paused = false;
  bool _complete = false;
  String? _lastRecorded = 'Set 1 recorded · 28 kg × 10';

  @override
  void initState() {
    super.initState();
    _byExercise[1] = [
      _SetData(
        id: 0,
        warmup: true,
        prevKg: '20',
        prevReps: '12',
        kg: '20',
        reps: '12',
        done: true,
      ),
      _SetData(
        id: 1,
        warmup: false,
        prevKg: '28',
        prevReps: '10',
        kg: '28',
        reps: '10',
        done: true,
      ),
      _SetData(id: 2, warmup: false, prevKg: '28', prevReps: '9', kg: '28'),
      _SetData(id: 3, warmup: false, prevKg: '28', prevReps: '8'),
    ];
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || _complete || !mounted) return;
      setState(() {
        _elapsed++;
        if (_restLeft > 0) _restLeft--;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  List<_SetData> get _sets => _byExercise.putIfAbsent(_exercise, () {
    return [
      _SetData(id: _nextId++, warmup: true, prevKg: '', prevReps: ''),
      for (var i = 0; i < 3; i++)
        _SetData(id: _nextId++, warmup: false, prevKg: '', prevReps: ''),
    ];
  });

  int get _doneTotal =>
      _doneBefore +
      _byExercise.values.fold(0, (a, l) => a + l.where((s) => s.done).length);

  int get _activeIndex => _sets.indexWhere((s) => !s.done);

  static String _clock(int seconds) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(seconds ~/ 3600)}:${two((seconds % 3600) ~/ 60)}:${two(seconds % 60)}';
  }

  static String _mmss(int seconds) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(seconds ~/ 60)}:${two(seconds % 60)}';
  }

  void _confirmSet(int index) {
    final s = _sets[index];
    if (s.kg.trim().isEmpty || s.reps.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter weight and reps first.')),
      );
      return;
    }
    setState(() {
      s.done = true;
      _restLeft = 90; // the rest timer starts after a set is confirmed
      final number = _sets.where((x) => !x.warmup).toList().indexOf(s) + 1;
      _lastRecorded =
          s.warmup
              ? 'Warm-up recorded · ${s.kg} kg × ${s.reps}'
              : 'Set $number recorded · ${s.kg} kg × ${s.reps}';
    });
  }

  void _addSet({required bool warmup}) {
    setState(() {
      final list = _sets;
      final set = _SetData(
        id: _nextId++,
        warmup: warmup,
        prevKg: '',
        prevReps: '',
      );
      if (warmup) {
        final lastWarm = list.lastIndexWhere((s) => s.warmup);
        list.insert(lastWarm + 1, set);
      } else {
        list.add(set);
      }
    });
  }

  void _removeSet({required bool warmup}) {
    setState(() {
      final list = _sets;
      final i = list.lastIndexWhere((s) => s.warmup == warmup && !s.done);
      if (i >= 0) list.removeAt(i);
    });
  }

  void _goTo(int index) {
    if (index < 0 || index >= _exercises.length) return;
    setState(() {
      _exercise = index;
      _restLeft = 0;
    });
  }

  void _exit() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<String?> _ask({
    required String title,
    required String body,
    required List<(String, String, ButtonKind)> choices,
    bool stacked = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final p = ctx.pal;
        Widget button((String, String, ButtonKind) c) => AppButton(
          c.$1,
          kind: c.$3,
          onPressed: () => Navigator.of(ctx).pop(c.$2),
        );
        final Widget actions =
            stacked
                ? Column(
                  children: [
                    for (final c in choices)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SizedBox(
                          width: double.infinity,
                          child: button(c),
                        ),
                      ),
                  ],
                )
                : Row(
                  children: [
                    for (var i = 0; i < choices.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: button(choices[i])),
                    ],
                  ],
                );
        return Dialog(
          backgroundColor: p.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.cardPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                MutedText(body, size: 15),
                const SizedBox(height: 16),
                actions,
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _leave() async {
    final done = _doneTotal;
    final choice = await _ask(
      title: 'Leave workout?',
      body: 'You have $done sets recorded. Leaving now will not erase them.',
      stacked: true,
      choices: const [
        ('Keep going', 'keep', ButtonKind.primary),
        ('Save & exit', 'save', ButtonKind.tonal),
        ('Discard workout', 'discard', ButtonKind.danger),
      ],
    );
    if (!mounted) return;
    if (choice == 'save' || choice == 'discard') _exit();
  }

  Future<void> _finish() async {
    final choice = await _ask(
      title: 'Confirm: finish workout?',
      body: '7 exercises · $_doneTotal sets · 12,450 kg',
      choices: const [
        ('Keep going', 'keep', ButtonKind.tonal),
        ('Finish', 'finish', ButtonKind.primary),
      ],
    );
    if (!mounted || choice != 'finish') return;
    setState(() => _complete = true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _complete,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.pagePadding,
              14,
              AppTheme.pagePadding,
              28,
            ),
            children: [
              _header(context),
              const SizedBox(height: AppTheme.gap),
              if (_complete) ..._summary(context) else ..._active(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        GestureDetector(
          key: const Key('session-back'),
          behavior: HitTestBehavior.opaque,
          onTap: _complete ? _exit : _leave,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Icon(Icons.chevron_left, color: p.text, size: 26),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chest + Shoulders',
                style: TextStyle(
                  color: p.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _complete
                    ? 'Finished · ${_clock(_elapsed)}'
                    : 'Exercise ${_exercise + 1} of ${_exercises.length} · ${_clock(_elapsed)}${_paused ? ' · paused' : ''}',
                style: TextStyle(color: p.muted, fontSize: 15),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _summary(BuildContext context) {
    return [
      const TitledCard(
        title: 'Workout complete',
        sample: true,
        children: [
          Row(
            children: [
              Expanded(child: StatBlock('00:58:12', 'Duration')),
              Expanded(child: StatBlock('5,820 kg', 'Volume')),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: StatBlock('7 / 7', 'Exercises')),
              Expanded(child: StatBlock('1 PR', 'Bench 85 kg')),
            ],
          ),
        ],
      ),
      const SizedBox(height: AppTheme.gap),
      const TitledCard(
        title: 'Session stats',
        sample: true,
        children: [
          Row(
            children: [
              Expanded(flex: 3, child: StatBlock('1,120 kg', 'Volume')),
              Expanded(flex: 2, child: StatBlock('9', 'Sets done')),
              Expanded(flex: 2, child: StatBlock('82 s', 'Avg rest')),
            ],
          ),
        ],
      ),
      const SizedBox(height: AppTheme.gap),
      AppButton.primary('Save workout', height: 56, onPressed: _exit),
    ];
  }

  List<Widget> _active(BuildContext context) {
    final p = context.pal;
    final (name, scheme) = _exercises[_exercise];
    final active = _activeIndex;
    final nextName =
        _exercise + 1 < _exercises.length ? _exercises[_exercise + 1].$1 : null;
    final sets = _sets;
    final warmCount = sets.where((s) => s.warmup).length;
    final workCount = sets.length - warmCount;

    var workNumber = 0;
    final rows = <Widget>[];
    for (var i = 0; i < sets.length; i++) {
      final s = sets[i];
      if (!s.warmup) workNumber++;
      rows.add(
        _SetRow(
          key: ValueKey('set-${s.id}-${i == active}'),
          data: s,
          label: s.warmup ? 'Warm-up' : 'Working set $workNumber',
          number: s.warmup ? 'W' : '$workNumber',
          state:
              s.done
                  ? _RowState.done
                  : (i == active ? _RowState.active : _RowState.pending),
          onKg: (v) => s.kg = v,
          onReps: (v) => s.reps = v,
          onConfirm: () => _confirmSet(i),
          prefillKg: i == active && s.kg.isEmpty ? s.prevKg : null,
        ),
      );
      rows.add(const SizedBox(height: 10));
    }

    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(
                color: p.text,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$scheme · rest 90 s · RIR $_rir',
              style: TextStyle(color: p.muted, fontSize: 14.5),
            ),
            const SizedBox(height: 14),
            ...rows,
            AppButton('+ Add set', onPressed: () => _addSet(warmup: false)),
          ],
        ),
      ),
      if (_restLeft > 0) ...[
        const SizedBox(height: AppTheme.gap),
        AppCard(
          color: p.tile,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rest', style: TextStyle(color: p.muted, fontSize: 15)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _mmss(_restLeft),
                      style: TextStyle(
                        color: p.text,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _restLeft += 15),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        '+15 s',
                        style: TextStyle(
                          color: p.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: () => setState(() => _restLeft = 0),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: p.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: AppTheme.gap),
      ButtonPair(
        AppButton(
          '‹ Prev',
          onPressed: _exercise > 0 ? () => _goTo(_exercise - 1) : null,
        ),
        AppButton.primary(
          nextName == null ? 'Last exercise' : 'Next: $nextName ›',
          onPressed: nextName == null ? null : () => _goTo(_exercise + 1),
        ),
      ),
      const SizedBox(height: 4),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          LinkText('Skip exercise', onTap: () => _goTo(_exercise + 1)),
          LinkText('Add note', onTap: () {}),
          LinkText('Finish workout', color: p.red, onTap: _finish),
        ],
      ),
      const SizedBox(height: 4),
      const GroupLabel('Session tools'),
      const SizedBox(height: AppTheme.gap),
      TitledCard(
        title: 'Workout progress',
        sample: true,
        children: [
          MeterBar(value: _doneTotal / _totalSets),
          const SizedBox(height: 12),
          MutedText(
            'Exercise ${_exercise + 1} of ${_exercises.length} · $_doneTotal of $_totalSets sets done',
            size: 15,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.gap),
      TitledCard(
        title: 'Set details',
        children: [
          const FieldLabel('RIR (reps in reserve)'),
          PillTabs(
            labels: const ['0', '1', '2', '3', '4+'],
            index: _rir.clamp(0, 4),
            onChanged: (i) => setState(() => _rir = i),
          ),
          const SizedBox(height: 12),
          const FieldLabel('RPE (optional)'),
          PillTabs(
            labels: const ['6', '7', '8', '9', '10'],
            index: (_rpe - 6).clamp(0, 4),
            onChanged: (i) => setState(() => _rpe = i + 6),
          ),
          if (_lastRecorded != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: p.greenFill,
                borderRadius: BorderRadius.circular(AppTheme.radius),
              ),
              child: Text(
                '✓ $_lastRecorded',
                style: TextStyle(color: p.green, fontSize: 14.5),
              ),
            ),
          ],
          const SizedBox(height: 14),
          ButtonPair(
            AppButton('+ Add set', onPressed: () => _addSet(warmup: false)),
            AppButton(
              '− Remove set',
              onPressed: () => _removeSet(warmup: false),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppTheme.gap),
      const TitledCard(
        title: 'Notes',
        children: [
          FieldLabel('Exercise note'),
          FieldBox(hint: 'Machine setup, pain, form…'),
          SizedBox(height: 12),
          FieldLabel('Workout note'),
          FieldBox(hint: 'How did it feel?'),
        ],
      ),
      const SizedBox(height: AppTheme.gap),
      const GroupLabel('Exercise tools'),
      const SizedBox(height: AppTheme.gap),
      TitledCard(
        title: 'Sets',
        children: [
          _Stepper(
            label: 'Warm-up sets',
            value: warmCount,
            onMinus: () => _removeSet(warmup: true),
            onPlus: () => _addSet(warmup: true),
          ),
          const SizedBox(height: 10),
          _Stepper(
            label: 'Working sets',
            value: workCount,
            onMinus: () => _removeSet(warmup: false),
            onPlus: () => _addSet(warmup: false),
          ),
        ],
      ),
      const SizedBox(height: AppTheme.gap),
      TitledCard(
        title: 'Replace exercise',
        link: 'Search',
        children: [
          const MutedText(
            'Matched to the same muscles, your equipment and recorded restrictions.',
          ),
          const SizedBox(height: 6),
          RowList([
            RowItem(
              title: 'Cable Fly',
              subtitle: 'Cable · chest',
              trailing: 'Use ›',
              onTap: () {},
            ),
            RowItem(
              title: 'Machine Chest Press',
              subtitle: 'Machine · chest',
              trailing: 'Use ›',
              onTap: () {},
            ),
          ]),
        ],
      ),
      const SizedBox(height: AppTheme.gap),
      TitledCard(
        title: 'Instructions',
        children: [
          const MutedText(
            'Bench at 30°, elbows about 45° from the torso, press steadily off the bottom.',
            size: 15,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            children: [
              for (final m in ['Upper chest', 'Front delts', 'Triceps'])
                Text(m, style: TextStyle(color: p.link, fontSize: 15)),
            ],
          ),
        ],
      ),
      const SizedBox(height: AppTheme.gap),
      TitledCard(
        title: 'Pause or finish',
        children: [
          AppButton(
            _paused ? 'Resume workout' : 'Pause workout',
            onPressed: () => setState(() => _paused = !_paused),
          ),
          const SizedBox(height: 12),
          AppButton.primary('Finish workout', height: 54, onPressed: _finish),
          const SizedBox(height: 12),
          const MutedText('Pause saves progress and you can resume later.'),
        ],
      ),
      const SizedBox(height: AppTheme.gap),
      const TitledCard(
        title: 'Later',
        children: [
          RowList([
            RowItem(
              title: 'Exercise demonstrations',
              subtitle: 'Videos and instructions',
              trailing: 'Later',
            ),
            RowItem(
              title: 'Advanced session stats',
              subtitle: 'Live volume and tempo',
              trailing: 'Later',
            ),
          ]),
        ],
      ),
    ];
  }
}

enum _RowState { done, active, pending }

class _SetRow extends StatelessWidget {
  const _SetRow({
    super.key,
    required this.data,
    required this.label,
    required this.number,
    required this.state,
    required this.onKg,
    required this.onReps,
    required this.onConfirm,
    this.prefillKg,
  });

  final _SetData data;
  final String label;
  final String number;
  final _RowState state;
  final ValueChanged<String> onKg;
  final ValueChanged<String> onReps;
  final VoidCallback onConfirm;
  final String? prefillKg;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final isActive = state == _RowState.active;
    final isDone = state == _RowState.done;

    final Color badgeBg;
    final Color badgeFg;
    if (data.warmup) {
      badgeBg = p.amber.withValues(alpha: 0.2);
      badgeFg = p.amber;
    } else if (isDone) {
      badgeBg = p.greenFill;
      badgeFg = p.green;
    } else if (isActive) {
      badgeBg = p.primary;
      badgeFg = p.onPrimary;
    } else {
      badgeBg = p.tile;
      badgeFg = p.muted;
    }

    final initialKg = data.kg.isNotEmpty ? data.kg : (prefillKg ?? '');
    if (isActive && data.kg.isEmpty && initialKg.isNotEmpty) {
      data.kg = initialKg;
    }

    final check = GestureDetector(
      onTap: isActive ? onConfirm : null,
      child: Container(
        key: isActive ? const Key('confirm-set') : null,
        width: 64,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDone ? p.greenFill : (isActive ? p.primary : p.tile),
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Icon(
          Icons.check,
          size: 26,
          color: isDone ? p.green : (isActive ? p.onPrimary : p.faint),
        ),
      ),
    );

    final content = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? p.bg.withValues(alpha: 0.35) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radius + 2),
        border: isActive ? Border.all(color: p.primary, width: 1.6) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeBg,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  number,
                  style: TextStyle(
                    color: badgeFg,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? '$label · now' : label,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      data.previous,
                      style: TextStyle(color: p.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FieldBox(
                  fieldKey: isActive ? const Key('kg-field') : null,
                  initial: initialKg,
                  hint: 'kg',
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: onKg,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FieldBox(
                  fieldKey: isActive ? const Key('reps-field') : null,
                  initial: data.reps,
                  hint: 'reps',
                  keyboard: TextInputType.number,
                  onChanged: onReps,
                ),
              ),
              const SizedBox(width: 10),
              check,
            ],
          ),
        ],
      ),
    );
    return state == _RowState.pending
        ? Opacity(opacity: 0.55, child: content)
        : content;
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget square(String text, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.tile,
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: p.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: p.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        square('−', onMinus),
        SizedBox(
          width: 44,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        square('+', onPlus),
      ],
    );
  }
}
