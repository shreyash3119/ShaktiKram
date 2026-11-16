import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/insights/insight_providers.dart';
import '../../../core/insights/insight_repository.dart' show InsightSnapshot;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/editor_sheet.dart';
import '../../../core/widgets/insight_status.dart' show ageText;
import '../../progress/data/progress_insights.dart';
import '../../progress/data/progress_providers.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';
import 'training_dialogs.dart';
import 'training_format.dart';
import 'training_management_screens.dart';
import 'workout_session_screen.dart';

export 'training_dialogs.dart' show showSessionDetail;

/// Training section: Overview, Splits, Exercises, History and Schedule. Everything is read from the phone (the local
/// copy of the training data). Plans (exercises, templates, splits, schedule) are changed through the management
/// service and workouts through the session service; both save on the phone first and sync later. Workout totals are
/// the server's, read from the insight cache. A workout with no logged sets is shown but never counted.
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

  void _goTo(int tab) => setState(() => _tab = tab);

  List<Widget> _content() {
    switch (_tab) {
      case 1:
        return const [_YourSplits(), _Templates()];
      case 2:
        return const [_ExerciseLibrary()];
      case 3:
        return const [_History()];
      case 4:
        return [
          const _ScheduleWeekCard(),
          _ScheduleSplitBanner(onOpenSplits: () => _goTo(1)),
          _ScheduleDays(onOpenSplits: () => _goTo(1)),
        ];
      default:
        return [
          _TodayCard(onOpenSchedule: () => _goTo(4)),
          const _ThisWeek(),
          const _ActiveSplit(),
          const _QuickActions(),
          const _RecentActivity(),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercises = _tab == 2;
    return ScreenFrame(
      title: exercises ? 'Exercises' : 'Training',
      subtitle:
          exercises
              ? 'Browse and search movements'
              : 'Splits, exercises and workouts',
      children: [
        PillTabs(
          labels: _tabs,
          index: _tab,
          container: true,
          layout: PillLayout.scroll,
          onChanged: _goTo,
        ),
        ..._content(),
      ],
    );
  }
}

/// A small icon tile next to a sentence: the "nothing here yet" line inside a card.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: p.tile,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.info_outline, size: 22, color: p.link),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              text,
              style: TextStyle(color: p.muted, fontSize: 16, height: 1.35),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: p.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------------------------------------------

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.onOpenSchedule});

  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final active = ref.watch(activeSessionProvider).valueOrNull;
    final today = todayDate();
    final plan =
        ref.watch(todayPlanProvider(today)).valueOrNull ?? const TodayPlan();
    final entry = plan.entry;
    final template = plan.template;
    final planned = plan.hasPlan && !plan.isRest;

    final String title;
    final String caption;
    if (active != null) {
      title = active.name ?? 'Workout in progress';
      caption = 'In progress · started ${dateText(active.localDate)}';
    } else if (plan.hasPlan) {
      title = plan.title ?? 'Workout';
      caption = 'Today · ${dateText(today)}';
    } else {
      title = 'No workout planned';
      caption = 'Today · ${dateText(today)}';
    }

    void start() => startOrContinueWorkout(
      context,
      ref,
      templateVersionId: active == null && !plan.isRest ? template?.id : null,
      scheduleEntryId: entry?.id,
      splitVersionId: entry?.splitVersionId,
      splitDayId: entry?.splitDayId,
      name: plan.title,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            caption,
            style: TextStyle(
              color: p.muted,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: p.text,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          if (template != null && active == null && !plan.isRest) ...[
            const SizedBox(height: 10),
            Text(template.name, style: TextStyle(color: p.muted, fontSize: 16)),
          ],
          if (!plan.hasPlan && active == null) ...[
            const SizedBox(height: 10),
            Text(
              'Plan your week in the Schedule tab, or start an empty workout.',
              style: TextStyle(color: p.text, fontSize: 17, height: 1.3),
            ),
          ],
          const SizedBox(height: 16),
          if (active != null)
            AppButton.primary('Continue workout', onPressed: start)
          else if (planned)
            AppButton.primary('Start workout', onPressed: start)
          else
            ButtonPair(
              AppButton.primary('Start empty workout', onPressed: start),
              AppButton('Go to Schedule', onPressed: onOpenSchedule),
            ),
        ],
      ),
    );
  }
}

enum _DayState { none, done, missed }

/// Which days of the week the person trained (green), planned a workout but did not (red), or neither. A day is done when
/// a workout with logged sets was finished on it. It is missed when it is past and a workout was planned and not done, or
/// the only workout on it has no logged sets.
Map<String, _DayState> _dayStates(
  List<ScheduleEntry?> week,
  List<({WorkoutSession session, bool counted})> finished,
  String today,
) {
  final counted = {
    for (final f in finished)
      if (f.counted) f.session.localDate,
  };
  final empty = {
    for (final f in finished)
      if (!f.counted) f.session.localDate,
  };
  final out = <String, _DayState>{};
  for (final e in week) {
    if (e == null) continue;
    final date = e.localDate;
    if (counted.contains(date) || e.status == 'completed') {
      out[date] = _DayState.done;
    } else if (date.compareTo(today) < 0 &&
        !e.isRestDay &&
        (e.status == 'planned' || e.status == 'skipped')) {
      out[date] = _DayState.missed;
    }
  }
  for (final d in counted) {
    out[d] = _DayState.done;
  }
  for (final d in empty) {
    if (d.compareTo(today) < 0 && out[d] != _DayState.done){
      out[d] = _DayState.missed;}
  }
  return out;
}

class _ThisWeek extends ConsumerWidget {
  const _ThisWeek();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = todayDate();
    final monday = mondayOf(today);
    final week = ref.watch(scheduleWeekProvider(monday)).valueOrNull;
    final finished =
        ref.watch(finishedSessionsProvider).valueOrNull ??
        const <({WorkoutSession session, bool counted})>[];
    final entries = week ?? const <ScheduleEntry?>[];
    final states = _dayStates(entries, finished, today);
    final planned =
        entries.whereType<ScheduleEntry>().where((e) => !e.isRestDay).toList();
    final doneCount =
        planned.where((e) => states[e.localDate] == _DayState.done).length;

    Widget tile(int i) {
      final date = datePlus(monday, i);
      final isToday = date == today;
      final state = states[date] ?? _DayState.none;
      final Color fill = switch (state) {
        _DayState.done => p.greenFill,
        _DayState.missed => p.red.withAlpha(46),
        _DayState.none => p.tile,
      };
      final Color ink = switch (state) {
        _DayState.done => p.green,
        _DayState.missed => p.red,
        _DayState.none => p.text,
      };
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: isToday ? Border.all(color: p.primary, width: 2) : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weekdayNames[i],
                style: TextStyle(
                  color: state == _DayState.none ? p.muted : ink,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${DateTime.parse(date).day}',
                style: TextStyle(
                  color: ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 18,
                child:
                    state == _DayState.done
                        ? Icon(Icons.check, size: 18, color: p.green)
                        : (state == _DayState.missed
                            ? Icon(Icons.close, size: 18, color: p.red)
                            : null),
              ),
            ],
          ),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            'This week',
            trailing: Text(
              weekRangeText(monday),
              style: TextStyle(color: p.muted, fontSize: 15),
            ),
          ),
          const SizedBox(height: 14),
          if (week == null)
            const MutedText('Loading…')
          else
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  tile(i),
                ],
              ],
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text('✓ Done', style: TextStyle(color: p.muted, fontSize: 15)),
              Text('✕ Missed', style: TextStyle(color: p.muted, fontSize: 15)),
              Text(
                planned.isEmpty
                    ? 'Nothing planned yet'
                    : '$doneCount of ${planned.length} planned done',
                style: TextStyle(color: p.muted, fontSize: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveSplit extends ConsumerWidget {
  const _ActiveSplit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final split = ref.watch(activeSplitProvider).valueOrNull;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            split == null ? 'Active split' : 'Active split · ${split.name}',
          ),
          const SizedBox(height: 10),
          if (split == null) ...[
            Text(
              'You are not following a split yet.',
              style: TextStyle(color: p.muted, fontSize: 17),
            ),
            const SizedBox(height: 14),
            AppButton(
              'Create a split',
              onPressed: () => showSplitEditor(context),
            ),
          ] else
            RowList([
              for (final d in split.days)
                RowItem(
                  title: 'Day ${d.position} · ${d.isRest ? 'Rest' : d.label}',
                ),
            ]),
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Quick actions'),
          const SizedBox(height: 14),
          ButtonPair(
            AppButton(
              'New template',
              onPressed: () => showTemplateEditor(context),
            ),
            AppButton(
              'Add exercise',
              onPressed: () => showExerciseEditor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Updated just now": how old the server's workout totals are. Tap to refresh.
class _SummaryStatus extends StatelessWidget {
  const _SummaryStatus({required this.snapshot, required this.onRefresh});
  final InsightSnapshot snapshot;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final age = ageText(snapshot.fetchedAt);
    final String text;
    var warn = false;
    if (snapshot.refreshing) {
      text = 'Updating…';
    } else if (snapshot.hasData) {
      warn = snapshot.error != null;
      text =
          snapshot.error == null
              ? 'Updated $age'
              : (snapshot.isOffline ? 'Offline · $age' : 'Not updated · $age');
    } else {
      warn = snapshot.error != null;
      text = snapshot.isOffline ? 'Offline' : 'Not loaded';
    }
    final color = warn ? p.amber : p.link;
    return InkWell(
      key: const Key('summary-status'),
      borderRadius: BorderRadius.circular(8),
      onTap: snapshot.refreshing ? null : onRefresh,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, size: 18, color: color),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: color, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _RecentActivity extends ConsumerWidget {
  const _RecentActivity();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finished =
        ref.watch(finishedSessionsProvider).valueOrNull ??
        const <({WorkoutSession session, bool counted})>[];
    final counted =
        [
          for (final f in finished)
            if (f.counted) f.session,
        ].take(3).toList();
    final snap = ref.watch(sessionSummariesProvider).snapshot;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            'Recent activity',
            trailing: _SummaryStatus(
              snapshot: snap,
              onRefresh:
                  () =>
                      ref
                          .read(insightProvider(sessionSummarySpec).notifier)
                          .refresh(),
            ),
          ),
          const SizedBox(height: 14),
          if (counted.isEmpty)
            const _EmptyNote(
              'Finished workouts with logged sets will show up here.',
            )
          else
            RowList([
              for (final s in counted) _sessionRow(context, s, counted: true),
            ]),
        ],
      ),
    );
  }
}

RowItem _sessionRow(
  BuildContext context,
  WorkoutSession s, {
  required bool counted,
}) {
  final seconds =
      s.endedAt == null
          ? null
          : s.endedAt!.difference(s.startedAt).inSeconds - s.pausedSeconds;
  return RowItem(
    title: s.name ?? 'Workout',
    subtitle: [
      dateText(s.localDate),
      if (counted) minutesText(seconds) else 'No sets logged, not counted',
    ].where((t) => t.isNotEmpty).join(' · '),
    chevron: true,
    onTap: () => showSessionDetail(context, s.id),
  );
}

// ---------------------------------------------------------------------------------------------------------------
// Splits
// ---------------------------------------------------------------------------------------------------------------

class _YourSplits extends ConsumerWidget {
  const _YourSplits();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final splits =
        ref.watch(splitsProvider).valueOrNull ?? const <ActiveSplit>[];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Your splits'),
          const SizedBox(height: 14),
          if (splits.isEmpty)
            const _EmptyNote(
              'No splits yet. Create one with your training days, then make it active.',
            )
          else
            RowList([
              for (final s in splits)
                RowItem(
                  title: s.name,
                  subtitle:
                      '${s.days.length} days · ${s.pattern.replaceAll('_', ' ')}',
                  trailing:
                      s.status == 'active'
                          ? 'Active'
                          : (s.status == 'draft'
                              ? 'Not active'
                              : s.status[0].toUpperCase() +
                                  s.status.substring(1)),
                  chevron: true,
                  onTap: () => showSplitActions(context, s),
                ),
            ]),
          const SizedBox(height: 14),
          AppButton.primary(
            'Create a split',
            onPressed: () => showSplitEditor(context),
          ),
        ],
      ),
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Templates'),
          const SizedBox(height: 14),
          if (templates.isEmpty)
            const _EmptyNote(
              'No templates yet. A template is a list of exercises with sets and reps that a split day can use.',
            )
          else
            RowList([
              for (final t in templates)
                RowItem(
                  title: t.name,
                  subtitle: 'Version ${t.version}',
                  chevron: true,
                  onTap:
                      () =>
                          showTemplateEditor(context, templateId: t.templateId),
                ),
            ]),
          const SizedBox(height: 14),
          AppButton.primary(
            'New template',
            onPressed: () => showTemplateEditor(context),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Exercises
// ---------------------------------------------------------------------------------------------------------------

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: selected ? p.primary : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? p.primary : p.divider),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? p.onPrimary : p.text,
              fontSize: 17,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge(this.category);
  final String category;

  @override
  Widget build(BuildContext context) {
    final compound = category == 'compound';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: compound ? const Color(0xFFC9DCFF) : const Color(0xFF8FE9CC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        compound ? 'Compound' : 'Isolation',
        style: TextStyle(
          color: compound ? const Color(0xFF1D4ED8) : const Color(0xFF065F46),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ExerciseLibrary extends ConsumerStatefulWidget {
  const _ExerciseLibrary();

  @override
  ConsumerState<_ExerciseLibrary> createState() => _ExerciseLibraryState();
}

class _ExerciseLibraryState extends ConsumerState<_ExerciseLibrary> {
  String _query = '';
  String? _group;
  bool _archived = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final all =
        ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[];
    final muscles =
        ref.watch(musclesProvider).valueOrNull ?? const <MuscleRef>[];
    final equipment =
        ref.watch(equipmentProvider).valueOrNull ?? const <EquipmentRef>[];
    final links =
        ref.watch(exerciseLinksProvider).valueOrNull ??
        const <String, List<({String muscleId, String role})>>{};
    final groupOf = {for (final m in muscles) m.id: m.groupKey};
    final labelOf = {for (final m in muscles) m.id: m.label};
    final equipmentOf = {for (final e in equipment) e.id: e.label};
    final groups =
        {
            for (final m in muscles) m.groupKey,
          }.where((g) => g.isNotEmpty).toList()
          ..sort();
    final q = _query.trim().toLowerCase();

    bool matches(Exercise e) {
      if (e.isInactive != _archived) return false;
      if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
      if (_group != null &&
          !(links[e.id] ?? const []).any((l) => groupOf[l.muscleId] == _group)){
        return false;}
      return true;
    }

    String subtitle(Exercise e) {
      final primary =
          (links[e.id] ?? const [])
              .where((l) => l.role == 'primary')
              .map((l) => labelOf[l.muscleId])
              .whereType<String>()
              .toList();
      return [
        if (primary.isNotEmpty) primary.first,
        if (e.equipmentId != null && equipmentOf[e.equipmentId] != null)
          equipmentOf[e.equipmentId]!,
      ].join(' • ');
    }

    final shown = [
      for (final e in all)
        if (matches(e)) e,
    ];
    String cap(String g) => '${g[0].toUpperCase()}${g.substring(1)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: FieldBox(
                hint: 'Search exercises…',
                fieldKey: const Key('exercise-search'),
                height: 64,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 12),
            Material(
              color: p.primary,
              shape: const StadiumBorder(),
              child: InkWell(
                key: const Key('exercise-new'),
                customBorder: const StadiumBorder(),
                onTap: () => showExerciseEditor(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 19,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, color: p.onPrimary),
                      const SizedBox(width: 6),
                      Text(
                        'New',
                        style: TextStyle(
                          color: p.onPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: _group == null && !_archived,
                onTap:
                    () => setState(() {
                      _group = null;
                      _archived = false;
                    }),
              ),
              for (final g in groups) ...[
                const SizedBox(width: 10),
                _FilterChip(
                  label: cap(g),
                  selected: _group == g,
                  onTap: () => setState(() => _group = _group == g ? null : g),
                ),
              ],
              const SizedBox(width: 10),
              _FilterChip(
                label: 'Archived',
                selected: _archived,
                onTap: () => setState(() => _archived = !_archived),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (shown.isEmpty)
          MutedText(
            all.isEmpty
                ? 'No exercises on this phone yet.'
                : (_archived
                    ? 'No archived exercises.'
                    : 'No exercise matches. Clear the search or filters.'),
          )
        else
          for (final e in shown) ...[
            InkWell(
              key: Key('exercise-${e.id}'),
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              onTap: () => showExerciseDetail(context, e.id),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: p.tile,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.fitness_center, color: p.muted),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.name,
                            style: TextStyle(
                              color: p.text,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (subtitle(e).isNotEmpty)
                            Text(
                              subtitle(e),
                              style: TextStyle(color: p.muted, fontSize: 15),
                            ),
                        ],
                      ),
                    ),
                    if (e.category == 'compound' ||
                        e.category == 'isolation') ...[
                      const SizedBox(width: 8),
                      _CategoryBadge(e.category!),
                    ],
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right, color: p.muted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------------------------------------------

const _periods = [
  (7, 'Last 7 days'),
  (30, 'Last 30 days'),
  (90, 'Last 90 days'),
  (0, 'All time'),
];

class _History extends ConsumerStatefulWidget {
  const _History();

  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final today = todayDate();
    final cutoff = _days == 0 ? '0000-00-00' : datePlus(today, -_days);
    final finished =
        ref.watch(finishedSessionsProvider).valueOrNull ??
        const <({WorkoutSession session, bool counted})>[];
    final summaries = ref.watch(sessionSummariesProvider);
    final rows = [
      for (final r in summaries.rows)
        if (r.counts && r.localDate.compareTo(cutoff) >= 0) r,
    ];
    final volume = rows.fold<double>(0, (a, r) => a + r.volumeKg);
    final countedDates = {
      for (final r in summaries.rows)
        if (r.counts) r.localDate,
      for (final f in finished)
        if (f.counted) f.session.localDate,
    };
    final streak = weekStreak(countedDates, today);
    final inPeriod = [
      for (final f in finished)
        if (f.session.localDate.compareTo(cutoff) >= 0) f,
    ];
    final hasStats = summaries.snapshot.hasData;

    Widget divider() => Container(width: 1, height: 56, color: p.divider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: StatBlock(
                        hasStats ? '${rows.length}' : '–',
                        'Workouts',
                      ),
                    ),
                    divider(),
                    Expanded(
                      child: StatBlock(
                        hasStats ? kgText(volume) : '–',
                        'Volume (kg)',
                      ),
                    ),
                    divider(),
                    Expanded(child: StatBlock('$streak wk', 'Streak')),
                  ],
                ),
              ),
              if (!hasStats) ...[
                const SizedBox(height: 10),
                _SummaryStatus(
                  snapshot: summaries.snapshot,
                  onRefresh:
                      () =>
                          ref
                              .read(
                                insightProvider(sessionSummarySpec).notifier,
                              )
                              .refresh(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent workouts',
                style: TextStyle(
                  color: p.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            PopupMenuButton<int>(
              key: const Key('history-period'),
              initialValue: _days,
              color: p.card,
              onSelected: (v) => setState(() => _days = v),
              itemBuilder:
                  (_) => [
                    for (final o in _periods)
                      PopupMenuItem(
                        value: o.$1,
                        child: Text(o.$2, style: TextStyle(color: p.text)),
                      ),
                  ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: p.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _periods.firstWhere((o) => o.$1 == _days).$2,
                      style: TextStyle(color: p.text, fontSize: 15),
                    ),
                    Icon(Icons.arrow_drop_down, color: p.text),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (inPeriod.isEmpty)
          const AppCard(child: _EmptyNote('Finished workouts show up here.'))
        else
          for (final f in inPeriod) ...[
            f.counted
                ? _CountedWorkoutCard(session: f.session)
                : _EmptyWorkoutCard(session: f.session),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: p.tile,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: p.muted),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: p.text,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountedWorkoutCard extends ConsumerWidget {
  const _CountedWorkoutCard({required this.session});
  final WorkoutSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final detail = ref.watch(sessionDetailProvider(session.id)).valueOrNull;
    final names = {
      for (final e
          in ref.watch(exerciseLibraryProvider).valueOrNull ??
              const <Exercise>[])
        e.id: e.name,
    };
    final lines = <String>[];
    if (detail != null) {
      for (final e in detail.exercises) {
        if (e.exercise.isSkipped) continue;
        final n = e.sets.where((s) => s.isWorking).length;
        if (n > 0){
          lines.add(
            '${names[e.exercise.exerciseId] ?? 'Exercise'} · $n ${n == 1 ? 'set' : 'sets'}',
          );}
      }
    }
    final seconds = detail?.summary.durationSeconds;
    return InkWell(
      key: Key('workout-${session.id}'),
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      onTap: () => showSessionDetail(context, session.id),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    session.name ?? 'Workout',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  dateText(session.localDate),
                  style: TextStyle(color: p.muted, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (seconds != null)
                  _InfoPill(icon: Icons.schedule, text: minutesText(seconds)),
                if (detail != null)
                  _InfoPill(
                    icon: Icons.fitness_center,
                    text: '${kgText(detail.summary.volumeKg)} kg',
                  ),
              ],
            ),
            if (lines.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(color: p.divider, height: 1),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final l in lines.take(3))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              l,
                              style: TextStyle(color: p.text, fontSize: 17),
                            ),
                          ),
                        if (lines.length > 3)
                          Text(
                            '+${lines.length - 3} more',
                            style: TextStyle(color: p.muted, fontSize: 15),
                          ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: p.muted),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyWorkoutCard extends ConsumerWidget {
  const _EmptyWorkoutCard({required this.session});
  final WorkoutSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    return Container(
      key: Key('empty-workout-${session.id}'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: p.amber.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  session.name ?? 'Workout',
                  style: TextStyle(
                    color: p.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                dateText(session.localDate),
                style: TextStyle(color: p.muted, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: p.amber.withAlpha(36),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: p.amber.withAlpha(110)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: p.amber),
                const SizedBox(width: 8),
                Text(
                  '0 sets · not counted',
                  style: TextStyle(
                    color: p.amber,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No logged sets. Open it to add sets, or dismiss it to clean up your history.',
            style: TextStyle(color: p.muted, fontSize: 16, height: 1.35),
          ),
          const SizedBox(height: 14),
          ButtonPair(
            AppButton(
              'Open',
              onPressed: () => showSessionDetail(context, session.id),
            ),
            AppButton(
              'Dismiss',
              kind: ButtonKind.danger,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await confirmDiscardSession(
                    context,
                    ref,
                    session.id,
                    counted: false,
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(saveErrorText(e))),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Schedule
// ---------------------------------------------------------------------------------------------------------------

/// This week as seven chips: a dot on days with a plan or a workout, a dash on days with nothing, today filled.
class _ScheduleWeekCard extends ConsumerWidget {
  const _ScheduleWeekCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = todayDate();
    final monday = mondayOf(today);
    final week =
        ref.watch(scheduleWeekProvider(monday)).valueOrNull ??
        const <ScheduleEntry?>[];
    final finished =
        ref.watch(finishedSessionsProvider).valueOrNull ??
        const <({WorkoutSession session, bool counted})>[];
    final active = {for (final f in finished) f.session.localDate};

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Schedule · this week'),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Builder(
                    builder: (_) {
                      final date = datePlus(monday, i);
                      final isToday = date == today;
                      final has =
                          (i < week.length && week[i] != null) ||
                          active.contains(date);
                      final ink = isToday ? p.onPrimary : p.muted;
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isToday ? p.primary : p.tile,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            Text(
                              weekdayNames[i],
                              style: TextStyle(
                                color: isToday ? p.onPrimary : p.muted,
                                fontSize: 15,
                                fontWeight:
                                    isToday ? FontWeight.w800 : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            has
                                ? Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ink,
                                  ),
                                )
                                : Text(
                                  '–',
                                  style: TextStyle(color: ink, fontSize: 15),
                                ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '● has activity · – nothing planned',
            style: TextStyle(color: p.muted, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

/// Without an active split: a prompt to activate one. With one: the split's name and a button to plan the next 4 weeks.
class _ScheduleSplitBanner extends ConsumerWidget {
  const _ScheduleSplitBanner({required this.onOpenSplits});
  final VoidCallback onOpenSplits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final split = ref.watch(activeSplitProvider).valueOrNull;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: p.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  split == null ? 'No split active' : 'Following ${split.name}',
                  style: TextStyle(
                    color: p.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  split == null
                      ? 'Activate one to plan your week.'
                      : 'Fill the next 4 weeks from it.',
                  style: TextStyle(color: p.muted, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: p.primary,
            shape: const StadiumBorder(),
            child: InkWell(
              key: const Key('schedule-split-action'),
              customBorder: const StadiumBorder(),
              onTap:
                  split == null
                      ? onOpenSplits
                      : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final n = await ref
                              .read(trainingManagementServiceProvider)
                              .planFromSplit(split, todayDate(), 28);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                n == 0
                                    ? 'Those days are already planned.'
                                    : 'Planned $n days. Days that already had a plan were left alone.',
                              ),
                            ),
                          );
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(saveErrorText(e))),
                          );
                        }
                      },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
                child: Text(
                  split == null ? 'Activate' : 'Plan 4 weeks',
                  style: TextStyle(
                    color: p.onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// This week, one row per day. Past days are dimmed; today has a button to log the workout. Tap a day to plan it.
class _ScheduleDays extends ConsumerWidget {
  const _ScheduleDays({required this.onOpenSplits});
  final VoidCallback onOpenSplits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = todayDate();
    final monday = mondayOf(today);
    final week =
        ref.watch(scheduleWeekProvider(monday)).valueOrNull ??
        const <ScheduleEntry?>[];
    final labels =
        ref.watch(splitDayLabelsProvider).valueOrNull ??
        const <String, String>{};
    final plan =
        ref.watch(todayPlanProvider(today)).valueOrNull ?? const TodayPlan();

    String describe(String date, ScheduleEntry? e) {
      if (e == null) return 'Nothing planned';
      if (e.isRestDay) return 'Rest day';
      final name =
          date == today && plan.title != null
              ? plan.title!
              : (labels[e.splitDayId] ?? 'Workout');
      return e.status == 'planned' ? name : '$name · ${e.status}';
    }

    final rows = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final date = datePlus(monday, i);
      final e = i < week.length ? week[i] : null;
      final isToday = date == today;
      final past = date.compareTo(today) < 0;
      final dim = past && (e == null || e.status == 'planned');
      final titleColor = dim ? p.muted : p.text;
      rows.add(
        InkWell(
          key: Key('schedule-day-$date'),
          borderRadius: BorderRadius.circular(20),
          onTap:
              () => showScheduleDay(context, date, onOpenSplits: onOpenSplits),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration:
                isToday
                    ? BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: p.primary, width: 1.5),
                    )
                    : null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${dateText(date)}${isToday ? ' · Today' : ''}',
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        describe(date, e),
                        style: TextStyle(
                          color: dim ? p.faint : p.muted,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isToday && plan.hasPlan && !plan.isRest)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Material(
                      color: p.primary,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        key: const Key('schedule-log-workout'),
                        customBorder: const StadiumBorder(),
                        onTap:
                            () => startOrContinueWorkout(
                              context,
                              ref,
                              templateVersionId: plan.template?.id,
                              scheduleEntryId: plan.entry?.id,
                              splitVersionId: plan.entry?.splitVersionId,
                              splitDayId: plan.entry?.splitDayId,
                              name: plan.title,
                            ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          child: Text(
                            '+ Log workout',
                            style: TextStyle(
                              color: p.onPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (past && e != null && e.isRestDay)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'Past rest day',
                      style: TextStyle(color: p.muted, fontSize: 15),
                    ),
                  ),
                Icon(Icons.chevron_right, color: p.muted),
              ],
            ),
          ),
        ),
      );
      if (i < 6){
        rows.add(
          Divider(color: p.divider, height: 1, indent: 14, endIndent: 14),
        );}
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'THIS WEEK',
            style: TextStyle(color: p.muted, fontSize: 15, letterSpacing: 1.2),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(children: rows),
        ),
      ],
    );
  }
}
