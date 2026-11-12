import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/local_stamp.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/meters.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';
import 'workout_session_screen.dart';

/// Training section: Overview, Splits, Exercises, History and Schedule. Everything here is read from the phone
/// (the local copy of the training data); starting a workout is the only write, and it goes through the session
/// service. Editing splits, templates and the exercise library is not on this screen yet. Cards still showing
/// design-pass numbers are marked "Sample values".
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  static const _tabs = [
    'Overview',
    'Splits',
    'Exercises',
    'History',
    'Schedule',
  ];
  int _tab = 0;

  List<Widget> _content() {
    switch (_tab) {
      case 1:
        return const [_YourSplits(), _Templates()];
      case 2:
        return const [_ExerciseLibrary()];
      case 3:
        return const [_History()];
      case 4:
        return const [_ScheduleList(), _ScheduleWeek()];
      default:
        return const [
          _TodayCard(),
          _ThisWeek(),
          _QuickActions(),
          _RecentSessions(),
          _TrainingInsights(),
          _ActiveSplit(),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Training',
      subtitle: 'Splits, exercises and workouts',
      children: [
        PillTabs(
          labels: _tabs,
          index: _tab,
          container: true,
          layout: PillLayout.scroll,
          onChanged: (i) => setState(() => _tab = i),
        ),
        ..._content(),
      ],
    );
  }
}

String _today() => localStampOf(DateTime.now()).localDate;

/// Monday of the week that contains [localDate].
String _mondayOf(String localDate) {
  final d = DateTime.parse(localDate);
  final m = DateTime.utc(d.year, d.month, d.day - (d.weekday - 1));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${m.year.toString().padLeft(4, '0')}-${two(m.month)}-${two(m.day)}';
}

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
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dateText(String localDate) {
  final d = DateTime.tryParse(localDate);
  return d == null
      ? localDate
      : '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}

String _minutes(int? seconds) =>
    seconds == null ? '' : '${(seconds / 60).round()} min';

class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final active = ref.watch(activeSessionProvider).valueOrNull;
    final today = _today();
    final entry = ref.watch(scheduleWeekProvider(today)).valueOrNull?.first;
    final split = ref.watch(activeSplitProvider).valueOrNull;
    final day =
        split == null || entry?.splitDayId == null
            ? null
            : [
              for (final d in split.days)
                if (d.id == entry!.splitDayId) d,
            ].firstOrNull;
    final templates =
        ref.watch(currentTemplatesProvider).valueOrNull ??
        const <TemplateVersion>[];
    final template =
        entry?.templateVersionId == null
            ? null
            : [
              for (final t in templates)
                if (t.id == entry!.templateVersionId) t,
            ].firstOrNull;

    final String title;
    final String caption;
    if (active != null) {
      title = active.name ?? 'Workout in progress';
      caption = 'In progress · started ${_dateText(active.localDate)}';
    } else if (entry?.isRestDay == true) {
      title = 'Rest day';
      caption = 'Today · ${_dateText(today)}';
    } else if (day != null || template != null) {
      title =
          day?.label.isNotEmpty == true
              ? day!.label
              : (template?.name ?? 'Workout');
      caption = 'Today · ${_dateText(today)}';
    } else {
      title = 'No workout planned';
      caption = 'Today · ${_dateText(today)}';
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            style: TextStyle(
              color: p.muted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: p.text,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (template != null && active == null) ...[
            const SizedBox(height: 10),
            Text(template.name, style: TextStyle(color: p.muted, fontSize: 15)),
          ],
          const SizedBox(height: 14),
          AppButton.primary(
            active != null ? 'Continue workout' : 'Start workout',
            onPressed:
                () => startOrContinueWorkout(
                  context,
                  ref,
                  templateVersionId:
                      active == null && entry?.isRestDay != true
                          ? template?.id
                          : null,
                  scheduleEntryId: entry?.id,
                  splitVersionId: entry?.splitVersionId,
                  splitDayId: entry?.splitDayId,
                  name: day?.label ?? template?.name,
                ),
          ),
        ],
      ),
    );
  }
}

class _ThisWeek extends ConsumerWidget {
  const _ThisWeek();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = _today();
    final week = ref.watch(scheduleWeekProvider(_mondayOf(today))).valueOrNull;
    final split = ref.watch(activeSplitProvider).valueOrNull;
    final entries = week ?? const <ScheduleEntry?>[];
    final planned =
        entries.whereType<ScheduleEntry>().where((e) => !e.isRestDay).toList();
    final done = planned.where((e) => e.status == 'completed').length;

    String label(ScheduleEntry e) {
      if (e.isRestDay) return 'Rest';
      final d =
          split == null
              ? null
              : [
                for (final x in split.days)
                  if (x.id == e.splitDayId) x,
              ].firstOrNull;
      return d?.label ?? 'Workout';
    }

    Widget tile(int i, ScheduleEntry? e) {
      final isToday =
          week != null && i < 7 && _datePlus(_mondayOf(today), i) == today;
      final Widget badge =
          e?.status == 'completed'
              ? Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.greenFill,
                ),
                child: Icon(Icons.check, size: 16, color: p.green),
              )
              : isToday
              ? Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.primary,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 16,
                  color: p.onPrimary,
                ),
              )
              : Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: p.faint, width: 1.5),
                ),
              );
      return Expanded(
        child: InnerTile(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _weekdays[i],
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 34,
                child: Text(
                  e == null ? '–' : label(e),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              badge,
            ],
          ),
        ),
      );
    }

    return TitledCard(
      title: 'This week',
      children: [
        if (week == null)
          const MutedText('Loading…')
        else ...[
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                tile(i, entries[i]),
              ],
            ],
          ),
          const SizedBox(height: 14),
          MeterBar(value: planned.isEmpty ? 0 : done / planned.length),
          const SizedBox(height: 10),
          MutedText(
            planned.isEmpty
                ? 'Nothing scheduled this week yet.'
                : '$done / ${planned.length} workouts done',
          ),
        ],
      ],
    );
  }
}

String _datePlus(String localDate, int days) {
  final d = DateTime.parse(localDate);
  final n = DateTime.utc(d.year, d.month, d.day + days);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${n.year.toString().padLeft(4, '0')}-${two(n.month)}-${two(n.day)}';
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TitledCard(
      title: 'Quick actions',
      children: [
        AppButton(
          'Start an empty workout',
          onPressed: () => context.push(AppRoutes.session),
        ),
        const SizedBox(height: 10),
        const MutedText(
          'Editing splits, templates and exercises is coming in a later step.',
        ),
      ],
    );
  }
}

class _RecentSessions extends ConsumerWidget {
  const _RecentSessions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions =
        ref.watch(recentSessionsProvider).valueOrNull ??
        const <WorkoutSession>[];
    final done =
        [
          for (final s in sessions)
            if (s.status == 'completed') s,
        ].take(3).toList();
    return TitledCard(
      title: 'Recent sessions',
      children: [
        if (done.isEmpty)
          const MutedText('Finished workouts show up here.')
        else
          RowList([for (final s in done) _sessionRow(context, s)]),
      ],
    );
  }
}

RowItem _sessionRow(BuildContext context, WorkoutSession s) {
  final seconds =
      s.endedAt == null
          ? null
          : s.endedAt!.difference(s.startedAt).inSeconds - s.pausedSeconds;
  return RowItem(
    title: s.name ?? 'Workout',
    subtitle: [
      _dateText(s.localDate),
      _minutes(seconds),
    ].where((t) => t.isNotEmpty).join(' · '),
    chevron: true,
    onTap: () => showSessionDetail(context, s.id),
  );
}

class _TrainingInsights extends StatelessWidget {
  const _TrainingInsights();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Training insights',
      sample: true,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: StatBlock('12,430 kg', 'This month volume'),
            ),
            Expanded(flex: 2, child: StatBlock('3', 'Workouts done')),
            Expanded(flex: 3, child: StatBlock('3 h 45 m', 'Total duration')),
          ],
        ),
        SizedBox(height: 14),
        MutedText(
          'Monthly totals come from the backend and are added in a later step.',
        ),
      ],
    );
  }
}

class _ActiveSplit extends ConsumerWidget {
  const _ActiveSplit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(activeSplitProvider).valueOrNull;
    return TitledCard(
      title: split == null ? 'Active split' : 'Active split · ${split.name}',
      children: [
        if (split == null)
          const MutedText('No active split on this phone yet.')
        else
          RowList([
            for (final d in split.days)
              RowItem(
                title: 'Day ${d.position} · ${d.isRest ? 'Rest' : d.label}',
              ),
          ]),
      ],
    );
  }
}

// ---- Splits ----

class _YourSplits extends ConsumerWidget {
  const _YourSplits();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(activeSplitProvider).valueOrNull;
    return TitledCard(
      title: 'Your splits',
      children: [
        if (split == null)
          const MutedText('No active split on this phone yet.')
        else
          RowList([
            RowItem(
              title: split.name,
              subtitle:
                  '${split.days.length} days · ${split.pattern.replaceAll('_', ' ')}',
              trailing: 'Active',
            ),
          ]),
      ],
    );
  }
}

class _Templates extends ConsumerWidget {
  const _Templates();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates =
        ref.watch(currentTemplatesProvider).valueOrNull ??
        const <TemplateVersion>[];
    return TitledCard(
      title: 'Templates',
      children: [
        if (templates.isEmpty)
          const MutedText('No templates on this phone yet.')
        else
          RowList([
            for (final t in templates)
              RowItem(title: t.name, subtitle: 'Version ${t.version}'),
          ]),
      ],
    );
  }
}

// ---- Exercises ----

class _ExerciseLibrary extends ConsumerStatefulWidget {
  const _ExerciseLibrary();

  @override
  ConsumerState<_ExerciseLibrary> createState() => _ExerciseLibraryState();
}

class _ExerciseLibraryState extends ConsumerState<_ExerciseLibrary> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all =
        ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[];
    final q = _query.trim().toLowerCase();
    final shown =
        q.isEmpty
            ? all
            : [
              for (final e in all)
                if (e.name.toLowerCase().contains(q)) e,
            ];
    return TitledCard(
      title: 'Exercise library',
      children: [
        const FieldLabel('Search'),
        FieldBox(
          hint: 'Search exercises',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          MutedText(
            all.isEmpty
                ? 'No exercises on this phone yet.'
                : 'No exercise matches that search.',
          )
        else
          RowList([
            for (final e in shown)
              RowItem(
                title: e.name,
                subtitle: [
                  if (e.category != null) e.category!,
                  if (e.isCustom) 'custom',
                ].join(' · '),
              ),
          ]),
      ],
    );
  }
}

// ---- History ----

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions =
        ref.watch(recentSessionsProvider).valueOrNull ??
        const <WorkoutSession>[];
    final finished = [
      for (final s in sessions)
        if (s.status == 'completed') s,
    ];
    return TitledCard(
      title: 'History',
      children: [
        if (finished.isEmpty)
          const MutedText(
            'Finished workouts show up here. Compare sessions comes in a later step.',
          )
        else
          RowList([for (final s in finished) _sessionRow(context, s)]),
      ],
    );
  }
}

/// One finished session: its exercises, sets and totals, read from the phone.
void showSessionDetail(BuildContext context, String sessionId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.pal.card,
    builder: (_) => _SessionDetailSheet(sessionId: sessionId),
  );
}

class _SessionDetailSheet extends ConsumerWidget {
  const _SessionDetailSheet({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final detail = ref.watch(sessionDetailProvider(sessionId)).valueOrNull;
    final names = {
      for (final e
          in ref.watch(exerciseLibraryProvider).valueOrNull ??
              const <Exercise>[])
        e.id: e.name,
    };
    String kg(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.cardPadding),
        child:
            detail == null
                ? const MutedText('This workout is not on this phone.')
                : ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      detail.session.name ?? 'Workout',
                      style: TextStyle(
                        color: p.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    MutedText(_dateText(detail.session.localDate)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: StatBlock(
                            _minutes(detail.summary.durationSeconds).isEmpty
                                ? '–'
                                : _minutes(detail.summary.durationSeconds),
                            'Duration',
                          ),
                        ),
                        Expanded(
                          child: StatBlock(
                            '${kg(detail.summary.volumeKg)} kg',
                            'Volume',
                          ),
                        ),
                        Expanded(
                          child: StatBlock(
                            '${detail.summary.workingSets}',
                            'Sets',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    RowList([
                      for (final e in detail.exercises)
                        RowItem(
                          title: names[e.exercise.exerciseId] ?? 'Exercise',
                          subtitle:
                              e.exercise.isSkipped
                                  ? 'Skipped'
                                  : [
                                    for (final s in e.sets)
                                      if (s.isWorking)
                                        '${s.weightKg == null ? '–' : kg(s.weightKg!)}×${s.reps ?? '–'}',
                                  ].join(' · '),
                        ),
                    ]),
                  ],
                ),
      ),
    );
  }
}

// ---- Schedule ----

class _ScheduleList extends ConsumerWidget {
  const _ScheduleList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final monday = _mondayOf(_today());
    final week =
        ref.watch(scheduleWeekProvider(monday)).valueOrNull ??
        const <ScheduleEntry?>[];
    final split = ref.watch(activeSplitProvider).valueOrNull;
    final rows = <Widget>[];
    for (var i = 0; i < week.length; i++) {
      final e = week[i];
      if (e == null) continue;
      final d =
          split == null
              ? null
              : [
                for (final x in split.days)
                  if (x.id == e.splitDayId) x,
              ].firstOrNull;
      final label = e.isRestDay ? 'Rest day' : (d?.label ?? 'Workout');
      final status =
          e.isRestDay
              ? 'Rest'
              : '${e.status[0].toUpperCase()}${e.status.substring(1)}';
      rows.add(
        RowItem(
          title: '${_weekdays[i]} · $label',
          trailing: status,
          trailingColor: e.status == 'skipped' ? p.amber : null,
        ),
      );
    }
    return TitledCard(
      title: 'Schedule',
      children: [
        if (rows.isEmpty)
          const MutedText('Nothing is scheduled this week yet.')
        else
          RowList(rows),
      ],
    );
  }
}

class _ScheduleWeek extends ConsumerWidget {
  const _ScheduleWeek();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = _today();
    final monday = _mondayOf(today);
    final week =
        ref.watch(scheduleWeekProvider(monday)).valueOrNull ??
        const <ScheduleEntry?>[];
    String word(ScheduleEntry? e) {
      if (e == null) return '–';
      if (e.isRestDay) return 'Rest';
      return switch (e.status) {
        'completed' => 'Done',
        'skipped' => 'Skip',
        _ => 'Planned',
      };
    }

    return TitledCard(
      title: 'Schedule · this week',
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Builder(
                  builder: (_) {
                    final isToday = _datePlus(monday, i) == today;
                    final e = i < week.length ? week[i] : null;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isToday ? p.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _weekdays[i],
                            style: TextStyle(
                              color: isToday ? p.onPrimary : p.muted,
                              fontSize: 12.5,
                              fontWeight:
                                  isToday ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            word(e),
                            style: TextStyle(
                              color: isToday ? p.onPrimary : p.muted,
                              fontSize: 11.5,
                              fontWeight:
                                  isToday ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const MutedText(
          'Planned rest days and approved breaks do not count as missed.',
          size: 15,
        ),
      ],
    );
  }
}
