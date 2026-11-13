import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/insights/insight_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/local_stamp.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/editor_sheet.dart';
import '../../../core/widgets/insight_status.dart';
import '../../../core/widgets/meters.dart';
import '../../progress/data/progress_insights.dart';
import '../../progress/data/progress_models.dart';
import '../../progress/data/progress_providers.dart';
import '../data/training_management_service.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';
import 'training_management_screens.dart';
import 'workout_session_screen.dart';

/// Training section: Overview, Splits, Exercises, History and Schedule. Everything is read from the phone (the local
/// copy of the training data). Plans (exercises, templates, splits, schedule) are changed through the management
/// service and workouts through the session service; both save on the phone first and sync later. Monthly totals are
/// the server's, read from the insight cache. A workout with no logged sets is shown but never counted.
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  static const _tabs = ['Overview', 'Splits', 'Exercises', 'History', 'Schedule'];
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
        return const [_ScheduleEditor(), _ScheduleWeek()];
      default:
        return const [_TodayCard(), _ThisWeek(), _QuickActions(), _RecentSessions(), _MonthTotals(), _ActiveSplit()];
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

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dateText(String localDate) {
  final d = DateTime.tryParse(localDate);
  return d == null ? localDate : '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}

/// "42 min", "under 1 min", or nothing when the length is unknown.
String _minutes(int? seconds) {
  if (seconds == null) return '';
  if (seconds < 60) return 'under 1 min';
  return '${(seconds / 60).round()} min';
}

String _datePlus(String localDate, int days) {
  final d = DateTime.parse(localDate);
  final n = DateTime.utc(d.year, d.month, d.day + days);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${n.year.toString().padLeft(4, '0')}-${two(n.month)}-${two(n.day)}';
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final active = ref.watch(activeSessionProvider).valueOrNull;
    final today = _today();
    final plan = ref.watch(todayPlanProvider(today)).valueOrNull ?? const TodayPlan();
    final entry = plan.entry;
    final template = plan.template;

    final String title;
    final String caption;
    if (active != null) {
      title = active.name ?? 'Workout in progress';
      caption = 'In progress · started ${_dateText(active.localDate)}';
    } else if (plan.hasPlan) {
      title = plan.title ?? 'Workout';
      caption = 'Today · ${_dateText(today)}';
    } else {
      title = 'No workout planned';
      caption = 'Today · ${_dateText(today)}';
    }

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(caption, style: TextStyle(color: p.muted, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text(title, style: TextStyle(color: p.text, fontSize: 24, fontWeight: FontWeight.w800)),
        if (template != null && active == null && !plan.isRest) ...[
          const SizedBox(height: 10),
          Text(template.name, style: TextStyle(color: p.muted, fontSize: 15)),
        ],
        if (!plan.hasPlan && active == null) ...[
          const SizedBox(height: 10),
          Text('Plan your week in the Schedule tab, or start an empty workout.', style: TextStyle(color: p.muted, fontSize: 15)),
        ],
        const SizedBox(height: 14),
        AppButton.primary(
          active != null ? 'Continue workout' : (plan.hasPlan && !plan.isRest ? 'Start workout' : 'Start an empty workout'),
          onPressed: () => startOrContinueWorkout(
            context,
            ref,
            templateVersionId: active == null && !plan.isRest ? template?.id : null,
            scheduleEntryId: entry?.id,
            splitVersionId: entry?.splitVersionId,
            splitDayId: entry?.splitDayId,
            name: plan.title,
          ),
        ),
      ]),
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
    final labels = ref.watch(splitDayLabelsProvider).valueOrNull ?? const <String, String>{};
    final entries = week ?? const <ScheduleEntry?>[];
    final planned = entries.whereType<ScheduleEntry>().where((e) => !e.isRestDay).toList();
    final done = planned.where((e) => e.status == 'completed').length;

    String label(ScheduleEntry e) => e.isRestDay ? 'Rest' : (labels[e.splitDayId] ?? 'Workout');

    Widget tile(int i, ScheduleEntry? e) {
      final isToday = week != null && i < 7 && _datePlus(_mondayOf(today), i) == today;
      final Widget badge = e?.status == 'completed'
          ? Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, color: p.greenFill), child: Icon(Icons.check, size: 16, color: p.green))
          : isToday
              ? Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, color: p.primary), child: Icon(Icons.play_arrow_rounded, size: 16, color: p.onPrimary))
              : Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.faint, width: 1.5)));
      return Expanded(
        child: InnerTile(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_weekdays[i], style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 4),
            SizedBox(
              height: 34,
              child: Text(e == null ? '–' : label(e), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            badge,
          ]),
        ),
      );
    }

    return TitledCard(title: 'This week', children: [
      if (week == null)
        const MutedText('Loading…')
      else ...[
        Row(children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            tile(i, entries[i]),
          ],
        ]),
        const SizedBox(height: 14),
        MeterBar(value: planned.isEmpty ? 0 : done / planned.length),
        const SizedBox(height: 10),
        MutedText(planned.isEmpty ? 'Nothing scheduled this week yet. Plan it in the Schedule tab.' : '$done / ${planned.length} workouts done'),
      ],
    ]);
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TitledCard(title: 'Quick actions', children: [
      AppButton('Start an empty workout', onPressed: () => startOrContinueWorkout(context, ref)),
      const SizedBox(height: 10),
      ButtonPair(
        AppButton('New split', onPressed: () => showSplitEditor(context)),
        AppButton('New template', onPressed: () => showTemplateEditor(context)),
      ),
      const SizedBox(height: 10),
      AppButton('Add an exercise', onPressed: () => showExerciseEditor(context)),
    ]);
  }
}

class _RecentSessions extends ConsumerWidget {
  const _RecentSessions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finished = ref.watch(finishedSessionsProvider).valueOrNull ?? const <({WorkoutSession session, bool counted})>[];
    final counted = [for (final f in finished) if (f.counted) f.session].take(3).toList();
    return TitledCard(title: 'Recent sessions', children: [
      if (counted.isEmpty)
        const MutedText('Finished workouts with logged sets show up here.')
      else
        RowList([for (final s in counted) _sessionRow(context, s, counted: true)]),
    ]);
  }
}

RowItem _sessionRow(BuildContext context, WorkoutSession s, {required bool counted}) {
  final seconds = s.endedAt == null ? null : s.endedAt!.difference(s.startedAt).inSeconds - s.pausedSeconds;
  return RowItem(
    title: s.name ?? 'Workout',
    subtitle: [_dateText(s.localDate), if (counted) _minutes(seconds) else 'No sets logged, not counted'].where((t) => t.isNotEmpty).join(' · '),
    chevron: true,
    onTap: () => showSessionDetail(context, s.id),
  );
}

/// This month's totals, calculated by the server from finished workouts that have logged working sets.
class _MonthTotals extends ConsumerWidget {
  const _MonthTotals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final prefix = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    final summaries = ref.watch(sessionSummariesProvider);
    final month = [for (final r in summaries.rows) if (r.counts && r.localDate.startsWith(prefix)) r];
    final volume = month.fold<double>(0, (a, r) => a + r.volumeKg);
    final seconds = month.fold<int>(0, (a, r) => a + (r.durationSeconds ?? 0));
    String duration() {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      return h > 0 ? '$h h $m m' : '$m m';
    }

    String kg(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)} t' : '${v.toStringAsFixed(0)} kg';
    final snap = summaries.snapshot;
    return TitledCard(title: '${_months[now.month - 1]} ${now.year} totals', children: [
      if (!snap.hasData)
        const MutedText('Monthly totals appear once they have loaded from the server.')
      else if (month.isEmpty)
        const MutedText('No finished workouts with logged sets this month yet.')
      else ...[
        Row(children: [
          Expanded(flex: 3, child: StatBlock(kg(volume), 'Volume')),
          Expanded(flex: 2, child: StatBlock('${month.length}', 'Workouts')),
          Expanded(flex: 3, child: StatBlock(duration(), 'Time')),
        ]),
        const SizedBox(height: 10),
        const MutedText('Counts finished workouts with at least one logged working set.'),
      ],
      InsightStatusLine(snapshot: snap, onRefresh: () => ref.read(insightProvider(sessionSummarySpec).notifier).refresh()),
    ]);
  }
}

class _ActiveSplit extends ConsumerWidget {
  const _ActiveSplit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final split = ref.watch(activeSplitProvider).valueOrNull;
    return TitledCard(title: split == null ? 'Active split' : 'Active split · ${split.name}', children: [
      if (split == null) ...[
        const MutedText('You are not following a split yet.'),
        const SizedBox(height: 10),
        AppButton('Create a split', onPressed: () => showSplitEditor(context)),
      ] else
        RowList([
          for (final d in split.days) RowItem(title: 'Day ${d.position} · ${d.isRest ? 'Rest' : d.label}'),
        ]),
    ]);
  }
}

// ---- Splits ----

class _YourSplits extends ConsumerWidget {
  const _YourSplits();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final splits = ref.watch(splitsProvider).valueOrNull ?? const <ActiveSplit>[];
    return TitledCard(title: 'Your splits', children: [
      if (splits.isEmpty)
        const MutedText('No splits yet. Create one with your training days, then make it active.')
      else
        RowList([
          for (final s in splits)
            RowItem(
              title: s.name,
              subtitle: '${s.days.length} days · ${s.pattern.replaceAll('_', ' ')}',
              trailing: s.status == 'active' ? 'Active' : (s.status == 'draft' ? 'Not active' : s.status[0].toUpperCase() + s.status.substring(1)),
              chevron: true,
              onTap: () => showSplitActions(context, s),
            ),
        ]),
      const SizedBox(height: 12),
      AppButton.primary('Create a split', onPressed: () => showSplitEditor(context)),
    ]);
  }
}

class _Templates extends ConsumerWidget {
  const _Templates();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(currentTemplatesProvider).valueOrNull ?? const <TemplateVersion>[];
    return TitledCard(title: 'Templates', children: [
      if (templates.isEmpty)
        const MutedText('No templates yet. A template is a list of exercises with sets and reps that a split day can use.')
      else
        RowList([
          for (final t in templates)
            RowItem(title: t.name, subtitle: 'Version ${t.version}', chevron: true, onTap: () => showTemplateEditor(context, templateId: t.templateId)),
        ]),
      const SizedBox(height: 12),
      AppButton.primary('New template', onPressed: () => showTemplateEditor(context)),
    ]);
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
  String? _group;
  String? _equipment;
  int _category = 0;
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[];
    final muscles = ref.watch(musclesProvider).valueOrNull ?? const <MuscleRef>[];
    final equipment = ref.watch(equipmentProvider).valueOrNull ?? const <EquipmentRef>[];
    final links = ref.watch(exerciseLinksProvider).valueOrNull ?? const <String, List<({String muscleId, String role})>>{};
    final groupOf = {for (final m in muscles) m.id: m.groupKey};
    final groups = {for (final m in muscles) m.groupKey}.toList()..sort();
    final q = _query.trim().toLowerCase();
    bool matches(Exercise e) {
      if (!_showInactive && e.isInactive) return false;
      if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
      if (_category == 1 && e.category != 'compound') return false;
      if (_category == 2 && e.category != 'isolation') return false;
      if (_equipment != null && e.equipmentId != _equipment) return false;
      if (_group != null && !(links[e.id] ?? const []).any((l) => groupOf[l.muscleId] == _group)) return false;
      return true;
    }

    final shown = [for (final e in all) if (matches(e)) e];
    final filtering = q.isNotEmpty || _category != 0 || _group != null || _equipment != null;
    return TitledCard(title: 'Exercise library', children: [
      const FieldLabel('Search'),
      FieldBox(hint: 'Search exercises', fieldKey: const Key('exercise-search'), onChanged: (v) => setState(() => _query = v)),
      const SizedBox(height: 10),
      PillTabs(labels: const ['All', 'Compound', 'Isolation'], index: _category, onChanged: (i) => setState(() => _category = i)),
      if (groups.isNotEmpty) ...[
        const SizedBox(height: 10),
        ChoiceWrap(options: [for (final g in groups) (g, '${g[0].toUpperCase()}${g.substring(1)}')], selected: {if (_group != null) _group!}, onToggle: (g) => setState(() => _group = _group == g ? null : g)),
      ],
      if (equipment.isNotEmpty) ...[
        const SizedBox(height: 10),
        ChoiceWrap(options: [for (final e in equipment) (e.id, e.label)], selected: {if (_equipment != null) _equipment!}, onToggle: (id) => setState(() => _equipment = _equipment == id ? null : id)),
      ],
      ToggleRow(title: 'Show exercises not in use', value: _showInactive, onChanged: (v) => setState(() => _showInactive = v)),
      const SizedBox(height: 4),
      if (shown.isEmpty)
        MutedText(all.isEmpty ? 'No exercises on this phone yet.' : (filtering ? 'No exercise matches. Clear the search or filters.' : 'No exercises to show.'))
      else
        RowList([
          for (final e in shown)
            RowItem(
              title: e.name,
              subtitle: [if (e.category != null) e.category!, if (e.isCustom) 'custom', if (e.isInactive) 'not in use'].join(' · '),
              chevron: true,
              onTap: () => showExerciseDetail(context, e.id),
            ),
        ]),
      const SizedBox(height: 12),
      AppButton.primary('Add an exercise', onPressed: () => showExerciseEditor(context)),
    ]);
  }
}

// ---- History ----

class _History extends ConsumerWidget {
  const _History();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finished = ref.watch(finishedSessionsProvider).valueOrNull ?? const <({WorkoutSession session, bool counted})>[];
    return TitledCard(title: 'History', children: [
      if (finished.isEmpty)
        const MutedText('Finished workouts show up here.')
      else ...[
        RowList([for (final f in finished) _sessionRow(context, f.session, counted: f.counted)]),
        if (finished.any((f) => !f.counted)) ...[
          const SizedBox(height: 10),
          const MutedText('Workouts with no logged sets are listed but not counted in your totals, streaks or records. Open one to discard it.'),
        ],
      ],
    ]);
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
    final names = {for (final e in ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[]) e.id: e.name};
    String kg(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    final counted = detail != null && detail.summary.workingSets > 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.cardPadding),
        child: detail == null
            ? const MutedText('This workout is not on this phone.')
            : ListView(shrinkWrap: true, children: [
                Text(detail.session.name ?? 'Workout', style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                MutedText('${_dateText(detail.session.localDate)} · ${detail.session.status == 'completed' ? 'Finished' : detail.session.status}'),
                const SizedBox(height: 14),
                if (!counted) ...[
                  const MutedText('No sets were logged in this workout, so it is not counted in your totals, streaks or records.'),
                  const SizedBox(height: 14),
                ] else ...[
                  Row(children: [
                    Expanded(child: StatBlock(_minutes(detail.summary.durationSeconds).isEmpty ? '–' : _minutes(detail.summary.durationSeconds), 'Duration')),
                    Expanded(child: StatBlock('${kg(detail.summary.volumeKg)} kg', 'Volume')),
                    Expanded(child: StatBlock('${detail.summary.workingSets}', 'Sets')),
                  ]),
                  const SizedBox(height: 10),
                ],
                if (detail.exercises.isNotEmpty)
                  RowList([
                    for (final e in detail.exercises)
                      RowItem(
                        title: names[e.exercise.exerciseId] ?? 'Exercise',
                        subtitle: e.exercise.isSkipped
                            ? 'Skipped'
                            : (e.sets.isEmpty ? 'No sets' : [for (final s in e.sets) if (s.isWorking) '${s.weightKg == null ? '–' : kg(s.weightKg!)}×${s.reps ?? '–'}'].join(' · ')),
                      ),
                  ]),
                if (detail.session.postNotes != null && detail.session.postNotes!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  MutedText(detail.session.postNotes!),
                ],
                const SizedBox(height: 14),
                if (!detail.session.isActive)
                  AppButton('Discard this workout', kind: ButtonKind.danger, onPressed: () async {
                    final sure = await askChoice(context,
                        title: 'Discard this workout?',
                        body: counted ? 'Its sets are removed from your history and records. This cannot be undone.' : 'It has no sets, so nothing of yours is lost.',
                        choices: const [('keep', 'Keep it', ButtonKind.tonal), ('discard', 'Discard', ButtonKind.danger)]);
                    if (sure != 'discard') return;
                    await ref.read(workoutSessionServiceProvider).discardSession(sessionId);
                    if (context.mounted) Navigator.of(context).pop();
                  }),
              ]),
      ),
    );
  }
}

// ---- Schedule ----

/// The next two weeks, one row per day. Tap a day to plan it, mark it as rest, or clear it.
class _ScheduleEditor extends ConsumerWidget {
  const _ScheduleEditor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = _today();
    final monday = _mondayOf(today);
    final to = _datePlus(monday, 13);
    final entries = ref.watch(scheduleRangeProvider((from: monday, to: to))).valueOrNull ?? const <ScheduleEntry>[];
    final labels = ref.watch(splitDayLabelsProvider).valueOrNull ?? const <String, String>{};
    final split = ref.watch(activeSplitProvider).valueOrNull;
    final byDate = {for (final e in entries) e.localDate: e};
    final rows = <Widget>[];
    for (var i = 0; i < 14; i++) {
      final date = _datePlus(monday, i);
      final e = byDate[date];
      final title = '${_dateText(date)}${date == today ? ' · today' : ''}';
      final String subtitle;
      String? trailing;
      if (e == null) {
        subtitle = 'Nothing planned';
      } else if (e.isRestDay) {
        subtitle = 'Rest day';
      } else {
        subtitle = labels[e.splitDayId] ?? 'Workout';
        trailing = '${e.status[0].toUpperCase()}${e.status.substring(1)}';
      }
      rows.add(RowItem(
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        trailingColor: e?.status == 'skipped' ? p.amber : null,
        chevron: true,
        onTap: () => showScheduleDaySheet(context, date, _dateText(date)),
      ));
    }
    return TitledCard(title: 'Schedule', children: [
      RowList(rows),
      const SizedBox(height: 12),
      if (split == null)
        const MutedText('Make a split active in the Splits tab to fill the schedule from it.')
      else
        AppButton.primary('Plan 4 weeks from "${split.name}"', onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            final n = await ref.read(trainingManagementServiceProvider).planFromSplit(split, today, 28);
            messenger.showSnackBar(SnackBar(content: Text(n == 0 ? 'Those days are already planned.' : 'Planned $n days. Days that already had a plan were left alone.')));
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text(saveErrorText(e))));
          }
        }),
    ]);
  }
}

class _ScheduleWeek extends ConsumerWidget {
  const _ScheduleWeek();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = _today();
    final monday = _mondayOf(today);
    final week = ref.watch(scheduleWeekProvider(monday)).valueOrNull ?? const <ScheduleEntry?>[];
    String word(ScheduleEntry? e) {
      if (e == null) return '–';
      if (e.isRestDay) return 'Rest';
      return switch (e.status) {
        'completed' => 'Done',
        'skipped' => 'Skip',
        _ => 'Planned',
      };
    }

    return TitledCard(title: 'Schedule · this week', children: [
      Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(builder: (_) {
              final isToday = _datePlus(monday, i) == today;
              final e = i < week.length ? week[i] : null;
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: isToday ? p.primary : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Text(_weekdays[i], style: TextStyle(color: isToday ? p.onPrimary : p.muted, fontSize: 12.5, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(word(e), style: TextStyle(color: isToday ? p.onPrimary : p.muted, fontSize: 11.5, fontWeight: isToday ? FontWeight.w700 : FontWeight.w400)),
                ]),
              );
            }),
          ),
      ]),
      const SizedBox(height: 14),
      const MutedText('Planned rest days and approved breaks do not count as missed.', size: 15),
    ]);
  }
}
