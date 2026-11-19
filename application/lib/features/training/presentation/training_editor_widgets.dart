import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/editor_sheet.dart';
import '../data/training_models.dart';
import 'equipment_groups.dart';

/// Small building blocks shared by the training editors (exercise, template, split).

/// The order the muscle groups are shown in; any other group follows alphabetically.
const _groupOrder = ['arms', 'back', 'chest', 'shoulders', 'core', 'legs'];

/// "upper_back" -> "Upper back".
String groupTitle(String key) {
  if (key.isEmpty) return 'Other';
  final t = key.replaceAll('_', ' ');
  return '${t[0].toUpperCase()}${t.substring(1)}';
}

/// The muscle groups present in [muscles], in display order.
List<String> orderedGroups(Iterable<MuscleRef> muscles) {
  final keys = {for (final m in muscles) m.groupKey};
  int rank(String k) {
    final i = _groupOrder.indexOf(k);
    return i < 0 ? _groupOrder.length : i;
  }

  return keys.toList()..sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.compareTo(b);
  });
}

/// A bordered panel that sits inside a sheet or page.
class EditorPanel extends StatelessWidget {
  const EditorPanel({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.bordered = true,
  });

  /// Surface colour; the tile colour by default. Forms on a page background use the card colour, like other screens.
  final Color? color;
  final bool bordered;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final box = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color ?? p.tile,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: bordered ? Border.all(color: p.divider) : null,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: box,
    );
  }
}

/// A full-width button with a dashed outline, for adding things ("+ Add day").
class DashedButton extends StatelessWidget {
  const DashedButton(this.label, {super.key, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: CustomPaint(
        painter: _DashedBorder(p.divider, AppTheme.radius),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: onPressed == null ? p.muted : p.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
    final path =
        Path()..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        );
    for (final PathMetric m in path.computeMetrics()) {
      var at = 0.0;
      while (at < m.length) {
        canvas.drawPath(m.extractPath(at, at + 5), paint);
        at += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}

/// A small square icon button (move up, move down, remove).
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final on = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: p.tile,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: danger && on ? p.red : p.divider),
          ),
          child: Icon(
            icon,
            size: 20,
            color: !on ? p.faint : (danger ? p.red : p.text),
          ),
        ),
      ),
    );
  }
}

/// A rounded chip. [selected] fills it; [onRemove] adds a close mark.
class MuscleChip extends StatelessWidget {
  const MuscleChip(
    this.label, {
    super.key,
    this.selected = false,
    this.helping = false,
    this.onTap,
    this.onRemove,
  });

  final String label;
  final bool selected;

  /// The teal style used for helping (secondary) muscles.
  final bool helping;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fill =
        selected ? (helping ? p.greenFill : p.primary) : Colors.transparent;
    final fg = selected ? (helping ? p.green : p.onPrimary) : p.text;
    final edge = selected ? (helping ? p.green : p.primary) : p.divider;
    return InkWell(
      onTap: onTap ?? onRemove,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: edge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected && onRemove == null) ...[
              Icon(Icons.check, size: 18, color: fg),
              const SizedBox(width: 6),
            ],
            // Long names (for example "Transverse abdominis (deep core)") wrap inside the chip instead of overflowing.
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.close, size: 18, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}

/// A "+ Add" chip with a dashed outline.
class AddChip extends StatelessWidget {
  const AddChip({super.key, required this.onTap, this.label = '+ Add'});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: CustomPaint(
        painter: _DashedBorder(p.divider, 999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              color: p.muted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Muscle groups as underlined text tabs with that group's muscles as chips below.
class MuscleGroupPicker extends StatefulWidget {
  const MuscleGroupPicker({
    super.key,
    required this.muscles,
    required this.selected,
    required this.onToggle,
    this.helping = false,
    this.disabled = const {},
  });

  final List<MuscleRef> muscles;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool helping;

  /// Muscles that cannot be picked here (already used in the other role).
  final Set<String> disabled;

  @override
  State<MuscleGroupPicker> createState() => _MuscleGroupPickerState();
}

class _MuscleGroupPickerState extends State<MuscleGroupPicker> {
  String? _group;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final groups = orderedGroups(widget.muscles);
    if (groups.isEmpty) {
      return Text(
        'No muscles on this phone yet.',
        style: TextStyle(color: p.muted, fontSize: 14),
      );
    }
    final current =
        groups.contains(_group)
            ? _group!
            : (widget.muscles
                    .where((m) => widget.selected.contains(m.id))
                    .map((m) => m.groupKey)
                    .firstOrNull ??
                groups.first);
    final shown = [
      for (final m in widget.muscles)
        if (m.groupKey == current) m,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final g in groups)
                InkWell(
                  key: Key('muscle-group-$g'),
                  onTap: () => setState(() => _group = g),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                    margin: const EdgeInsets.only(right: 18),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: g == current ? p.primary : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Text(
                      groupTitle(g),
                      style: TextStyle(
                        color: g == current ? p.text : p.muted,
                        fontSize: 16,
                        fontWeight:
                            g == current ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: p.divider),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final m in shown)
              Opacity(
                opacity: widget.disabled.contains(m.id) ? 0.4 : 1,
                child: MuscleChip(
                  m.label,
                  key: Key('muscle-${m.id}'),
                  selected: widget.selected.contains(m.id),
                  helping: widget.helping,
                  onTap:
                      widget.disabled.contains(m.id)
                          ? null
                          : () => widget.onToggle(m.id),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Opens a sheet to pick several muscles; returns the chosen ids, or null if dismissed.
Future<Set<String>?> pickMuscles(
  BuildContext context, {
  required String title,
  required List<MuscleRef> muscles,
  required Set<String> selected,
  Set<String> disabled = const {},
  bool helping = false,
}) {
  final chosen = {...selected};
  return showEditorSheet<Set<String>>(
    context,
    title: title,
    builder:
        (sheet) => StatefulBuilder(
          builder:
              (_, setState) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MuscleGroupPicker(
                    muscles: muscles,
                    selected: chosen,
                    helping: helping,
                    disabled: disabled,
                    onToggle:
                        (id) => setState(() {
                          if (!chosen.remove(id)) chosen.add(id);
                        }),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      key: const Key('muscles-done'),
                      onPressed: () => Navigator.of(sheet).pop({...chosen}),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
        ),
  );
}

/// Opens a sheet to pick one piece of equipment: a search box, group filters, and the equipment under group headings
/// (alphabetical). Returns its id, '' for "none", or null if dismissed. Done stays at the bottom while the list scrolls.
Future<String?> pickEquipment(
  BuildContext context, {
  required List<EquipmentRef> equipment,
  String? selected,
}) {
  var chosen = selected;
  var query = '';
  EquipmentGroup? filter;
  return showEditorSheet<String>(
    context,
    title: 'Equipment',
    builder:
        (sheet) => StatefulBuilder(
          builder: (_, setState) {
            final p = sheet.pal;
            final q = query.trim().toLowerCase();
            final shown = [
              for (final e in equipment)
                if ((filter == null || equipmentGroupOf(e.key) == filter) &&
                    (q.isEmpty || e.label.toLowerCase().contains(q)))
                  e,
            ];
            final groups = [
              for (final g in EquipmentGroup.values)
                if (shown.any((e) => equipmentGroupOf(e.key) == g)) g,
            ];
            Widget filterChip(String label, EquipmentGroup? g) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: MuscleChip(
                label,
                key: Key('equipment-filter-$label'),
                selected: filter == g,
                onTap: () => setState(() => filter = g),
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FieldBox(
                  hint: 'Search equipment…',
                  fieldKey: const Key('equipment-search'),
                  textAlign: TextAlign.start,
                  onChanged: (v) => setState(() => query = v),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      filterChip('All', null),
                      for (final g in EquipmentGroup.values)
                        filterChip(g.label, g),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(sheet).size.height * 0.42,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (equipment.isEmpty)
                          Text(
                            'No equipment on this phone yet.',
                            style: TextStyle(color: p.muted, fontSize: 14),
                          )
                        else if (shown.isEmpty)
                          Text(
                            'No equipment matches.',
                            style: TextStyle(color: p.muted, fontSize: 15),
                          ),
                        for (final g in groups) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 10),
                            child: Text(
                              g.label.toUpperCase(),
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 14,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final e
                                  in ([
                                    for (final e in shown)
                                      if (equipmentGroupOf(e.key) == g) e,
                                  ]..sort(
                                    (a, b) => a.label.toLowerCase().compareTo(
                                      b.label.toLowerCase(),
                                    ),
                                  )))
                                MuscleChip(
                                  e.label,
                                  key: Key('equipment-${e.id}'),
                                  selected: e.id == chosen,
                                  onTap: () => setState(() => chosen = e.id),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        chosen == null ? 'None selected' : '1 selected',
                        key: const Key('equipment-count'),
                        style: TextStyle(color: p.muted, fontSize: 15),
                      ),
                    ),
                    if (chosen != null)
                      TextButton(
                        key: const Key('equipment-none'),
                        onPressed: () => Navigator.of(sheet).pop(''),
                        child: const Text('No equipment'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    key: const Key('equipment-done'),
                    onPressed: () => Navigator.of(sheet).pop(chosen ?? ''),
                    child: const Text('Done'),
                  ),
                ),
              ],
            );
          },
        ),
  );
}
