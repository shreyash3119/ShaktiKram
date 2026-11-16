import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/insights/insight_providers.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/sync/change_writer.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/local_stamp.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/insight_status.dart';
import '../../../core/widgets/editor_sheet.dart';
import '../../../core/widgets/meters.dart';
import '../../lifestyle/data/lifestyle_models.dart';
import '../../lifestyle/data/lifestyle_providers.dart';
import '../../progress/data/progress_insights.dart';
import '../../progress/data/progress_models.dart';
import '../../progress/data/progress_providers.dart';
import '../../training/data/training_models.dart';
import '../../training/data/training_providers.dart';
import '../../training/data/training_repository.dart';
import '../../training/presentation/training_dialogs.dart';
import '../../training/presentation/workout_session_screen.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String dateLine(DateTime now) =>
    '${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}';

String _today() => localStampOf(DateTime.now()).localDate;

String _short(String localDate) {
  final d = DateTime.tryParse(localDate);
  return d == null ? localDate : '${_months[d.month - 1]} ${d.day}';
}

String _kg(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _words(String s) =>
    s.isEmpty
        ? s
        : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

/// Home is a composition of what the phone holds (today's plan, the running session, recent sessions, logs) and what
/// the server calculated (the daily briefing: readiness, deload, streak, trends). Server answers come from the
/// insight cache and say how old they are; nothing is recalculated here.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return ScreenFrame(
      title: greetingFor(now),
      subtitle: dateLine(now),
      trailing: const _HeaderButtons(),
      children: const [
        _TodayCard(),
        _QuickTiles(),
        _ReadinessAndConsistency(),
        _LifestyleCard(),
        _InsightsCard(),
        _FreshnessNote(),
      ],
    );
  }
}

/// Watches today's briefing and gives its freshness line for the cards that show server values.
class _FreshnessNote extends ConsumerWidget {
  const _FreshnessNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = _today();
    final snap = ref.watch(dailyBriefingProvider(today)).snapshot;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, right: 10),
            child: Icon(Icons.info_outline, size: 20, color: p.muted),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InsightStatusLine(
                  snapshot: snap,
                  onRefresh:
                      () =>
                          ref
                              .read(
                                insightProvider(dailyBriefingSpec(today))
                                    .notifier,
                              )
                              .refresh(),
                ),
                const SizedBox(height: 2),
                Text(
                  'Decision support only, not medical advice.',
                  style: TextStyle(color: p.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Header: notifications and refresh
// ---------------------------------------------------------------------------------------------------------------

/// What needs attention today. The bell on Home shows how many there are.
List<RowItem> _alertItems(
  WidgetRef ref, {
  VoidCallback? beforeNavigate,
  required BuildContext context,
}) {
  final active = ref.watch(activeSessionProvider).valueOrNull;
  final b = ref.watch(dailyBriefingProvider(_today())).briefing;
  return [
    if (active != null)
      RowItem(
        title: 'Unfinished session',
        subtitle: active.name ?? 'Workout in progress',
        trailing: 'Resume ›',
        onTap: () {
          beforeNavigate?.call();
          context.push(AppRoutes.session);
        },
      ),
    if (b != null && b.reassessmentDue)
      RowItem(
        title: 'Reassessment due',
        subtitle:
            b.nextReassessmentDate == null
                ? 'Muscle self-assessment'
                : 'Muscle self-assessment, ${_short(b.nextReassessmentDate!)}',
      ),
    if (b != null && b.restrictionWarnings.isNotEmpty)
      RowItem(
        title: 'Exercise restrictions',
        subtitle:
            '${b.restrictionWarnings.length} planned exercise(s) are affected by an injury or restriction',
      ),
    if (b != null && b.supplements.any((s) => s.takenToday < s.expectedDoses))
      const RowItem(
        title: 'Supplements',
        subtitle: 'Some doses are not logged yet today',
      ),
  ];
}

class _HeaderButtons extends ConsumerWidget {
  const _HeaderButtons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final count = _alertItems(ref, context: context).length;
    Widget button(Key key, IconData icon, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.divider),
              ),
              child: Icon(icon, color: p.text, size: 24),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            button(
              const Key('home-bell'),
              Icons.notifications_none,
              'Notifications',
              () => showDialog<void>(
                context: context,
                builder: (_) => const _AlertsDialog(),
              ),
            ),
            if (count > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  key: const Key('home-bell-badge'),
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 10),
        button(
          const Key('home-refresh'),
          Icons.sync,
          'Sync and refresh',
          () {
            ref.read(syncStatusProvider.notifier).syncNow();
            ref
                .read(insightProvider(dailyBriefingSpec(_today())).notifier)
                .refresh();
          },
        ),
      ],
    );
  }
}

class _AlertsDialog extends ConsumerWidget {
  const _AlertsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = _alertItems(
      ref,
      context: context,
      beforeNavigate: () => Navigator.of(context).pop(),
    );
    return ModalCard(
      title: 'Notifications',
      child:
          items.isEmpty
              ? const MutedText('Nothing needs attention.')
              : RowList(items),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Today card and its status
// ---------------------------------------------------------------------------------------------------------------

enum _DayState { none, rest, skipped, inProgress, completed }

class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = _today();
    final active = ref.watch(activeSessionProvider).valueOrNull;
    final plan =
        ref.watch(todayPlanProvider(today)).valueOrNull ?? const TodayPlan();
    final finishedToday = [
      for (final f
          in ref.watch(finishedSessionsProvider).valueOrNull ??
              const <({WorkoutSession session, bool counted})>[])
        if (f.session.localDate == today) f,
    ];
    final briefing = ref.watch(dailyBriefingProvider(today)).briefing;

    final entry = plan.entry;
    final _DayState state;
    if (active != null) {
      state = _DayState.inProgress;
    } else if (entry?.status == 'completed' || finishedToday.isNotEmpty) {
      state = _DayState.completed;
    } else if (entry?.status == 'skipped') {
      state = _DayState.skipped;
    } else if (plan.isRest) {
      state = _DayState.rest;
    } else {
      state = _DayState.none;
    }

    Future<void> start({bool linkEntry = true}) => startOrContinueWorkout(
      context,
      ref,
      templateVersionId: active == null ? plan.template?.id : null,
      scheduleEntryId:
          linkEntry && entry != null && !plan.isRest ? entry.id : null,
      splitVersionId: plan.entry?.splitVersionId,
      splitDayId: plan.entry?.splitDayId,
      name: plan.title,
    );

    final (String label, IconData? icon, Color fg, Color bg) = switch (state) {
      _DayState.none => ('Set status', null, p.text, Colors.transparent),
      _DayState.rest => ('Rest', Icons.nightlight_outlined, p.link, p.link.withValues(alpha: 0.16)),
      _DayState.skipped => ('Skipped', Icons.skip_next_outlined, p.amber, p.amber.withValues(alpha: 0.16)),
      _DayState.inProgress => ('In progress', Icons.play_arrow_outlined, p.link, p.link.withValues(alpha: 0.16)),
      _DayState.completed => ('Completed', Icons.check, p.green, p.greenFill),
    };

    final String title;
    final List<Widget> body;
    switch (state) {
      case _DayState.none:
        final planned = briefing?.plan.plannedExercises;
        title =
            entry?.status == 'rescheduled'
                ? 'Moved to tomorrow'
                : (plan.hasPlan ? (plan.title ?? 'Workout') : 'No workout planned');
        body = [
          if (planned != null && planned > 0 && plan.hasPlan)
            _muted(p, '$planned exercises planned'),
          const SizedBox(height: 4),
          AppButton.primary('Start workout', height: 58, onPressed: start),
          const SizedBox(height: 12),
          Center(
            child: LinkText(
              'Open Training ›',
              onTap: () => context.go(AppRoutes.training),
            ),
          ),
        ];
      case _DayState.rest:
        title = 'Rest day';
        body = [
          _muted(p, 'Planned rest days don’t count as missed.'),
          const SizedBox(height: 14),
          AppButton(
            'Start a workout anyway',
            onPressed: () => start(linkEntry: false),
          ),
          const SizedBox(height: 14),
          Center(
            child: LinkText(
              'Change status',
              onTap: () => showTodayStatus(context, ref),
            ),
          ),
        ];
      case _DayState.skipped:
        title = 'Workout skipped';
        body = [
          _muted(p, 'Want to move it to tomorrow?'),
          const SizedBox(height: 14),
          AppButton.primary(
            'Plan for tomorrow',
            height: 58,
            onPressed: () => _moveToTomorrow(context, ref),
          ),
          const SizedBox(height: 10),
          AppButton('Start workout now', onPressed: start),
        ];
      case _DayState.inProgress:
        title = 'Workout in progress';
        body = [_InProgressBody(active: active!), ..._resume(start)];
      case _DayState.completed:
        title = 'Workout completed';
        final done = finishedToday.isEmpty ? null : finishedToday.first;
        body = [
          _muted(
            p,
            done == null
                ? 'Marked as done.'
                : (done.counted
                    ? '${done.session.name ?? 'Workout'} · saved on this phone'
                    : 'No sets were logged, so it doesn’t count in totals or streaks.'),
          ),
          if (done != null) ...[
            const SizedBox(height: 14),
            AppButton(
              'View workout',
              onPressed: () => showSessionDetail(context, done.session.id),
            ),
          ],
        ];
    }

    return AppCard(
      color: p.card,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Today · ${_dayName(today)}',
                  style: TextStyle(
                    color: p.muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              InkWell(
                key: const Key('home-status-pill'),
                onTap: () => showTodayStatus(context, ref),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          state == _DayState.none
                              ? p.divider
                              : fg.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: fg),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.expand_more, size: 20, color: fg),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            key: const Key('home-today-title'),
            style: TextStyle(
              color: p.text,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...body,
        ],
      ),
    );
  }

  static Widget _muted(AppPalette p, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: TextStyle(color: p.muted, fontSize: 16)),
  );

  static List<Widget> _resume(Future<void> Function({bool linkEntry}) start) => [
    const SizedBox(height: 14),
    AppButton.primary('Resume workout', height: 58, onPressed: start),
  ];
}

String _dayName(String localDate) {
  final d = DateTime.tryParse(localDate);
  if (d == null) return localDate;
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${names[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}

Future<void> _moveToTomorrow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(trainingManagementServiceProvider).moveDayToTomorrow(_today());
    messenger.showSnackBar(const SnackBar(content: Text('Moved to tomorrow.')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(saveErrorText(e))));
  }
}

/// "Push · 00:27:12 · exercise 1 of 2" with a progress bar, ticking every second.
class _InProgressBody extends ConsumerStatefulWidget {
  const _InProgressBody({required this.active});

  final WorkoutSession active;

  @override
  ConsumerState<_InProgressBody> createState() => _InProgressBodyState();
}

class _InProgressBodyState extends ConsumerState<_InProgressBody> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = widget.active;
    final secs =
        DateTime.now().difference(s.startedAt).inSeconds - s.pausedSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    final t = secs < 0 ? 0 : secs;
    final clock = '${two(t ~/ 3600)}:${two((t % 3600) ~/ 60)}:${two(t % 60)}';
    final detail = ref.watch(sessionDetailProvider(s.id)).valueOrNull;
    final exercises = [
      for (final e in detail?.exercises ?? const <SessionExerciseDetail>[])
        if (!e.exercise.isSkipped) e,
    ];
    final done = exercises.where((e) => e.sets.any((x) => x.isWorking)).length;
    final total = exercises.length;
    final position = total == 0 ? null : math.min(done + 1, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${s.name ?? 'Workout'} · $clock${position == null ? '' : ' · exercise $position of $total'}',
          key: const Key('home-progress-line'),
          style: TextStyle(color: p.muted, fontSize: 16),
        ),
        const SizedBox(height: 14),
        MeterBar(value: total == 0 ? 0 : done / total, trackColor: p.tile),
      ],
    );
  }
}

/// The "Today's status" dialog: Rest, Skipped, In progress or Completed.
Future<void> showTodayStatus(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (_) => _StatusDialog(outer: context, ref: ref),
  );
}

class _StatusDialog extends StatelessWidget {
  const _StatusDialog({required this.outer, required this.ref});

  final BuildContext outer;
  final WidgetRef ref;

  Future<void> _choose(BuildContext dialog, String id) async {
    final messenger = ScaffoldMessenger.of(outer);
    final today = _today();
    final active = await ref.read(trainingRepositoryProvider).activeSession();
    final plan = await ref.read(todayPlanProvider(today).future);
    if (dialog.mounted) Navigator.of(dialog).pop();
    if (!outer.mounted) return;
    final management = ref.read(trainingManagementServiceProvider);
    try {
      switch (id) {
        case 'rest':
        case 'skipped':
          if (active != null) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Finish or discard the running workout first.'),
              ),
            );
            return;
          }
          if (id == 'rest') {
            await management.setScheduleDay(today, rest: true);
          } else {
            await management.markDaySkipped(today);
          }
        case 'in_progress':
          await startOrContinueWorkout(
            outer,
            ref,
            templateVersionId: active == null ? plan.template?.id : null,
            scheduleEntryId:
                plan.entry != null && !plan.isRest ? plan.entry!.id : null,
            splitVersionId: plan.entry?.splitVersionId,
            splitDayId: plan.entry?.splitDayId,
            name: plan.title,
          );
        case 'completed':
          final service = ref.read(workoutSessionServiceProvider);
          if (active != null) {
            final sure = await askChoice(
              outer,
              title: 'Finish this workout?',
              body: 'Exercises with no sets will be marked not done.',
              choices: const [
                ('keep', 'Keep going', ButtonKind.tonal),
                ('finish', 'Finish', ButtonKind.primary),
              ],
            );
            if (sure == 'finish') await service.completeSession(active.id);
          } else {
            await service.completeWithoutSets(
              name: plan.title,
              templateVersionId: plan.template?.id,
              splitVersionId: plan.entry?.splitVersionId,
              splitDayId: plan.entry?.splitDayId,
            );
          }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(saveErrorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final current = _currentState();
    Widget option(
      String id,
      String title,
      String sub,
      IconData icon,
      Color fg,
      Color bg,
    ) {
      final selected = current == id;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          key: Key('status-$id'),
          onTap: () => _choose(context, id),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected ? p.link.withValues(alpha: 0.14) : null,
              borderRadius: BorderRadius.circular(AppTheme.radius),
              border: Border.all(
                color: selected ? p.link : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: fg.withValues(alpha: 0.4)),
                  ),
                  child: Icon(icon, color: fg),
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
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        sub,
                        style: TextStyle(color: p.muted, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check, color: p.text),
              ],
            ),
          ),
        ),
      );
    }

    return ModalCard(
      title: 'Today’s status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          option('rest', 'Rest', 'Planned day off', Icons.nightlight_outlined, p.link, p.tile),
          option('skipped', 'Skipped', 'Missed it, not rescheduled', Icons.skip_next_outlined, p.amber, p.amber.withValues(alpha: 0.16)),
          option('in_progress', 'In progress', 'Training right now', Icons.play_arrow_outlined, p.link, p.link.withValues(alpha: 0.2)),
          option('completed', 'Completed', 'Finished today’s workout', Icons.check, p.green, p.greenFill),
          const SizedBox(height: 8),
          MutedText(
            'Completed without logged sets won’t count in totals or streaks.',
            size: 15,
          ),
        ],
      ),
    );
  }

  String? _currentState() {
    final today = _today();
    final active = ref.read(activeSessionProvider).valueOrNull;
    if (active != null) return 'in_progress';
    final plan = ref.read(todayPlanProvider(today)).valueOrNull;
    final done =
        (ref.read(finishedSessionsProvider).valueOrNull ??
                const <({WorkoutSession session, bool counted})>[])
            .any((f) => f.session.localDate == today);
    if (plan?.entry?.status == 'completed' || done) return 'completed';
    if (plan?.entry?.status == 'skipped') return 'skipped';
    if (plan?.isRest == true) return 'rest';
    return null;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Quick tiles and their dialogs
// ---------------------------------------------------------------------------------------------------------------

class _QuickTiles extends ConsumerWidget {
  const _QuickTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    Widget tile(Key key, IconData icon, String label, VoidCallback onTap) =>
        Expanded(
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: p.divider),
                  ),
                  child: Icon(icon, color: p.link, size: 28),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(color: p.text, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile(
          const Key('quick-log-weight'),
          Icons.monitor_weight_outlined,
          'Log weight',
          () => showLogWeight(context),
        ),
        tile(
          const Key('quick-log-meal'),
          Icons.restaurant,
          'Log meal',
          () => context.go(AppRoutes.lifestyle),
        ),
        tile(
          const Key('quick-add-water'),
          Icons.water_drop_outlined,
          'Add water',
          () => showDialog<void>(
            context: context,
            builder: (_) => const _AddWaterDialog(),
          ),
        ),
        tile(
          const Key('quick-history'),
          Icons.history,
          'History',
          () => context.go(AppRoutes.training),
        ),
      ],
    );
  }
}

class _AddWaterDialog extends ConsumerWidget {
  const _AddWaterDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ModalCard(
      title: 'Add water',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final ml in const [250, 500, 750, 1000])
            SizedBox(
              width: 120,
              child: AppButton(
                '+$ml ml',
                key: Key('water-$ml'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.of(context).pop();
                  await ref.read(lifestyleServiceProvider).addWater(ml);
                  messenger.showSnackBar(
                    SnackBar(content: Text('Added $ml ml of water.')),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showLogWeight(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _LogWeightDialog());

class _LogWeightDialog extends ConsumerStatefulWidget {
  const _LogWeightDialog();

  @override
  ConsumerState<_LogWeightDialog> createState() => _LogWeightDialogState();
}

class _LogWeightDialogState extends ConsumerState<_LogWeightDialog> {
  String? _text;
  String? _error;

  Future<void> _save() async {
    final kg = double.tryParse((_text ?? '').trim().replaceAll(',', '.'));
    if (kg == null || kg < 20 || kg > 400) {
      setState(() => _error = 'Enter a weight between 20 and 400 kg.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(changeWriterProvider)
        .upsert('body_measurements', weightPayload(kg, DateTime.now()));
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Weight saved on this phone. It will sync when online.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final weights =
        ref.watch(measurementsProvider('weight')).valueOrNull ??
        const <BodyMeasurement>[];
    _text ??= weights.isEmpty ? '' : _kg(weights.first.value);
    return ModalCard(
      title: 'Log weight',
      subtitle: 'Saved with today’s date',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('kg'),
          FieldBox(
            fieldKey: const Key('quick-weight-field'),
            initial: _text!,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) => _text = v,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              key: const Key('quick-weight-note'),
              style: TextStyle(color: p.red, fontSize: 15),
            ),
          ],
          const SizedBox(height: 16),
          AppButton.primary(
            'Save',
            key: const Key('quick-weight-save'),
            height: 56,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Readiness and consistency
// ---------------------------------------------------------------------------------------------------------------

class _ReadinessAndConsistency extends StatelessWidget {
  const _ReadinessAndConsistency();

  @override
  Widget build(BuildContext context) {
    return const IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _ReadinessTile()),
          SizedBox(width: 12),
          Expanded(child: _ConsistencyTile()),
        ],
      ),
    );
  }
}

class _ReadinessTile extends ConsumerWidget {
  const _ReadinessTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final b = ref.watch(dailyBriefingProvider(_today())).briefing;
    final readiness = b?.readiness;
    final score = readiness?.wellnessScore;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Readiness',
            style: TextStyle(
              color: p.muted,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: InkWell(
              key: const Key('readiness-dial'),
              borderRadius: BorderRadius.circular(80),
              onTap:
                  readiness == null
                      ? null
                      : () => showDialog<void>(
                        context: context,
                        builder: (_) => const _ReadinessDialog(),
                      ),
              child: SizedBox(
                width: 112,
                height: 112,
                child: CustomPaint(
                  painter: _DialPainter(
                    fraction: score == null ? 0 : (score / 100).clamp(0, 1),
                    on: p.link,
                    off: p.divider,
                  ),
                  child: Center(
                    child: Text(
                      score == null ? '–' : score.toStringAsFixed(0),
                      style: TextStyle(
                        color: p.text,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              readiness == null ? 'No check-in yet' : _words(readiness.level),
              key: readiness == null ? null : const Key('readiness-level'),
              style: TextStyle(color: p.text, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 8),
          Center(
            child: LinkText(
              'Check in ›',
              onTap: () => context.go(AppRoutes.lifestyle),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.fraction, required this.on, required this.off});

  final double fraction;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    const ticks = 36;
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final lit = (fraction * ticks).round();
    for (var i = 0; i < ticks; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / ticks;
      final paint =
          Paint()
            ..color = i < lit ? on : off
            ..strokeWidth = 4
            ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r - 13),
        c + Offset(math.cos(a), math.sin(a)) * (r - 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.fraction != fraction || old.on != on || old.off != off;
}

class _ReadinessDialog extends ConsumerWidget {
  const _ReadinessDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final b = ref.watch(dailyBriefingProvider(_today())).briefing;
    final r = b?.readiness;
    final deload = b?.deload;
    return ModalCard(
      title: 'Readiness',
      subtitle: r == null ? null : _words(r.level),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r?.wellnessScore != null)
            Text(
              'Wellness score ${r!.wellnessScore!.toStringAsFixed(0)}',
              style: TextStyle(color: p.muted, fontSize: 15),
            ),
          for (final line in r?.reasoning ?? const <String>[]) ...[
            const SizedBox(height: 8),
            Text(
              line,
              style: TextStyle(color: p.text, fontSize: 15, height: 1.35),
            ),
          ],
          if (deload != null &&
              deload.level != 'none' &&
              deload.level != 'unknown') ...[
            const SizedBox(height: 14),
            Text(
              'Deload: ${_words(deload.level)}',
              style: TextStyle(
                color: p.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final line in deload.reasoning) ...[
              const SizedBox(height: 6),
              Text(line, style: TextStyle(color: p.muted, fontSize: 15)),
            ],
          ],
          const SizedBox(height: 12),
          MutedText(
            r?.note ?? 'Guidance from your own check-ins, not medical advice.',
            size: 14,
          ),
        ],
      ),
    );
  }
}

class _ConsistencyTile extends ConsumerWidget {
  const _ConsistencyTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final b = ref.watch(dailyBriefingProvider(_today())).briefing;
    final finished =
        ref.watch(finishedSessionsProvider).valueOrNull ??
        const <({WorkoutSession session, bool counted})>[];
    final d = DateTime.now();
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    String two(int n) => n.toString().padLeft(2, '0');
    String iso(DateTime x) => '${x.year}-${two(x.month)}-${two(x.day)}';
    final counted = {
      for (final f in finished)
        if (f.counted) f.session.localDate,
    };
    final first = iso(monday);
    final thisWeek =
        finished
            .where(
              (f) => f.counted && f.session.localDate.compareTo(first) >= 0,
            )
            .length;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    Widget stat(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: p.text, fontSize: 15)),
          ),
          Text(
            value,
            style: TextStyle(
              color: p.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Consistency',
            style: TextStyle(
              color: p.muted,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 7; i++)
                Builder(
                  builder: (_) {
                    final day = DateTime(monday.year, monday.month, monday.day + i);
                    final isToday = iso(day) == iso(d);
                    final did = counted.contains(iso(day));
                    return Container(
                      key: Key('week-day-$i'),
                      width: 24,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: did ? p.greenFill : p.tile,
                        borderRadius: BorderRadius.circular(9),
                        border:
                            isToday
                                ? Border.all(color: p.link, width: 2)
                                : null,
                      ),
                      child: Text(
                        letters[i],
                        style: TextStyle(
                          color: did ? p.green : (isToday ? p.text : p.muted),
                          fontSize: 12,
                          fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          stat('This week', '$thisWeek'),
          stat('Streak', b?.currentStreak == null ? '–' : '${b!.currentStreak}'),
          stat('Longest', b?.longestStreak == null ? '–' : '${b!.longestStreak}'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Lifestyle today (with the latest weight)
// ---------------------------------------------------------------------------------------------------------------

class _LifestyleCard extends ConsumerWidget {
  const _LifestyleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = _today();
    final s = ref.watch(daySummaryProvider(today)).valueOrNull;
    final weights =
        ref.watch(measurementsProvider('weight')).valueOrNull ??
        const <BodyMeasurement>[];
    final fats =
        ref.watch(measurementsProvider('body_fat')).valueOrNull ??
        const <BodyMeasurement>[];
    final w = weights.isEmpty ? null : weights.first;
    final f = fats.isEmpty ? null : fats.first;
    Widget tile(String label, String value, Key key) => Expanded(
      child: InnerTile(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: p.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final meals =
        '${s?.mealsEaten ?? 0}${(s?.mealsPlanned ?? 0) > 0 ? '/${s!.mealsPlanned}' : ''}';
    return TitledCard(
      title: 'Lifestyle today',
      link: 'Lifestyle',
      onLink: () => context.go(AppRoutes.lifestyle),
      children: [
        Row(
          children: [
            tile('Supplements', '${s?.supplementsTaken ?? 0}', const Key('tile-supplements')),
            const SizedBox(width: 8),
            tile('Meals', meals, const Key('tile-meals')),
            const SizedBox(width: 8),
            tile('Water', '${s?.waterMl ?? 0} ml', const Key('tile-water')),
            const SizedBox(width: 8),
            tile('Steps', s?.steps?.steps == null ? '–' : '${s!.steps!.steps}', const Key('tile-steps')),
          ],
        ),
        const SizedBox(height: 14),
        Divider(height: 1, color: p.divider),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w == null ? 'Weight' : 'Weight · ${_short(w.localDate)}',
                    style: TextStyle(color: p.muted, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: w == null ? '–' : '${_kg(w.value)} kg',
                          style: TextStyle(
                            color: p.text,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextSpan(
                          text: ' · body fat ${f == null ? '–' : '${_kg(f.value)} %'}',
                          style: TextStyle(color: p.muted, fontSize: 15),
                        ),
                      ],
                    ),
                    key: const Key('home-weight'),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 96,
              child: AppButton(
                '+ Log',
                key: const Key('home-weight-log'),
                height: 52,
                onPressed: () => showLogWeight(context),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Insights and muscle priority
// ---------------------------------------------------------------------------------------------------------------

List<RowItem> _insightRows(DailyBriefing? b) => [
  for (final t in (b?.trends ?? const <BriefingTrend>[])
      .where((t) => t.signal != 'insufficient_data')
      .take(3))
    RowItem(
      title: '${t.exercise}: ${_words(t.signal)}',
      subtitle:
          t.changePct == null
              ? 'Estimated 1RM, recent sessions'
              : 'Estimated 1RM ${t.changePct! >= 0 ? '+' : ''}${t.changePct!.toStringAsFixed(1)}% over recent sessions',
    ),
  for (final w in (b?.weakPoints ?? const <BriefingWeakPoint>[]).take(2))
    RowItem(
      title: '${_words(w.muscleKey)} gets little direct work',
      subtitle:
          '${w.directSets28d} direct sets in 4 weeks. Consider it if it fits your split.',
    ),
];

class _InsightsCard extends ConsumerWidget {
  const _InsightsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final result = ref.watch(dailyBriefingProvider(_today()));
    final b = result.briefing;
    final rows = _insightRows(b);
    Widget row({
      required Key key,
      required String title,
      required String subtitle,
      String? trailing,
      VoidCallback? onTap,
    }) => InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: p.tile,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.info_outline, color: p.link, size: 22),
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
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(subtitle, style: TextStyle(color: p.muted, fontSize: 15)),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: TextStyle(
                  color: p.link,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          row(
            key: const Key('home-insights'),
            title: 'Insights',
            subtitle:
                rows.isNotEmpty
                    ? rows.first.title
                    : (result.snapshot.hasData
                        ? 'Nothing to point out right now'
                        : 'Appears once the daily briefing has loaded'),
            onTap:
                rows.isEmpty
                    ? null
                    : () => showDialog<void>(
                      context: context,
                      builder:
                          (_) => ModalCard(
                            title: 'Insights',
                            child: RowList(rows),
                          ),
                    ),
          ),
          Divider(height: 1, color: p.divider),
          row(
            key: const Key('home-muscle-priority'),
            title: 'Muscle priority',
            subtitle:
                b?.reassessmentDue == true
                    ? 'Reassessment due. Rate your muscles'
                    : 'Rate your muscles to get priorities',
            trailing: 'Rate ›',
            onTap: () => context.go(AppRoutes.progress),
          ),
        ],
      ),
    );
  }
}

/// A weight entry as a `body_measurements` payload (append-only table). Dates follow the phone's local time.
Map<String, dynamic> weightPayload(double kg, DateTime now) {
  final local = now.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return {
    'occurred_at': now.toUtc().toIso8601String(),
    'local_date': '${local.year}-${two(local.month)}-${two(local.day)}',
    'tz_offset_minutes': local.timeZoneOffset.inMinutes,
    'measurement_type': 'weight',
    'value': kg,
    'source': 'manual',
  };
}

