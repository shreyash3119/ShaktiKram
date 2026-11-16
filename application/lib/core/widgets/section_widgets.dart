import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small building blocks shared by the Progress and Lifestyle tabs.

/// Text tabs with an underline under the selected one, scrolling sideways when they do not fit.
class UnderlineTabs extends StatelessWidget {
  const UnderlineTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              InkWell(
                key: Key('tab-${labels[i]}'),
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                  margin: const EdgeInsets.only(right: 22),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 3,
                        color: i == index ? p.primary : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: i == index ? p.text : p.muted,
                      fontSize: 17,
                      fontWeight: i == index ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A square header button (info, refresh, notifications).
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: tooltip,
      child: InkWell(
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
  }
}

/// An empty-state line: an info tile and a sentence.
class NoteRow extends StatelessWidget {
  const NoteRow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
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
          child: Text(
            text,
            style: TextStyle(color: p.muted, fontSize: 17, height: 1.3),
          ),
        ),
      ],
    );
  }
}

/// A small note under the cards with an info icon.
class InfoLine extends StatelessWidget {
  const InfoLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 10),
            child: Icon(Icons.info_outline, size: 20, color: p.muted),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: p.muted, fontSize: 15, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small status pill ("Active").
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = color ?? p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Text(label, style: TextStyle(color: c, fontSize: 14)),
    );
  }
}
