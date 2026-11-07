import 'package:flutter/material.dart';

/// A small dashboard card: label, one bold value and an optional note.
/// A null [value] renders as a dash, used while the data source is not available yet.
class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, this.value, this.unit, this.note, this.icon});

  final String label;
  final String? value;
  final String? unit;
  final String? note;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: muted), const SizedBox(width: 6)],
            Expanded(child: Text(label, style: text.labelMedium?.copyWith(color: muted))),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(value ?? '—', style: text.headlineSmall),
            if (value != null && unit != null) ...[
              const SizedBox(width: 4),
              Text(unit!, style: text.labelMedium?.copyWith(color: muted)),
            ],
          ]),
          if (note != null) ...[const SizedBox(height: 4), Text(note!, style: text.bodySmall?.copyWith(color: muted))],
        ]),
      ),
    );
  }
}
