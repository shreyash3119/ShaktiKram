import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/editor_sheet.dart';
import '../data/training_management_service.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';
import '../data/training_repository.dart';
import '../data/workout_session_service.dart';
import 'exercise_picker_screen.dart';
import 'training_format.dart';
import 'workout_templates_screen.dart';
import 'workout_widgets.dart';

/// What the person put together on the Workout start page, handed to the screen that creates the workout.
class WorkoutStartRequest {
  const WorkoutStartRequest({
    required this.exercises,
    this.name,
    this.scheduleEntryId,
    this.splitVersionId,
    this.splitDayId,
    this.templateVersionId,
    this.note = '',
  });

  final List<PlannedExercise> exercises;
  final String? name;
  final String? scheduleEntryId;
  final String? splitVersionId;
  final String? splitDayId;

  /// Only set when the list is still exactly the template's exercises.
  final String? templateVersionId;
  final String note;
}

class _Item {
  const _Item(this.exerciseId, {this.line});

  final String exerciseId;

  /// The template line this exercise came from; carries the sets and reps targets.
  final TemplateExercise? line;

  String? get target {
    final l = line;
    if (l == null) return null;
    final min = l.repMin, max = l.repMax;
    if (min == null) return '${l.targetSets} sets';
    return max == null || max == min
        ? '${l.targetSets} × $min'
        : '${l.targetSets} × $min–$max';
  }
}

String _rx(TemplateExercise l) =>
    _Item(l.exerciseId, line: l).target ?? '${l.targetSets} sets';

/// The Workout start page (Training > Start workout, and a day opened from the Workout Calendar): pick today's plan, a
/// split day, a template or a past session, or search exercises, adjust the list, then start. Nothing is written until
/// [onStart] is called, so leaving the page loses nothing.
class WorkoutBuilder extends ConsumerStatefulWidget {
  const WorkoutBuilder({
    super.key,
    required this.subtitle,
    required this.startLabel,
    required this.onBack,
    required this.onStart,
    this.date,
  });

  /// `YYYY-MM-DD` of the workout; today when null.
  final String? date;
  final String subtitle;

  /// "Start workout", or "Add to log" for a day from the calendar.
  final String startLabel;
  final VoidCallback onBack;
  final Future<void> Function(WorkoutStartRequest request) onStart;

  @override
  ConsumerState<WorkoutBuilder> createState() => _WorkoutBuilderState();
}

class _WorkoutBuilderState extends ConsumerState<WorkoutBuilder> {
  List<_Item> _items = [];
  String? _name;
  String? _scheduleEntryId;
  String? _splitVersionId;
  String? _splitDayId;
  String? _templateVersionId;
  List<String> _templateIds = const [];
  String _note = '';
  int _dayIndex = 0;
  bool _busy = false;

  String get _date => widget.date ?? todayDate();

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// Replaces the list with a template's exercises.
  Future<void> _loadTemplate(
    TemplateVersion template, {
    String? name,
    ScheduleEntry? entry,
    String? splitVersionId,
    String? splitDayId,
  }) async {
    final lines = await ref
        .read(trainingRepositoryProvider)
        .templateExercises(template.id);
    if (!mounted) return;
    setState(() {
      _items = [for (final l in lines) _Item(l.exerciseId, line: l)];
      _templateIds = [for (final l in lines) l.exerciseId];
      _templateVersionId = template.id;
      _name = name ?? template.name;
      _scheduleEntryId = entry?.id;
      _splitVersionId = splitVersionId ?? entry?.splitVersionId;
      _splitDayId = splitDayId ?? entry?.splitDayId;
    });
  }

  Future<void> _loadDay(ActiveSplit split, SplitDay day) async {
    final templateId = day.templateId;
    final template =
        templateId == null
            ? null
            : await ref
                .read(trainingRepositoryProvider)
                .currentVersionOfTemplate(templateId);
    if (!mounted) return;
    if (template == null) {
      _toast('This day has no template to load.');
      return;
    }
    await _loadTemplate(
      template,
      name: day.label.isEmpty ? template.name : day.label,
      splitVersionId: split.versionId,
      splitDayId: day.id,
    );
  }

  Future<void> _repeat(SessionDetail detail) async {
    final repo = ref.read(trainingRepositoryProvider);
    final items = <_Item>[];
    for (final e in detail.exercises) {
      if (e.exercise.isSkipped) continue;
      final lineId = e.exercise.templateExerciseId;
      // Keep the sets and reps targets when the old workout still has them.
      TemplateExercise? line;
      final versionId = detail.session.templateVersionId;
      if (lineId != null && versionId != null) {
        line =
            (await repo.templateExercises(versionId))
                .where((t) => t.id == lineId)
                .firstOrNull;
      }
      items.add(_Item(e.exercise.exerciseId, line: line));
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _templateIds = const [];
      _templateVersionId = null;
      _name = detail.session.name;
      _scheduleEntryId = null;
      _splitVersionId = null;
      _splitDayId = null;
    });
  }

  Future<void> _addExercises() async {
    final result = await pickExercises(
      context,
      selected: [for (final i in _items) i.exerciseId],
    );
    if (result == null || !mounted) return;
    final byId = {for (final i in _items) i.exerciseId: i};
    setState(() => _items = [for (final id in result) byId[id] ?? _Item(id)]);
  }

  Future<void> _useTemplate() async {
    final t = await pickTemplate(context);
    if (t != null && mounted) await _loadTemplate(t);
  }

  Future<void> _start() async {
    if (_busy) return;
    final ids = [for (final i in _items) i.exerciseId];
    final intact =
        _templateVersionId != null &&
        ids.length == _templateIds.length &&
        [for (var i = 0; i < ids.length; i++) ids[i] == _templateIds[i]]
            .every((same) => same);
    setState(() => _busy = true);
    try {
      await widget.onStart(
        WorkoutStartRequest(
          exercises: [
            for (final i in _items)
              PlannedExercise(i.exerciseId, templateExerciseId: i.line?.id),
          ],
          name: _name,
          scheduleEntryId: _scheduleEntryId,
          splitVersionId: _splitVersionId,
          splitDayId: _splitDayId,
          templateVersionId: intact ? _templateVersionId : null,
          note: _note,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveTemplate() async {
    if (_items.isEmpty) {
      _toast('Add at least one exercise first.');
      return;
    }
    final controller = TextEditingController(text: _name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final p = ctx.pal;
        return AlertDialog(
          backgroundColor: p.card,
          title: Text(
            'Save as template',
            style: TextStyle(color: p.text, fontWeight: FontWeight.w800),
          ),
          content: TextField(
            key: const Key('template-name'),
            controller: controller,
            autofocus: true,
            style: TextStyle(color: p.text),
            decoration: InputDecoration(
              hintText: 'Template name',
              hintStyle: TextStyle(color: p.muted),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: p.muted)),
            ),
            TextButton(
              key: const Key('template-save'),
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text('Save', style: TextStyle(color: p.link)),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || !mounted) return;
    try {
      await ref
          .read(trainingManagementServiceProvider)
          .createTemplate(
            name: name,
            exercises: [
              for (final i in _items)
                TemplateExerciseDraft(
                  exerciseId: i.exerciseId,
                  targetSets: i.line?.targetSets ?? 3,
                  repMin: i.line?.repMin,
                  repMax: i.line?.repMax,
                  restSeconds: i.line?.restSeconds,
                  startWeightKg: i.line?.startWeightKg,
                ),
            ],
          );
      if (mounted) _toast('Template saved.');
    } catch (e) {
      if (mounted) _toast(saveErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return WorkoutPageScaffold(
      header: WorkoutPageHeader(
        title: 'Workout',
        subtitle: widget.subtitle,
        onBack: widget.onBack,
      ),
      bottom: Row(
        children: [
          Expanded(
            flex: 5,
            child: AppButton(
              'Save template',
              key: const Key('save-template'),
              height: 56,
              onPressed: _busy ? null : _saveTemplate,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: AppButton.primary(
              _items.isEmpty
                  ? widget.startLabel
                  : '${widget.startLabel} · ${_items.length}',
              key: const Key('start-workout'),
              height: 56,
              onPressed: _busy ? null : _start,
            ),
          ),
        ],
      ),
      children: [
        _planCard(),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                key: const Key('open-templates'),
                icon: Icons.description_outlined,
                title: 'Templates',
                subtitle:
                    '${ref.watch(currentTemplatesProvider).valueOrNull?.length ?? 0} saved',
                onTap: _useTemplate,
              ),
            ),
            const SizedBox(width: AppTheme.gap),
            Expanded(
              child: _ActionTile(
                key: const Key('open-picker'),
                icon: Icons.add_circle_outline,
                title: 'Add exercise',
                subtitle:
                    'Search ${(ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[]).where((e) => !e.isInactive).length}',
                onTap: _addExercises,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.gap),
        _splitsCard(),
        _repeatCard(),
        _workoutCard(p),
      ],
    );
  }

  // ---- Today's plan ----

  Widget _planCard() {
    final p = context.pal;
    final plan = ref.watch(todayPlanProvider(_date)).valueOrNull;
    final template = plan?.template;
    if (plan == null || plan.isRest || template == null) {
      return const SizedBox.shrink();
    }
    final lines =
        ref.watch(templateExercisesProvider(template.id)).valueOrNull ??
        const <TemplateExercise>[];
    final names = {
      for (final e
          in ref.watch(exerciseLibraryProvider).valueOrNull ??
              const <Exercise>[])
        e.id: e.name,
    };
    final split = ref.watch(activeSplitProvider).valueOrNull;
    final day = plan.day;
    final isToday = _date == todayDate();
    final head = [
      isToday ? 'Today’s plan' : 'Plan for ${dateText(_date)}',
      if (day != null && split != null && split.versionId == plan.entry?.splitVersionId)
        'Day ${day.position} of ${split.days.length} · ${split.name}',
    ].join(' · ');
    final shown = lines.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gap),
      child: AppCard(
        color: p.tile,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(head, style: TextStyle(color: p.muted, fontSize: 15)),
            const SizedBox(height: 14),
            Text(
              plan.title ?? template.name,
              style: TextStyle(
                color: p.text,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            RowList([
              for (final l in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        names[l.exerciseId] ?? 'Exercise',
                        style: TextStyle(
                          color: p.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _rx(l),
                        style: TextStyle(color: p.muted, fontSize: 15),
                      ),
                    ],
                  ),
                ),
            ]),
            if (lines.length > shown.length) ...[
              const SizedBox(height: 4),
              Text(
                '+ ${lines.length - shown.length} more exercises',
                style: TextStyle(color: p.muted, fontSize: 15),
              ),
            ],
            const SizedBox(height: 16),
            AppButton.primary(
              isToday ? 'Use today’s plan' : 'Use this plan',
              key: const Key('use-plan'),
              height: 56,
              onPressed:
                  () => _loadTemplate(
                    template,
                    name: plan.title,
                    entry: plan.entry,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Splits ----

  Widget _splitsCard() {
    final p = context.pal;
    final active = ref.watch(activeSplitProvider).valueOrNull;
    final all = ref.watch(splitsProvider).valueOrNull ?? const <ActiveSplit>[];
    final others = [
      for (final s in all)
        if (active == null || s.splitId != active.splitId) s,
    ];
    if (active == null && others.isEmpty) return const SizedBox.shrink();
    final days = [
      if (active != null)
        for (final d in active.days)
          if (!d.isRest) d,
    ];
    if (_dayIndex >= days.length) _dayIndex = 0;
    final selected = days.isEmpty ? null : days[_dayIndex];
    String dayLabel(SplitDay d) => 'Day ${d.position} · ${d.label}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gap),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Your splits',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                LinkText(
                  'Manage ›',
                  onTap: () => context.go(AppRoutes.training),
                ),
              ],
            ),
            if (active != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      active.name,
                      style: TextStyle(color: p.text, fontSize: 19),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: p.tile,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Active',
                      style: TextStyle(color: p.link, fontSize: 14),
                    ),
                  ),
                ],
              ),
              if (days.isNotEmpty) ...[
                const SizedBox(height: 14),
                PillTabs(
                  labels: [for (final d in days) dayLabel(d)],
                  index: _dayIndex,
                  layout: PillLayout.scroll,
                  onChanged: (i) => setState(() => _dayIndex = i),
                ),
                const SizedBox(height: 14),
                AppButton(
                  'Use Day ${selected!.position}: ${selected.label}',
                  key: const Key('use-day'),
                  height: 56,
                  onPressed: () => _loadDay(active, selected),
                ),
              ],
            ],
            if (others.isNotEmpty) ...[
              if (active != null) ...[
                const SizedBox(height: 14),
                Divider(height: 1, thickness: 1, color: p.divider),
              ],
              RowItem(
                title: 'Other splits',
                subtitle: others.map((s) => s.name).join(', '),
                chevron: true,
                onTap: () => _chooseOtherSplit(others),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _chooseOtherSplit(List<ActiveSplit> others) async {
    final picked = await showModalBottomSheet<(ActiveSplit, SplitDay)>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: context.pal.bg,
      builder: (sheet) {
        final p = sheet.pal;
        return ListView(
          padding: const EdgeInsets.all(AppTheme.pagePadding),
          children: [
            Text(
              'Other splits',
              style: TextStyle(
                color: p.text,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            for (final s in others)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.gap),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      RowList([
                        for (final d in s.days)
                          if (!d.isRest)
                            RowItem(
                              title: 'Day ${d.position} · ${d.label}',
                              trailing: 'Use ›',
                              onTap: () => Navigator.of(sheet).pop((s, d)),
                            ),
                      ]),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
    if (picked != null && mounted) await _loadDay(picked.$1, picked.$2);
  }

  // ---- Repeat a past session ----

  Widget _repeatCard() {
    final p = context.pal;
    final finished =
        ref.watch(finishedSessionsProvider).valueOrNull ??
        const <({WorkoutSession session, bool counted})>[];
    final last = finished.where((s) => s.counted).firstOrNull?.session;
    if (last == null) return const SizedBox.shrink();
    final detail = ref.watch(sessionDetailProvider(last.id)).valueOrNull;
    final count = detail?.exercises.length;
    final minutes = minutesText(detail?.summary.durationSeconds);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gap),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Repeat a past session',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                LinkText(
                  'History ›',
                  onTap: () => context.go(AppRoutes.training),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        last.name ?? 'Workout',
                        style: TextStyle(
                          color: p.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          dateText(last.localDate),
                          if (count != null) '$count ${count == 1 ? 'exercise' : 'exercises'}',
                          if (minutes.isNotEmpty) minutes,
                        ].join(' · '),
                        style: TextStyle(color: p.muted, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                RowButton(
                  'Repeat',
                  key: const Key('repeat-session'),
                  onPressed: detail == null ? null : () => _repeat(detail),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- Your workout ----

  Widget _workoutCard(AppPalette p) {
    final names = {
      for (final e
          in ref.watch(exerciseLibraryProvider).valueOrNull ??
              const <Exercise>[])
        e.id: e.name,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _items.isEmpty
                ? 'Your workout'
                : 'Your workout · ${_items.length} ${_items.length == 1 ? 'exercise' : 'exercises'}',
            style: TextStyle(
              color: p.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            const MutedText(
              'Nothing here yet. Use a plan, template or past session above, or add exercises. You can also start empty and add exercises as you go.',
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (from, to) {
                setState(() {
                  if (to > from) to--;
                  final moved = _items.removeAt(from);
                  _items.insert(to, moved);
                });
              },
              children: [
                for (var i = 0; i < _items.length; i++)
                  _DraftRow(
                    key: ValueKey('draft-${_items[i].exerciseId}-$i'),
                    index: i,
                    name: names[_items[i].exerciseId] ?? 'Exercise',
                    item: _items[i],
                    onRemove: () => setState(() => _items.removeAt(i)),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          FieldBox(
            initial: _note,
            hint: 'Workout note: how did it feel?',
            textAlign: TextAlign.start,
            fieldKey: const Key('builder-note'),
            onChanged: (v) => _note = v,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.cardPadding),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: p.link, size: 32),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                color: p.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: p.muted, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _DraftRow extends ConsumerWidget {
  const _DraftRow({
    super.key,
    required this.index,
    required this.name,
    required this.item,
    required this.onRemove,
  });

  final int index;
  final String name;
  final _Item item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final previous =
        ref
            .watch(
              previousPerformanceProvider((
                exerciseId: item.exerciseId,
                beforeSessionId: null,
              )),
            )
            .valueOrNull;
    final set = previous?.workingSets.firstOrNull;
    final last =
        set == null || set.weightKg == null || set.reps == null
            ? null
            : 'last ${kgText(set.weightKg!)} kg × ${set.reps}';
    final sub = [if (item.target != null) item.target!, if (last != null) last].join(' · ');
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.divider)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(Icons.drag_handle, color: p.muted, size: 22),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(sub, style: TextStyle(color: p.muted, fontSize: 15)),
                ],
              ],
            ),
          ),
          IconButton(
            key: Key('remove-draft-$index'),
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: Icon(Icons.close, color: p.muted),
          ),
        ],
      ),
    );
  }
}
