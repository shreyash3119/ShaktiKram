import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';
import 'training_exercise_screens.dart';
import 'workout_widgets.dart';

/// Exercises used in the latest finished workouts, newest first (for the "Recently used" row).
final recentExerciseIdsProvider = FutureProvider<List<String>>((ref) async {
  final sessions = await ref.watch(finishedSessionsProvider.future);
  final repo = ref.watch(trainingRepositoryProvider);
  final ids = <String>[];
  for (final s in sessions.take(8)) {
    for (final e in await repo.sessionExercises(s.session.id)) {
      if (!ids.contains(e.exerciseId)) ids.add(e.exerciseId);
      if (ids.length >= 8) return ids;
    }
  }
  return ids;
});

/// Opens the exercise picker. [selected] are the exercises already in the workout, in order. Returns the full list of
/// exercise ids the person ends up with (those kept plus those added), or null if they went back without pressing Done.
Future<List<String>?> pickExercises(
  BuildContext context, {
  required List<String> selected,
  String inWhat = 'in this workout',
}) => Navigator.of(context).push<List<String>>(
  MaterialPageRoute(
    builder: (_) => ExercisePickerScreen(selected: selected, inWhat: inWhat),
  ),
);

/// Search and filter the exercise library and add exercises to a workout.
class ExercisePickerScreen extends ConsumerStatefulWidget {
  const ExercisePickerScreen({
    super.key,
    required this.selected,
    this.inWhat = 'in this workout',
  });

  final List<String> selected;
  final String inWhat;

  @override
  ConsumerState<ExercisePickerScreen> createState() =>
      _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends ConsumerState<ExercisePickerScreen> {
  static const _firstPage = 5;
  static const _groupOrder = ['chest', 'back', 'shoulders', 'arms', 'legs', 'core'];

  late final List<String> _ids = [...widget.selected];
  final _search = TextEditingController();
  String _query = '';
  int _group = 0; // 0 = All
  int _equipment = 0; // 0 = any
  bool _ascending = true;
  bool _all = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _title(String key) =>
      key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

  void _toggle(String id) => setState(() {
    if (!_ids.remove(id)) _ids.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final library = [
      for (final e
          in ref.watch(exerciseLibraryProvider).valueOrNull ??
              const <Exercise>[])
        if (!e.isInactive) e,
    ];
    final muscles =
        ref.watch(musclesProvider).valueOrNull ?? const <MuscleRef>[];
    final equipment =
        ref.watch(equipmentProvider).valueOrNull ?? const <EquipmentRef>[];
    final links =
        ref.watch(exerciseLinksProvider).valueOrNull ??
        const <String, List<({String muscleId, String role})>>{};
    final recent =
        ref.watch(recentExerciseIdsProvider).valueOrNull ?? const <String>[];

    final muscleById = {for (final m in muscles) m.id: m};
    final groups = <String>{for (final m in muscles) m.groupKey}
      ..removeWhere((g) => g.isEmpty);
    final groupKeys =
        groups.toList()..sort((a, b) {
          final ia = _groupOrder.indexOf(a), ib = _groupOrder.indexOf(b);
          if (ia != ib) return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
          return a.compareTo(b);
        });
    final usedEquipment =
        equipment
            .where((q) => library.any((e) => e.equipmentId == q.id))
            .toList();
    if (_group > groupKeys.length) _group = 0;
    if (_equipment > usedEquipment.length) _equipment = 0;

    Set<String> primaryGroups(Exercise e) => {
      for (final l in links[e.id] ?? const <({String muscleId, String role})>[])
        if (l.role == 'primary' && muscleById[l.muscleId] != null)
          muscleById[l.muscleId]!.groupKey,
    };
    String detail(Exercise e) {
      final primary = [
        for (final l in links[e.id] ?? const <({String muscleId, String role})>[])
          if (l.role == 'primary' && muscleById[l.muscleId] != null)
            muscleById[l.muscleId]!.label,
      ];
      final eq = equipment.where((q) => q.id == e.equipmentId).firstOrNull;
      return [
        if (e.category != null && e.category!.isNotEmpty) _title(e.category!),
        if (primary.isNotEmpty) primary.take(2).join(', '),
        if (eq != null) eq.label,
      ].join(' · ');
    }

    final q = _query.trim().toLowerCase();
    final matches =
        library.where((e) {
            if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
            if (_group > 0 && !primaryGroups(e).contains(groupKeys[_group - 1])) {
              return false;
            }
            if (_equipment > 0 &&
                e.equipmentId != usedEquipment[_equipment - 1].id) {
              return false;
            }
            return true;
          }).toList()
          ..sort(
            (a, b) =>
                _ascending
                    ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
                    : b.name.toLowerCase().compareTo(a.name.toLowerCase()),
          );
    final shown = _all ? matches : matches.take(_firstPage).toList();
    final byId = {for (final e in library) e.id: e};

    Widget status(Exercise e) {
      final added = _ids.contains(e.id);
      if (!added) {
        return RowButton(
          'Add',
          key: Key('add-${e.id}'),
          onPressed: () => _toggle(e.id),
        );
      }
      return GestureDetector(
        key: Key('added-${e.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _toggle(e.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: p.greenFill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 15, color: p.green),
              const SizedBox(width: 4),
              Text(
                'Added',
                style: TextStyle(
                  color: p.green,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final recentExercises = [
      for (final id in recent)
        if (byId[id] != null) byId[id]!,
    ];

    return WorkoutPageScaffold(
      header: WorkoutPageHeader(
        title: 'Add exercise',
        subtitle: '${_ids.length} ${widget.inWhat}',
        onBack: () => Navigator.of(context).pop(),
      ),
      bottom: AppButton.primary(
        _ids.isEmpty ? 'Done' : 'Done · ${_ids.length} added',
        key: const Key('picker-done'),
        height: 56,
        onPressed: () => Navigator.of(context).pop(List<String>.of(_ids)),
      ),
      children: [
        TextField(
          key: const Key('picker-search'),
          controller: _search,
          onChanged:
              (v) => setState(() {
                _query = v;
                _all = false;
              }),
          style: TextStyle(
            color: p.text,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          cursorColor: p.primary,
          decoration: InputDecoration(
            hintText: 'Search ${library.length} exercises',
            hintStyle: TextStyle(color: p.muted, fontSize: 18),
            prefixIcon: Icon(Icons.search, color: p.muted, size: 26),
            filled: true,
            fillColor: p.tile,
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              borderSide: BorderSide(color: p.primary),
            ),
          ),
        ),
        const SizedBox(height: 12),
        PillTabs(
          labels: ['All', for (final g in groupKeys) _title(g)],
          index: _group,
          container: true,
          layout: PillLayout.scroll,
          onChanged:
              (i) => setState(() {
                _group = i;
                _all = false;
              }),
        ),
        if (usedEquipment.isNotEmpty) ...[
          const SizedBox(height: 10),
          PillTabs(
            labels: ['Any equipment', for (final e in usedEquipment) e.label],
            index: _equipment,
            container: true,
            layout: PillLayout.scroll,
            onChanged:
                (i) => setState(() {
                  _equipment = i;
                  _all = false;
                }),
          ),
        ],
        if (recentExercises.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Recently used', style: TextStyle(color: p.muted, fontSize: 15)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in recentExercises)
                    GestureDetector(
                      key: Key('recent-${e.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!_ids.contains(e.id)) _toggle(e.id);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Text(
                          e.name,
                          style: TextStyle(
                            color: _ids.contains(e.id) ? p.faint : p.muted,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppTheme.gap + 4),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      q.isEmpty
                          ? '${matches.length} exercises'
                          : '${shown.length} of ${matches.length} results for “${_query.trim()}”',
                      style: TextStyle(
                        color: p.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const Key('picker-sort'),
                    onTap: () => setState(() => _ascending = !_ascending),
                    child: Text(
                      _ascending ? 'A–Z ▾' : 'Z–A ▾',
                      style: TextStyle(
                        color: p.link,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (matches.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: MutedText(
                    library.isEmpty
                        ? 'No exercises on this phone yet. They appear after the first sync, or create one below.'
                        : 'No exercise matches. Try another word or filter.',
                  ),
                )
              else
                RowList([
                  for (final e in shown)
                    Padding(
                      key: Key('result-${e.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.name,
                                  style: TextStyle(
                                    color: p.text,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (detail(e).isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    detail(e),
                                    style: TextStyle(
                                      color: p.muted,
                                      fontSize: 14.5,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          status(e),
                        ],
                      ),
                    ),
                ]),
              if (!_all && matches.length > _firstPage) ...[
                const SizedBox(height: 8),
                AppButton(
                  'Show ${matches.length - _firstPage} more',
                  key: const Key('picker-more'),
                  onPressed: () => setState(() => _all = true),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppTheme.gap),
        GestureDetector(
          key: const Key('picker-create'),
          behavior: HitTestBehavior.opaque,
          onTap: () => showExerciseEditor(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: p.tile,
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            ),
            alignment: Alignment.center,
            child: Text.rich(
              TextSpan(
                text: 'Can’t find it? ',
                style: TextStyle(color: p.muted, fontSize: 16),
                children: [
                  TextSpan(
                    text: 'Create custom exercise',
                    style: TextStyle(
                      color: p.link,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
