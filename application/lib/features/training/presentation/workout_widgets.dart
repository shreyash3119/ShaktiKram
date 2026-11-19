import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Header of the workout start, exercise picker and templates pages: a square back button, a title and a subtitle.
class WorkoutPageHeader extends StatelessWidget {
  const WorkoutPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.onBack,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        GestureDetector(
          key: const Key('session-back'),
          behavior: HitTestBehavior.opaque,
          onTap: onBack,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Icon(Icons.chevron_left, color: p.text, size: 26),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: TextStyle(color: p.muted, fontSize: 15)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A small tile-coloured button used on rows ("Add", "Use", "Repeat").
class RowButton extends StatelessWidget {
  const RowButton(this.label, {super.key, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.tile,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 42),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            label,
            style: TextStyle(
              color: p.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// The page body: a scrolling list on top, and an optional bar of buttons fixed at the bottom.
class WorkoutPageScaffold extends StatelessWidget {
  const WorkoutPageScaffold({
    super.key,
    required this.header,
    required this.children,
    this.bottom,
  });

  final Widget header;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.pagePadding,
                  14,
                  AppTheme.pagePadding,
                  16,
                ),
                children: [header, const SizedBox(height: AppTheme.gap), ...children],
              ),
            ),
            if (bottom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.pagePadding,
                  4,
                  AppTheme.pagePadding,
                  12,
                ),
                child: bottom,
              ),
          ],
        ),
      ),
    );
  }
}
