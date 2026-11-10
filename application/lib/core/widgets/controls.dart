import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Pill-style tab or filter row. The selected pill is filled blue.
/// [container] puts the row on a card-coloured bar (the main sub-tab rows).
enum PillLayout { even, scroll, wrap }

class PillTabs extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.layout = PillLayout.even,
    this.container = false,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final PillLayout layout;
  final bool container;

  Widget _pill(BuildContext context, int i, {required bool expand}) {
    final p = context.pal;
    final selected = i == index;
    final pill = Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? p.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        labels[i],
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: TextStyle(
          color: selected ? p.onPrimary : p.muted,
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
    final tappable = GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onChanged(i), child: pill);
    return expand ? Expanded(child: tappable) : tappable;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final Widget row;
    switch (layout) {
      case PillLayout.even:
        row = Row(children: [for (var i = 0; i < labels.length; i++) _pill(context, i, expand: true)]);
      case PillLayout.scroll:
        row = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [for (var i = 0; i < labels.length; i++) _pill(context, i, expand: false)]),
        );
      case PillLayout.wrap:
        row = Wrap(spacing: 4, runSpacing: 6, children: [for (var i = 0; i < labels.length; i++) _pill(context, i, expand: false)]);
    }
    if (!container) return row;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20)),
      child: row,
    );
  }
}

enum ButtonKind { primary, tonal, danger }

/// Full-width rounded button. Primary is blue, tonal sits on a tile, danger is red text on a tile.
class AppButton extends StatelessWidget {
  const AppButton(this.label, {super.key, this.onPressed, this.kind = ButtonKind.tonal, this.height = 52});

  const AppButton.primary(this.label, {super.key, this.onPressed, this.height = 52}) : kind = ButtonKind.primary;

  final String label;
  final VoidCallback? onPressed;
  final ButtonKind kind;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final bg = kind == ButtonKind.primary ? p.primary : p.tile;
    final fg = switch (kind) {
      ButtonKind.primary => p.onPrimary,
      ButtonKind.tonal => p.text,
      ButtonKind.danger => p.red,
    };
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: onPressed ?? () {},
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

/// Two buttons side by side with equal width.
class ButtonPair extends StatelessWidget {
  const ButtonPair(this.left, this.right, {super.key});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(children: [Expanded(child: left), const SizedBox(width: 12), Expanded(child: right)]);
  }
}

/// A text link such as "Skip exercise".
class LinkText extends StatelessWidget {
  const LinkText(this.label, {super.key, this.onTap, this.color});
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(label, style: TextStyle(color: color ?? context.pal.link, fontSize: 15, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

/// Settings-style row with a switch.
class ToggleRow extends StatelessWidget {
  const ToggleRow({super.key, required this.title, this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: TextStyle(color: p.muted, fontSize: 13.5)),
            ],
          ]),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          thumbColor: WidgetStatePropertyAll(p.onPrimary),
          activeTrackColor: p.primary,
          inactiveTrackColor: p.tile,
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ]),
    );
  }
}

/// Number or text field that looks like the designs' tiles: centred text, no border.
class FieldBox extends StatefulWidget {
  const FieldBox({
    super.key,
    this.initial = '',
    this.hint,
    this.keyboard,
    this.onChanged,
    this.fieldKey,
    this.height = 56,
  });

  final String initial;
  final String? hint;
  final TextInputType? keyboard;
  final ValueChanged<String>? onChanged;
  final Key? fieldKey;
  final double height;

  @override
  State<FieldBox> createState() => _FieldBoxState();
}

class _FieldBoxState extends State<FieldBox> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(AppTheme.radius)),
      alignment: Alignment.center,
      child: TextField(
        key: widget.fieldKey,
        controller: _controller,
        keyboardType: widget.keyboard,
        textAlign: TextAlign.center,
        onChanged: widget.onChanged,
        style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(color: p.muted, fontSize: 15, fontWeight: FontWeight.w600),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }
}

/// Muted caption above a field ("Weight (kg)").
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: TextStyle(color: context.pal.muted, fontSize: 13.5)),
    );
  }
}

/// A field with its caption, for two-up form rows.
class LabeledField extends StatelessWidget {
  const LabeledField(this.label, {super.key, this.initial = '', this.hint, this.keyboard});
  final String label;
  final String initial;
  final String? hint;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldLabel(label),
      FieldBox(initial: initial, hint: hint, keyboard: keyboard),
    ]);
  }
}
