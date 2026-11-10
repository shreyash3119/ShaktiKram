import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Rounded surface used for every block on a screen.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppTheme.cardPadding),
      decoration: BoxDecoration(
        color: color ?? context.pal.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: child,
    );
  }
}

/// A smaller tile inside a card (stat tiles, day tiles).
class InnerTile extends StatelessWidget {
  const InnerTile({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.pal.tile,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: box);
  }
}

/// Card title with the optional amber "Sample values" badge and a blue link on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.sample = false, this.link, this.onLink});

  final String title;
  final bool sample;
  final String? link;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Text(title, style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w700, height: 1.25)),
      ),
      if (sample) ...[
        const SizedBox(width: 8),
        Text('Sample values', style: TextStyle(color: p.amber, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
      if (link != null) ...[
        const SizedBox(width: 10),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLink ?? () {},
          child: Text('$link ›', style: TextStyle(color: p.link, fontSize: 14, fontWeight: FontWeight.w500)),
        ),
      ],
    ]);
  }
}

/// Small upper-case label between cards ("MORE", "QUICK ACTIONS").
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: context.pal.muted, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      ),
    );
  }
}

/// Muted explanatory text.
class MutedText extends StatelessWidget {
  const MutedText(this.text, {super.key, this.size = 14, this.align});
  final String text;
  final double size;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) {
    return Text(text, textAlign: align, style: TextStyle(color: context.pal.muted, fontSize: size, height: 1.35));
  }
}

/// A bold value over a muted label ("12,450 kg" / "Volume").
class StatBlock extends StatelessWidget {
  const StatBlock(this.value, this.label, {super.key, this.size = 22, this.valueColor});

  final String value;
  final String label;
  final double size;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: TextStyle(color: valueColor ?? p.text, fontSize: size, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
    ]);
  }
}

/// One row of a list: bold title, muted subtitle and an optional value, label or chevron on the right.
class RowItem extends StatelessWidget {
  const RowItem({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingColor,
    this.chevron = false,
    this.onTap,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final Color? trailingColor;
  final bool chevron;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.3)),
            ],
          ]),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing!, style: TextStyle(color: trailingColor ?? p.muted, fontSize: 14)),
        ],
        if (chevron) ...[
          const SizedBox(width: 8),
          Text('›', style: TextStyle(color: p.muted, fontSize: 18)),
        ],
      ]),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// Rows separated by thin dividers.
class RowList extends StatelessWidget {
  const RowList(this.rows, {super.key});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(Divider(height: 1, thickness: 1, color: p.divider));
      out.add(rows[i]);
    }
    return Column(children: out);
  }
}

/// Title row with its card, so a screen is a flat list of one-line calls.
class TitledCard extends StatelessWidget {
  const TitledCard({
    super.key,
    required this.title,
    required this.children,
    this.sample = false,
    this.link,
    this.onLink,
  });

  final String title;
  final bool sample;
  final String? link;
  final VoidCallback? onLink;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(title, sample: sample, link: link, onLink: onLink),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }
}

/// Page frame: large title with a subtitle, then the content. Used by every tab.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({super.key, required this.title, this.subtitle, this.trailing, required this.children});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.pagePadding, 20, AppTheme.pagePadding, 24),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(color: p.text, fontSize: 30, fontWeight: FontWeight.w800, height: 1.15)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: TextStyle(color: p.muted, fontSize: 15)),
                  ],
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ]),
            const SizedBox(height: AppTheme.gap + 4),
            for (final child in children) ...[child, const SizedBox(height: AppTheme.gap)],
          ],
        ),
      ),
    );
  }
}
