import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/section_widgets.dart';
import '../data/training_management_service.dart';
import '../data/training_providers.dart';
import '../data/workout_calendar.dart';
import 'training_format.dart';
import 'workout_session_screen.dart';

const _fullMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _key(int y, int m, int d) => '$y-${_two(m)}-${_two(d)}';

/// Opens the existing workout logger for [date]: edit when a workout is recorded there, today's normal workout for
/// today, otherwise a new workout for that day with the day's planned exercises loaded when there are any.
Future<void> openWorkoutForDate(BuildContext context, WidgetRef ref, String date) async {
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final today = todayDate();
  if (date.compareTo(today) > 0) {
    messenger.showSnackBar(
      const SnackBar(content: Text('You can only log today or an earlier day.')),
    );
    return;
  }
  try {
    final repo = ref.read(trainingRepositoryProvider);
    final day = (await repo.calendarDays(date, date, today))[date]!;
    if (day.status == WorkoutDayStatus.completed && day.sessionId != null) {
      await router.push(
        AppRoutes.session,
        extra: WorkoutLogArgs(
          selectedDate: date,
          mode: WorkoutLogMode.edit,
          sessionId: day.sessionId!,
        ),
      );
      return;
    }
    final plan = await ref.read(todayPlanProvider(date).future);
    final found = day.entry;
    final entry =
        found != null && !found.isRestDay && (found.status == 'planned' || found.status == 'skipped')
            ? found
            : null;
    if (date == today) {
      // Today keeps the normal live workout.
      if (!context.mounted) return;
      await startOrContinueWorkout(
        context,
        ref,
        templateVersionId: entry == null ? null : plan.template?.id,
        scheduleEntryId: entry?.id,
        splitVersionId: entry?.splitVersionId,
        splitDayId: entry?.splitDayId,
        name: entry == null ? null : plan.title,
      );
      return;
    }
    final id = await ref.read(workoutSessionServiceProvider).startHistoricalSession(
      date,
      name: entry == null ? null : plan.title,
      scheduleEntryId: entry?.id,
      splitVersionId: entry?.splitVersionId,
      splitDayId: entry?.splitDayId,
      templateVersionId: entry == null ? null : (plan.template?.id ?? entry.templateVersionId),
    );
    await router.push(
      AppRoutes.session,
      extra: WorkoutLogArgs(selectedDate: date, mode: WorkoutLogMode.create, sessionId: id),
    );
  } on ArgumentError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// Monthly view of workout history: green where a workout was recorded, red where a planned workout has no record,
/// blank for skipped, rest and unplanned days. It only shows history and picks a date; logging happens in the
/// existing workout screen.
class WorkoutCalendarScreen extends ConsumerStatefulWidget {
  const WorkoutCalendarScreen({super.key});

  @override
  ConsumerState<WorkoutCalendarScreen> createState() => _WorkoutCalendarScreenState();
}

class _WorkoutCalendarScreenState extends ConsumerState<WorkoutCalendarScreen> {
  late int _year;
  late int _month;
  String? _selected;

  @override
  void initState() {
    super.initState();
    final t = DateTime.parse(todayDate());
    _year = t.year;
    _month = t.month;
  }

  void _shift(int by) {
    final d = DateTime(_year, _month + by, 1);
    setState(() {
      _year = d.year;
      _month = d.month;
    });
  }

  Future<void> _markSkipped(String date) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(trainingManagementServiceProvider).markDaySkipped(date);
      messenger.showSnackBar(SnackBar(content: Text('${dateText(date)} marked as skipped.')));
    } on ManagementError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _longPress(String date, WorkoutDayStatus? status) async {
    if (status != WorkoutDayStatus.missing) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('skip-dialog'),
        title: Text('Skip ${dateText(date)}?'),
        content: const Text('Mark this planned workout as skipped instead of missing. You can still log it later.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            key: const Key('skip-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Mark skipped'),
          ),
        ],
      ),
    );
    if (yes == true) await _markSkipped(date);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final today = todayDate();
    final monthKey = '$_year-${_two(_month)}';
    final days = ref.watch(workoutCalendarProvider(monthKey)).valueOrNull ?? const <String, WorkoutCalendarDay>{};
    final first = DateTime(_year, _month, 1);
    final count = DateTime(_year, _month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= count; d++) {
      final date = _key(_year, _month, d);
      final status = days[date]?.status;
      cells.add(_DayCell(
        date: date,
        day: d,
        status: status,
        isToday: date == today,
        isSelected: date == _selected,
        isFuture: date.compareTo(today) > 0,
        onTap: () {
          setState(() => _selected = date);
          openWorkoutForDate(context, ref, date);
        },
        onLongPress: () => _longPress(date, status),
      ));
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox());
    }
    final rows = <Widget>[];
    for (var r = 0; r < cells.length; r += 7) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            for (var c = 0; c < 7; c++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: AspectRatio(aspectRatio: 1, child: cells[r + c]),
                ),
              ),
          ],
        ),
      ));
    }

    return ScreenFrame(
      title: 'Workout calendar',
      subtitle: 'Tap a day to log or edit',
      leading: HeaderIconButton(
        key: const Key('calendar-back'),
        icon: Icons.chevron_left,
        tooltip: 'Back',
        onTap: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.training);
          }
        },
      ),
      children: [
        AppCard(
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('calendar-prev'),
                    tooltip: 'Previous month',
                    onPressed: () => _shift(-1),
                    icon: Icon(Icons.chevron_left, color: p.text),
                  ),
                  Expanded(
                    child: Text(
                      '${_fullMonths[_month - 1]} $_year',
                      key: const Key('calendar-month'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.text, fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    key: const Key('calendar-next'),
                    tooltip: 'Next month',
                    onPressed: () => _shift(1),
                    icon: Icon(Icons.chevron_right, color: p.text),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final w in weekdayNames)
                    Expanded(
                      child: Text(
                        w,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ...rows,
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _Legend(color: p.green, label: 'Completed'),
                  _Legend(color: p.red, label: 'Missing workout log'),
                  _Legend(color: p.faint, label: 'Skipped or rest', hollow: true),
                ],
              ),
            ],
          ),
        ),
        const MutedText('Long-press a red day to mark it as skipped.', size: 13),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.day,
    required this.status,
    required this.isToday,
    required this.isSelected,
    required this.isFuture,
    required this.onTap,
    required this.onLongPress,
  });

  final String date;
  final int day;
  final WorkoutDayStatus? status;
  final bool isToday;
  final bool isSelected;
  final bool isFuture;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Color? fill;
    var text = isFuture ? p.faint : p.text;
    switch (status) {
      case WorkoutDayStatus.completed:
        fill = p.green.withValues(alpha: 0.22);
        text = p.green;
      case WorkoutDayStatus.missing:
        fill = p.red.withValues(alpha: 0.18);
        text = p.red;
      default:
        break;
    }
    final border = isSelected
        ? Border.all(color: p.link, width: 2)
        : (isToday ? Border.all(color: p.primary, width: 1.5) : null);
    return Semantics(
      label: '$date ${status?.name ?? 'none'}',
      child: InkWell(
        key: Key('cal-$date'),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            border: border,
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Text(
            '$day',
            style: TextStyle(
              color: text,
              fontSize: 15,
              fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.hollow = false});

  final Color color;
  final String label;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: hollow ? null : color.withValues(alpha: 0.35),
            border: hollow ? Border.all(color: color) : Border.all(color: color),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: p.muted, fontSize: 12.5)),
      ],
    );
  }
}
