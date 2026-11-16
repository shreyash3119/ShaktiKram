import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/editor_sheet.dart';
import '../../progress/data/progress_models.dart';
import '../../progress/data/progress_providers.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';
import 'training_editor_widgets.dart';

/// Adds an exercise (no [exercise], a sheet) or edits one (a full page).
Future<void> showExerciseEditor(BuildContext context, {Exercise? exercise}) {
  if (exercise == null) {
    return showEditorSheet<void>(
      context,
      title: 'Add exercise',
      builder: (_) => const _ExerciseForm(),
    );
  }
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder:
          (_) => _FullPage(
            title: 'Edit exercise',
            closeIcon: Icons.close,
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pagePadding,
                8,
                AppTheme.pagePadding,
                24,
              ),
              child: _ExerciseForm(exercise: exercise),
            ),
          ),
    ),
  );
}

/// What the app knows about an exercise: muscles, personal records, notes, and archiving.
Future<void> showExerciseDetail(BuildContext context, String exerciseId) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => _ExerciseDetailPage(exerciseId)),
    );

/// A page with a header row (close or back, a centred title, an optional trailing widget).
class _FullPage extends StatelessWidget {
  const _FullPage({
    required this.title,
    required this.closeIcon,
    required this.body,
    this.trailing,
  });

  final String title;
  final IconData closeIcon;
  final Widget body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:const EdgeInsets.fromLTRB(
                AppTheme.pagePadding - 8,
                8,
                AppTheme.pagePadding,
                4,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        key: const Key('page-close'),
                        tooltip: closeIcon == Icons.close ? 'Close' : 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(closeIcon, color: p.text, size: 28),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Add / edit form
// ---------------------------------------------------------------------------------------------------------------

class _ExerciseForm extends ConsumerStatefulWidget {
  const _ExerciseForm({this.exercise});

  final Exercise? exercise;

  @override
  ConsumerState<_ExerciseForm> createState() => _ExerciseFormState();
}

class _ExerciseFormState extends ConsumerState<_ExerciseForm> {
  late String _name = widget.exercise?.name ?? '';
  late String _notes = widget.exercise?.notes ?? '';
  late String? _category = widget.exercise?.category;
  late String? _equipment = widget.exercise?.equipmentId;
  final Set<String> _primary = {};
  final Set<String> _secondary = {};
  String? _error;
  bool _busy = false;

  bool get _isEdit => widget.exercise != null;

  @override
  void initState() {
    super.initState();
    final e = widget.exercise;
    if (e != null) {
      ref.read(trainingRepositoryProvider).exerciseMuscles(e.id).then((rows) {
        if (!mounted) return;
        setState(() {
          for (final r in rows) {
            (r.role == 'primary' ? _primary : _secondary).add(r.muscleId);
          }
        });
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(trainingManagementServiceProvider);
      final e = widget.exercise;
      if (e == null) {
        await service.createExercise(
          name: _name,
          category: _category,
          equipmentId: _equipment,
          notes: _notes,
          primaryMuscleIds: _primary.toList(),
          secondaryMuscleIds: _secondary.toList(),
        );
      } else {
        await service.updateExercise(
          e.id,
          name: _name,
          category: _category,
          equipmentId: _equipment,
          notes: _notes,
          primaryMuscleIds: _primary.toList(),
          secondaryMuscleIds: _secondary.toList(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = saveErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _togglePrimary(String id) => setState(() {
    if (!_primary.remove(id)) {
      _primary.add(id);
      _secondary.remove(id);
    }
  });

  Future<void> _editRole({
    required bool primary,
    required List<MuscleRef> muscles,
  }) async {
    final chosen = await pickMuscles(
      context,
      title: primary ? 'Main muscles' : 'Helping muscles',
      muscles: muscles,
      selected: primary ? _primary : _secondary,
      disabled: primary ? _secondary : _primary,
      helping: !primary,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      final target = primary ? _primary : _secondary;
      target
        ..clear()
        ..addAll(chosen);
      (primary ? _secondary : _primary).removeAll(chosen);
    });
  }

  Future<void> _pickEquipment(List<EquipmentRef> equipment) async {
    final id = await pickEquipment(
      context,
      equipment: equipment,
      selected: _equipment,
    );
    if (id == null || !mounted) return;
    setState(() => _equipment = id.isEmpty ? null : id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final muscles =
        ref.watch(musclesProvider).valueOrNull ?? const <MuscleRef>[];
    final equipment =
        ref.watch(equipmentProvider).valueOrNull ?? const <EquipmentRef>[];
    final names = {for (final m in muscles) m.id: m.label};
    final equipmentName =
        equipment.where((q) => q.id == _equipment).firstOrNull?.label;
    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        t,
        style: TextStyle(
          color: p.muted,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    final nameField = FieldBox(
      initial: _name,
      hint: 'e.g. Incline dumbbell press',
      fieldKey: const Key('exercise-name'),
      textAlign: TextAlign.start,
      onChanged: (v) => _name = v,
    );
    final notesField = FieldBox(
      initial: _notes,
      hint: 'Setup, cues, machine number…',
      height: 104,
      multiline: true,
      fieldKey: const Key('exercise-notes'),
      onChanged: (v) => _notes = v,
    );
    final save = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormError(_error),
        AppButton.primary('Save exercise', onPressed: _busy ? null : _save),
      ],
    );

    if (_isEdit) {
      Widget roleRow(String label, bool primary) {
        final ids = primary ? _primary : _secondary;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: TextStyle(color: p.muted, fontSize: 16),
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in ids)
                    MuscleChip(
                      names[id] ?? 'Muscle',
                      selected: true,
                      helping: !primary,
                      onRemove:
                          () => setState(() {
                            ids.remove(id);
                          }),
                    ),
                  AddChip(
                    key: Key(primary ? 'add-primary' : 'add-secondary'),
                    onTap: () => _editRole(primary: primary, muscles: muscles),
                  ),
                ],
              ),
            ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading('Exercise name'),
          nameField,
          const SizedBox(height: 22),
          heading('Movement type'),
          PillTabs(
            labels: const ['Compound', 'Isolation'],
            index: _category == null ? -1 : (_category == 'compound' ? 0 : 1),
            container: true,
            onChanged:
                (i) => setState(
                  () => _category = i == 0 ? 'compound' : 'isolation',
                ),
          ),
          const SizedBox(height: 20),
          Text(
            'Target muscles',
            style: TextStyle(
              color: p.muted,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          EditorPanel(
            child: Column(
              children: [
                roleRow('Primary', true),
                const SizedBox(height: 14),
                roleRow('Secondary', false),
              ],
            ),
          ),
          const SizedBox(height: 18),
          heading('Equipment'),
          EditorPanel(
            key: const Key('equipment-row'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            onTap: () => _pickEquipment(equipment),
            child: Row(
              children: [
                Icon(Icons.fitness_center, color: p.muted, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    equipmentName ?? 'None',
                    style: TextStyle(
                      color: equipmentName == null ? p.muted : p.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(Icons.expand_more, color: p.muted),
              ],
            ),
          ),
          const SizedBox(height: 22),
          heading('Form cues and notes · optional'),
          notesField,
          const SizedBox(height: 22),
          save,
        ],
      );
    }

    final helpingNames = [
      for (final id in _secondary) names[id] ?? '',
    ].where((t) => t.isNotEmpty).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Name'),
        nameField,
        const SizedBox(height: 16),
        const FieldLabel('Category'),
        PillTabs(
          labels: const ['Not set', 'Compound', 'Isolation'],
          index: _category == null ? 0 : (_category == 'compound' ? 1 : 2),
          container: true,
          onChanged:
              (i) => setState(
                () =>
                    _category =
                        i == 0 ? null : (i == 1 ? 'compound' : 'isolation'),
              ),
        ),
        const SizedBox(height: 18),
        EditorPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Main muscles',
                      style: TextStyle(
                        color: p.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    key: const Key('main-muscles-badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: p.primary),
                    ),
                    child: Text(
                      _primary.isEmpty
                          ? 'required'
                          : '${_primary.length} selected · required',
                      style: TextStyle(color: p.link, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              MuscleGroupPicker(
                muscles: muscles,
                selected: _primary,
                disabled: _secondary,
                onToggle: _togglePrimary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        EditorPanel(
          key: const Key('helping-muscles-row'),
          onTap: () => _editRole(primary: false, muscles: muscles),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Helping muscles',
                      style: TextStyle(
                        color: p.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _secondary.isEmpty
                          ? 'Optional · none selected'
                          : 'Optional · $helpingNames',
                      style: TextStyle(color: p.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: p.muted),
            ],
          ),
        ),
        if (equipment.isNotEmpty) ...[
          const SizedBox(height: 14),
          EditorPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Equipment',
                        style: TextStyle(
                          color: p.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'Optional',
                      style: TextStyle(color: p.muted, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (equipmentName != null) ...[
                  Wrap(
                    children: [
                      MuscleChip(
                        equipmentName,
                        selected: true,
                        onRemove: () => setState(() => _equipment = null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                DashedButton(
                  equipmentName == null
                      ? '+ Add equipment'
                      : 'Change equipment',
                  onPressed: () => _pickEquipment(equipment),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        const FieldLabel('Notes · optional'),
        notesField,
        const SizedBox(height: 18),
        save,
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Details
// ---------------------------------------------------------------------------------------------------------------

String _kg(double v) =>
    v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

class _ExerciseDetailPage extends ConsumerWidget {
  const _ExerciseDetailPage(this.exerciseId);

  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final exercise =
        [
          for (final e
              in ref.watch(exerciseLibraryProvider).valueOrNull ??
                  const <Exercise>[])
            if (e.id == exerciseId) e,
        ].firstOrNull;
    if (exercise == null) {
      return const _FullPage(
        title: 'Exercise details',
        closeIcon: Icons.arrow_back_ios_new,
        body:  Padding(
          padding: EdgeInsets.all(20),
          child: MutedText('This exercise is not on this phone.'),
        ),
      );
    }
    final muscles = {
      for (final m
          in ref.watch(musclesProvider).valueOrNull ?? const <MuscleRef>[])
        m.id: m.label,
    };
    final equipmentName =
        ref
            .watch(equipmentProvider)
            .valueOrNull
            ?.where((q) => q.id == exercise.equipmentId)
            .firstOrNull
            ?.label;
    final links =
        ref.watch(exerciseMusclesProvider(exerciseId)).valueOrNull ??
        const <({String muscleId, String role})>[];
    List<String> names(String role) => [
      for (final l in links)
        if (l.role == role && (muscles[l.muscleId] ?? '').isNotEmpty)
          muscles[l.muscleId]!,
    ];
    final primary = names('primary');
    final secondary = names('secondary');

    // Personal records recorded on this phone for this exercise.
    final records = [
      for (final r
          in ref.watch(personalRecordsProvider).valueOrNull ??
              const <PersonalRecord>[])
        if (r.exerciseId == exerciseId) r,
    ];
    PersonalRecord? best(String kind) {
      PersonalRecord? top;
      for (final r in records) {
        if (r.kind == kind && (top == null || r.value > top.value)) top = r;
      }
      return top;
    }

    final heaviest = best('max_weight');
    final e1rm = best('est_1rm');
    final bestSet =
        heaviest == null
            ? '—'
            : '${_kg(heaviest.weightKg ?? heaviest.value)} kg${heaviest.reps == null ? '' : ' × ${heaviest.reps}'}';
    final category =
        exercise.category == null
            ? null
            : '${exercise.category![0].toUpperCase()}${exercise.category!.substring(1)}';

    Widget sectionTitle(String t) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        t,
        style: TextStyle(
          color: p.muted,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    Widget roleRow(String label, List<String> items, {required bool helping}) {
      return Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: TextStyle(color: p.muted, fontSize: 16)),
          ),
          Expanded(
            child:
                items.isEmpty
                    ? Text('—', style: TextStyle(color: p.muted))
                    : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final n in items)
                          MuscleChip(n, selected: true, helping: helping),
                      ],
                    ),
          ),
        ],
      );
    }

    Widget statTile(String label, String value, Key key) => Expanded(
      child: EditorPanel(
        key: key,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: p.text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );

    final notes = (exercise.notes ?? '').trim();
    return _FullPage(
      title: 'Exercise details',
      closeIcon: Icons.arrow_back_ios_new,
      trailing: OutlinedButton(
        key: const Key('exercise-edit'),
        onPressed: () => showExerciseEditor(context, exercise: exercise),
        child: const Text('Edit'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding:const EdgeInsets.fromLTRB(
                AppTheme.pagePadding,
                8,
                AppTheme.pagePadding,
                20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise.name,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (category != null) _InfoChip(category, strong: true),
                      if (equipmentName != null) _InfoChip(equipmentName),
                      if (exercise.isInactive) const _InfoChip('Archived'),
                    ],
                  ),
                  sectionTitle('Target muscles'),
                  EditorPanel(
                    child: Column(
                      children: [
                        roleRow('Primary', primary, helping: false),
                        const SizedBox(height: 14),
                        roleRow('Secondary', secondary, helping: true),
                      ],
                    ),
                  ),
                  sectionTitle('Your stats · all time'),
                  Row(
                    children: [
                      statTile('Best set', bestSet, const Key('stat-best-set')),
                      const SizedBox(width: 12),
                      statTile(
                        'Est. 1RM',
                        e1rm == null ? '—' : '${_kg(e1rm.value)} kg',
                        const Key('stat-e1rm'),
                      ),
                    ],
                  ),
                  if (notes.isNotEmpty) ...[
                    sectionTitle('Form cues and notes'),
                    EditorPanel(
                      child: Text(
                        notes,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 17,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  const SizedBox(height: 24),
                  AppButton(
                    exercise.isInactive
                        ? 'Use this exercise again'
                        : 'Archive exercise',
                    kind:
                        exercise.isInactive
                            ? ButtonKind.tonal
                            : ButtonKind.danger,
                    onPressed: () async {
                      await ref
                          .read(trainingManagementServiceProvider)
                          .setExerciseInactive(
                            exercise.id,
                            !exercise.isInactive,
                          );
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: MutedText(
                      exercise.isInactive
                          ? 'Brings it back into new workouts.'
                          : 'Stops using it in new workouts.',
                      align: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Center(
                    child: MutedText(
                      'Past workouts keep it either way. Nothing is deleted.',
                      align: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.label, {this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: strong ? p.link.withValues(alpha: 0.25) : p.tile,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: strong ? p.link : p.text,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
