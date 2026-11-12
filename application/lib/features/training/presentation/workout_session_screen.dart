import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/meters.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';
import '../data/training_repository.dart';
import '../data/workout_session_service.dart';

/// Starts a workout (from [templateVersionId] when given) and opens the session screen. If one is already running
/// the screen simply continues it. Used by the Training and Home start buttons.
Future<void> startOrContinueWorkout(
  BuildContext context,
  WidgetRef ref, {
  String? templateVersionId,
  String? scheduleEntryId,
  String? splitVersionId,
  String? splitDayId,
  String? name,
}) async {
  final service = ref.read(workoutSessionServiceProvider);
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final active = await ref.read(trainingRepositoryProvider).activeSession();
    if (active == null && templateVersionId != null) {
      await service.startSession(
        name: name,
        templateVersionId: templateVersionId,
        scheduleEntryId: scheduleEntryId,
        splitVersionId: splitVersionId,
        splitDayId: splitDayId,
      );
    }
  } on SessionAlreadyActive {
    // Fine: continue the one that is running.
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
    return;
  }
  router.push(AppRoutes.session);
}

/// The active workout. Everything is read from and written to the phone through the training providers and
/// [WorkoutSessionService]; the screen never talks to the backend. Sets are saved the moment they are confirmed,
/// so leaving or restarting the app does not lose them. Suggested weights and PRs are not computed here: they come
/// from the backend later (decision F5), so "Previous" shows only what was actually logged last time.
class WorkoutSessionScreen extends ConsumerStatefulWidget {
  const WorkoutSessionScreen({super.key});

  @override
  ConsumerState<WorkoutSessionScreen> createState() =>
      _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends ConsumerState<WorkoutSessionScreen> {
  Timer? _ticker;
  int _exercise = 0;
  int _restLeft = 0;
  int? _rir;
  double? _rpe;
  bool _warmup = false;
  String? _kg; // null until typed: the previous weight is offered instead
  String _reps = '';
  String _setKey = '';
  String _workoutNote = '';
  DateTime _now = DateTime.now();
  DateTime? _pausedAt;
  String? _finishedId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
        if (_pausedAt == null && _restLeft > 0) _restLeft--;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  WorkoutSessionService get _service => ref.read(workoutSessionServiceProvider);

  static String _clock(int seconds) {
    String two(int n) => n.toString().padLeft(2, '0');
    final s = seconds < 0 ? 0 : seconds;
    return '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
  }

  static String _mmss(int seconds) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(seconds ~/ 60)}:${two(seconds % 60)}';
  }

  static String _kgText(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  int _elapsed(WorkoutSession s) {
    final until = _pausedAt ?? _now;
    return until.difference(s.startedAt).inSeconds - s.pausedSeconds;
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ArgumentError catch (e) {
      if (mounted) _toast('${e.message}');
    } catch (e) {
      if (mounted) _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  Future<void> _leave(SessionDetail detail) async {
    final sets = detail.exercises.fold<int>(0, (a, e) => a + e.sets.length);
    final choice = await _ask(
      title: 'Leave workout?',
      body:
          'You have $sets sets recorded. They are saved on this phone and the workout stays open until you finish it.',
      stacked: true,
      choices: const [
        ('Keep going', 'keep', ButtonKind.primary),
        ('Save & exit', 'save', ButtonKind.tonal),
        ('Discard workout', 'discard', ButtonKind.danger),
      ],
    );
    if (!mounted) return;
    if (choice == 'save') {
      await _saveNote(detail.session.id);
      // A pause is only known while this screen is open, so it ends here: the time paused is added to the session
      // before leaving, and the saved workout is never left "paused" with an unknown start.
      if (_pausedAt != null) await _run(() => _resume(detail.session));
      if (!mounted) return;
      _exit();
    } else if (choice == 'discard') {
      final sure = await _ask(
        title: 'Discard this workout?',
        body: 'Its sets and exercises are removed. This cannot be undone.',
        choices: const [
          ('Keep it', 'keep', ButtonKind.tonal),
          ('Discard', 'discard', ButtonKind.danger),
        ],
      );
      if (!mounted || sure != 'discard') return;
      await _run(() => _service.discardSession(detail.session.id));
      if (mounted) _exit();
    }
  }

  Future<void> _saveNote(String sessionId) async {
    if (_workoutNote.trim().isEmpty) return;
    await _run(() => _service.setNotes(sessionId, _workoutNote));
  }

  Future<void> _finish(SessionDetail detail) async {
    final s = detail.summary;
    final choice = await _ask(
      title: 'Confirm: finish workout?',
      body:
          '${detail.exercises.length} exercises · ${s.workingSets} working sets · ${_kgText(s.volumeKg)} kg',
      choices: const [
        ('Keep going', 'keep', ButtonKind.tonal),
        ('Finish', 'finish', ButtonKind.primary),
      ],
    );
    if (!mounted || choice != 'finish') return;
    await _run(() async {
      if (_pausedAt != null) await _resume(detail.session);
      await _service.completeSession(
        detail.session.id,
        postNotes: _workoutNote,
      );
      if (mounted) setState(() => _finishedId = detail.session.id);
    });
  }

  /// A session saved as `paused` by an earlier run (the app was closed while paused). The database has no pause start,
  /// so the paused time cannot be known. The session goes back to in progress and its clock keeps running; the pause is
  /// not guessed. Done once per screen.
  bool _orphanPauseHandled = false;

  void _endOrphanPause(WorkoutSession s) {
    if (_orphanPauseHandled || _pausedAt != null || s.status != 'paused'){
      return;}
    _orphanPauseHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _run(() => _service.setPaused(s.id, paused: false));
      if (mounted){
        _toast(
          'This workout was paused when the app closed. The pause time was not recorded, so the clock kept running.',
        );}
    });
  }

  Future<void> _pause(WorkoutSession s) async {
    final at = DateTime.now();
    await _service.setPaused(s.id, paused: true);
    if (mounted) setState(() => _pausedAt = at);
  }

  Future<void> _resume(WorkoutSession s) async {
    final at = _pausedAt;
    final seconds = at == null ? 0 : DateTime.now().difference(at).inSeconds;
    await _service.setPaused(s.id, paused: false, addPausedSeconds: seconds);
    if (mounted) setState(() => _pausedAt = null);
  }

  void _resetDraft() {
    _kg = null;
    _reps = '';
    _setKey = '';
  }

  Future<void> _confirmSet(
    SessionExerciseDetail current, {
    required int restSeconds,
    String? prefillKg,
  }) async {
    final kg = double.tryParse(
      (_kg ?? prefillKg ?? '').trim().replaceAll(',', '.'),
    );
    final reps = int.tryParse(_reps.trim());
    if (kg == null || reps == null) {
      _toast('Enter weight and reps first.');
      return;
    }
    await _run(() async {
      await _service.logSet(
        current.exercise.id,
        weightKg: kg,
        reps: reps,
        setType: _warmup ? 'warmup' : 'working',
        rir: _warmup ? null : _rir,
        rpe: _warmup ? null : _rpe,
        restSeconds: restSeconds,
      );
      if (!mounted) return;
      setState(() {
        _restLeft = restSeconds;
        _kg = _kgText(kg);
        _reps = '';
        _setKey = 'after-${DateTime.now().microsecondsSinceEpoch}';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final finished = _finishedId;
    if (finished != null) return _finishedView(finished);

    final active = ref.watch(activeSessionProvider);
    return active.when(
      loading:
          () => const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          ),
      error:
          (e, _) => _shell(null, [
            const MutedText('This workout could not be read from the phone.'),
          ]),
      data: (session) {
        if (session == null) return _picker();
        final detail = ref.watch(sessionDetailProvider(session.id));
        return detail.when(
          loading:
              () => const Scaffold(
                body: SafeArea(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          error:
              (e, _) => _shell(null, [
                const MutedText(
                  'This workout could not be read from the phone.',
                ),
              ]),
          data: (d) => d == null ? _picker() : _activeView(d),
        );
      },
    );
  }

  /// Page frame shared by every state: back button, title and the list of cards.
  Widget _shell(
    SessionDetail? detail,
    List<Widget> children, {
    String title = 'Workout',
    String? subtitle,
    bool canPop = true,
  }) {
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && detail != null) _leave(detail);
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
              _header(
                title,
                subtitle,
                detail == null ? _exit : () => _leave(detail),
              ),
              const SizedBox(height: AppTheme.gap),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String title, String? subtitle, VoidCallback onBack) {
    final p = context.pal;
    return Row(
      children: [
        GestureDetector(
          key: const Key('session-back'),
          behavior: HitTestBehavior.opaque,
          onTap: onBack,
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
                title,
                style: TextStyle(
                  color: p.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: p.muted, fontSize: 15)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---- No workout running: choose how to start ----

  Widget _picker() {
    final templates =
        ref.watch(currentTemplatesProvider).valueOrNull ??
        const <TemplateVersion>[];
    return _shell(null, [
      TitledCard(
        title: 'Start a workout',
        children: [
          AppButton.primary(
            'Start empty workout',
            onPressed:
                _busy
                    ? null
                    : () => _run(() async {
                      await _service.startSession();
                    }),
          ),
          if (templates.isNotEmpty) ...[
            const SizedBox(height: 12),
            const MutedText('Or start from a template:'),
            const SizedBox(height: 6),
            RowList([
              for (final t in templates)
                RowItem(
                  title: t.name,
                  subtitle: 'Version ${t.version}',
                  trailing: 'Start ›',
                  onTap:
                      _busy
                          ? null
                          : () => _run(() async {
                            await _service.startSession(
                              name: t.name,
                              templateVersionId: t.id,
                            );
                          }),
                ),
            ]),
          ],
        ],
      ),
    ]);
  }

  // ---- Finished: summary ----

  Widget _finishedView(String sessionId) {
    final detail = ref.watch(sessionDetailProvider(sessionId)).valueOrNull;
    final names = _exerciseNames();
    final s = detail?.summary;
    return PopScope(
      canPop: true,
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
              _header(
                detail?.session.name ?? 'Workout',
                s == null
                    ? null
                    : 'Finished · ${_clock(s.durationSeconds ?? 0)}',
                _exit,
              ),
              const SizedBox(height: AppTheme.gap),
              TitledCard(
                title: 'Workout complete',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatBlock(
                          _clock(s?.durationSeconds ?? 0),
                          'Duration',
                        ),
                      ),
                      Expanded(
                        child: StatBlock(
                          '${_kgText(s?.volumeKg ?? 0)} kg',
                          'Volume',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: StatBlock(
                          '${s?.exercisesDone ?? 0}',
                          'Exercises done',
                        ),
                      ),
                      Expanded(
                        child: StatBlock(
                          '${s?.workingSets ?? 0}',
                          'Working sets',
                        ),
                      ),
                      Expanded(
                        child: StatBlock('${s?.totalReps ?? 0}', 'Reps'),
                      ),
                    ],
                  ),
                ],
              ),
              if (detail != null) ...[
                const SizedBox(height: AppTheme.gap),
                TitledCard(
                  title: 'What you did',
                  children: [
                    RowList([
                      for (final e in detail.exercises)
                        RowItem(
                          title: names[e.exercise.exerciseId] ?? 'Exercise',
                          subtitle:
                              e.exercise.isSkipped
                                  ? 'Skipped${e.exercise.skipReason == null ? '' : ' · ${e.exercise.skipReason}'}'
                                  : _setsLine(e.sets),
                        ),
                    ]),
                  ],
                ),
              ],
              const SizedBox(height: AppTheme.gap),
              const MutedText(
                'Saved on this phone. It will sync when online. Personal records appear once the backend has processed the workout.',
              ),
              const SizedBox(height: AppTheme.gap),
              AppButton.primary('Done', height: 56, onPressed: _exit),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, String> _exerciseNames() => {
    for (final e
        in ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[])
      e.id: e.name,
  };

  static String _setsLine(List<LoggedSet> sets) {
    final working = [
      for (final s in sets)
        if (s.isWorking) s,
    ];
    if (working.isEmpty){
      return sets.isEmpty ? 'No sets logged' : '${sets.length} warm-up sets';}
    return working
        .map(
          (s) =>
              '${s.weightKg == null ? '–' : _kgText(s.weightKg!)}×${s.reps ?? '–'}',
        )
        .join(' · ');
  }

  // ---- Active workout ----

  Widget _activeView(SessionDetail detail) {
    final session = detail.session;
    final names = _exerciseNames();
    final exercises = detail.exercises;
    if (_exercise >= exercises.length){
      _exercise = exercises.isEmpty ? 0 : exercises.length - 1;}
    final current = exercises.isEmpty ? null : exercises[_exercise];
    _endOrphanPause(session);
    final paused = _pausedAt != null;

    final subtitle =
        exercises.isEmpty
            ? '${_clock(_elapsed(session))}${paused ? ' · paused' : ''}'
            : 'Exercise ${_exercise + 1} of ${exercises.length} · ${_clock(_elapsed(session))}${paused ? ' · paused' : ''}';

    return _shell(
      detail,
      canPop: false,
      title: session.name ?? 'Workout',
      subtitle: subtitle,
      [
        if (current == null)
          _addExerciseCard(session, names, empty: true)
        else
          ..._exerciseSection(detail, current, names),
        const SizedBox(height: AppTheme.gap),
        if (current != null) _addExerciseCard(session, names),
        const SizedBox(height: AppTheme.gap),
        TitledCard(
          title: 'Workout note',
          children: [
            FieldBox(
              key: ValueKey('note-${session.id}'),
              initial: session.notes ?? '',
              hint: 'How did it feel?',
              onChanged: (v) => _workoutNote = v,
            ),
            const SizedBox(height: 10),
            AppButton(
              'Save note',
              onPressed: _busy ? null : () => _saveNote(session.id),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.gap),
        TitledCard(
          title: 'Pause or finish',
          children: [
            AppButton(
              paused ? 'Resume workout' : 'Pause workout',
              onPressed:
                  _busy
                      ? null
                      : () => _run(
                        () => paused ? _resume(session) : _pause(session),
                      ),
            ),
            const SizedBox(height: 12),
            AppButton.primary(
              'Finish workout',
              height: 54,
              onPressed: _busy ? null : () => _finish(detail),
            ),
            const SizedBox(height: 12),
            const MutedText(
              'Sets are saved as you confirm them. Pausing stops the clock while this screen is open; leaving the screen ends the pause.',
              size: 14.5,
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _exerciseSection(
    SessionDetail detail,
    SessionExerciseDetail current,
    Map<String, String> names,
  ) {
    final p = context.pal;
    final exercises = detail.exercises;
    final session = detail.session;
    final ex = current.exercise;
    final name = names[ex.exerciseId] ?? 'Exercise';
    final library =
        ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[];
    final info =
        [
          for (final e in library)
            if (e.id == ex.exerciseId) e,
        ].firstOrNull;
    final previous =
        ref
            .watch(
              previousPerformanceProvider((
                exerciseId: ex.exerciseId,
                beforeSessionId: session.id,
              )),
            )
            .valueOrNull;

    final prescription = ex.prescription;
    final target =
        prescription == null ? null : _prescriptionText(prescription);
    final restSeconds = (prescription?['rest_s'] as num?)?.toInt() ?? 90;
    final prevWorking = previous?.workingSets ?? const <LoggedSet>[];

    final working = [
      for (final s in current.sets)
        if (s.isWorking) s,
    ];
    final warm = [
      for (final s in current.sets)
        if (!s.isWorking) s,
    ];
    final nextNumber = _warmup ? warm.length + 1 : working.length + 1;
    final prevForNext =
        !_warmup && nextNumber <= prevWorking.length
            ? prevWorking[nextNumber - 1]
            : null;
    final prefillKg =
        prevForNext?.weightKg == null ? null : _kgText(prevForNext!.weightKg!);
    final draftKey = ValueKey(
      'draft-${ex.id}-${current.sets.length}-$_setKey-$_warmup',
    );
    final nextName =
        _exercise + 1 < exercises.length
            ? names[exercises[_exercise + 1].exercise.exerciseId] ?? 'Next'
            : null;

    final rows = <Widget>[
      for (final s in [...warm, ...working])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _DoneSetRow(
            label:
                s.isWorking
                    ? 'Working set ${s.setNumber}'
                    : 'Warm-up ${s.setNumber}',
            number: s.isWorking ? '${s.setNumber}' : 'W',
            text:
                '${s.weightKg == null ? '–' : _kgText(s.weightKg!)} kg × ${s.reps ?? '–'}${s.rir == null ? '' : ' · RIR ${s.rir}'}',
            onRemove: _busy ? null : () => _run(() => _service.deleteSet(s.id)),
          ),
        ),
    ];

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
              [
                if (target != null) target,
                'rest $restSeconds s',
                if (ex.isSkipped) 'skipped',
              ].join(' · '),
              style: TextStyle(color: p.muted, fontSize: 14.5),
            ),
            const SizedBox(height: 14),
            if (ex.isSkipped) ...[
              const MutedText(
                'This exercise is marked skipped. Log a set or restore it.',
              ),
              const SizedBox(height: 10),
              AppButton(
                'Restore exercise',
                onPressed:
                    _busy
                        ? null
                        : () => _run(() => _service.restoreExercise(ex.id)),
              ),
              const SizedBox(height: 14),
            ],
            ...rows,
            _DraftRow(
              key: draftKey,
              label:
                  _warmup
                      ? 'Warm-up $nextNumber · now'
                      : 'Working set $nextNumber · now',
              number: _warmup ? 'W' : '$nextNumber',
              previous:
                  prevForNext == null
                      ? 'No previous data'
                      : 'Previous ${prevForNext.weightKg == null ? '–' : _kgText(prevForNext.weightKg!)} × ${prevForNext.reps ?? '–'}',
              kg: _kg ?? prefillKg ?? '',
              reps: _reps,
              onKg: (v) => _kg = v,
              onReps: (v) => _reps = v,
              onConfirm:
                  _busy
                      ? null
                      : () => _confirmSet(
                        current,
                        restSeconds: restSeconds,
                        prefillKg: prefillKg,
                      ),
            ),
            const SizedBox(height: 12),
            PillTabs(
              labels: const ['Working', 'Warm-up'],
              index: _warmup ? 1 : 0,
              onChanged:
                  (i) => setState(() {
                    _warmup = i == 1;
                    _resetDraft();
                  }),
            ),
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
          LinkText(
            ex.isSkipped ? 'Exercise skipped' : 'Skip exercise',
            onTap: ex.isSkipped ? () {} : () => _skip(ex),
          ),
          LinkText(
            'Remove exercise',
            color: p.red,
            onTap: () => _removeExercise(ex),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const GroupLabel('Session tools'),
      const SizedBox(height: AppTheme.gap),
      TitledCard(
        title: 'Workout progress',
        children: [
          MeterBar(value: _progress(exercises)),
          const SizedBox(height: 12),
          MutedText(
            '${exercises.where((e) => e.sets.isNotEmpty || e.exercise.isSkipped).length} of ${exercises.length} exercises started · '
            '${detail.summary.workingSets} working sets · ${_kgText(detail.summary.volumeKg)} kg',
            size: 15,
          ),
        ],
      ),
      const SizedBox(height: AppTheme.gap),
      TitledCard(
        title: 'Set details',
        children: [
          const FieldLabel('RIR (reps in reserve) for the next working set'),
          PillTabs(
            labels: const ['–', '0', '1', '2', '3', '4+'],
            index: _rir == null ? 0 : (_rir! + 1).clamp(1, 5),
            onChanged:
                (i) =>
                    setState(() => _rir = i == 0 ? null : (i == 5 ? 4 : i - 1)),
          ),
          const SizedBox(height: 12),
          const FieldLabel('RPE (optional)'),
          PillTabs(
            labels: const ['–', '6', '7', '8', '9', '10'],
            index: _rpe == null ? 0 : (_rpe! - 5).round().clamp(1, 5),
            onChanged:
                (i) =>
                    setState(() => _rpe = i == 0 ? null : (i + 5).toDouble()),
          ),
        ],
      ),
      if (info?.notes != null && info!.notes!.trim().isNotEmpty) ...[
        const SizedBox(height: AppTheme.gap),
        TitledCard(
          title: 'Instructions',
          children: [MutedText(info.notes!, size: 15)],
        ),
      ],
    ];
  }

  double _progress(List<SessionExerciseDetail> exercises) {
    if (exercises.isEmpty) return 0;
    final started =
        exercises
            .where((e) => e.sets.isNotEmpty || e.exercise.isSkipped)
            .length;
    return started / exercises.length;
  }

  static String? _prescriptionText(Map<String, dynamic> p) {
    final sets = (p['target_sets'] as num?)?.toInt();
    final min = (p['rep_min'] as num?)?.toInt();
    final max = (p['rep_max'] as num?)?.toInt();
    if (sets == null) return null;
    if (min == null) return '$sets sets';
    return max == null || max == min ? '$sets × $min' : '$sets × $min–$max';
  }

  void _goTo(int index) => setState(() {
    _exercise = index;
    _restLeft = 0;
    _resetDraft();
  });

  Future<void> _skip(SessionExercise ex) async {
    await _run(() => _service.skipExercise(ex.id, reason: 'Skipped'));
  }

  Future<void> _removeExercise(SessionExercise ex) async {
    final choice = await _ask(
      title: 'Remove this exercise?',
      body: 'Any sets logged for it are removed too.',
      choices: const [
        ('Keep it', 'keep', ButtonKind.tonal),
        ('Remove', 'remove', ButtonKind.danger),
      ],
    );
    if (!mounted || choice != 'remove') return;
    await _run(() => _service.removeExercise(ex.id));
    if (mounted && _exercise > 0) setState(() => _exercise--);
  }

  Widget _addExerciseCard(
    WorkoutSession session,
    Map<String, String> names, {
    bool empty = false,
  }) {
    final library =
        ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[];
    return TitledCard(
      title: empty ? 'Add your first exercise' : 'Add exercise',
      children: [
        if (library.isEmpty)
          const MutedText(
            'No exercises on this phone yet. They appear after the first sync, or you can add one in Training › Exercises.',
          )
        else
          RowList([
            for (final e in library.take(empty ? 12 : 6))
              RowItem(
                title: e.name,
                subtitle: e.category,
                trailing: 'Add ›',
                onTap:
                    _busy
                        ? null
                        : () => _run(() async {
                          await _service.addExercise(session.id, e.id);
                          if (mounted) setState(() => _resetDraft());
                        }),
              ),
          ]),
      ],
    );
  }
}

class _DoneSetRow extends StatelessWidget {
  const _DoneSetRow({
    required this.label,
    required this.number,
    required this.text,
    this.onRemove,
  });

  final String label;
  final String number;
  final String text;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.tile,
        borderRadius: BorderRadius.circular(AppTheme.radius + 2),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.greenFill,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                color: p.green,
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
                  label,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(text, style: TextStyle(color: p.muted, fontSize: 14)),
              ],
            ),
          ),
          GestureDetector(
            key: Key('remove-set-$number-$label'),
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.close, size: 20, color: p.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    super.key,
    required this.label,
    required this.number,
    required this.previous,
    required this.kg,
    required this.reps,
    required this.onKg,
    required this.onReps,
    required this.onConfirm,
  });

  final String label;
  final String number;
  final String previous;
  final String kg;
  final String reps;
  final ValueChanged<String> onKg;
  final ValueChanged<String> onReps;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.bg.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radius + 2),
        border: Border.all(color: p.primary, width: 1.6),
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
                  color: p.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  number,
                  style: TextStyle(
                    color: p.onPrimary,
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
                      label,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      previous,
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
                  fieldKey: const Key('kg-field'),
                  initial: kg,
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
                  fieldKey: const Key('reps-field'),
                  initial: reps,
                  hint: 'reps',
                  keyboard: TextInputType.number,
                  onChanged: onReps,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                key: const Key('confirm-set'),
                onTap: onConfirm,
                child: Container(
                  width: 64,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.primary,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                  ),
                  child: Icon(Icons.check, size: 26, color: p.onPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
