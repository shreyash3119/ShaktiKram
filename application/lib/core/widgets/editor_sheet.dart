import 'package:flutter/material.dart';

import '../errors/user_facing_error.dart';
import '../theme/app_theme.dart';
import 'controls.dart';

/// Opens a form in a bottom sheet that lifts above the keyboard and scrolls when it is tall.
Future<T?> showEditorSheet<T>(BuildContext context, {required String title, required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.pal.card,
    builder: (sheet) {
      final p = sheet.pal;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheet).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppTheme.cardPadding, 16, AppTheme.cardPadding, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w800))),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.of(sheet).pop(), icon: Icon(Icons.close, color: p.muted)),
            ]),
            const SizedBox(height: 8),
            builder(sheet),
          ]),
        ),
      );
    },
  );
}

/// The words to show when a save fails: a rule the person broke is shown as written, anything else is generic.
String saveErrorText(Object e) {
  if (e is UserFacingError) return e.message;
  if (e is ArgumentError) return '${e.message}';
  if (e is StateError) return e.message;
  return 'Could not save. Try again.';
}

/// A red message line for a form.
class FormError extends StatelessWidget {
  const FormError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(message!, key: const Key('form-error'), style: TextStyle(color: context.pal.red, fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}

/// Options shown as tappable chips. [multi] lets several be on at once.
class ChoiceWrap extends StatelessWidget {
  const ChoiceWrap({super.key, required this.options, required this.selected, required this.onToggle});

  /// (id, label) pairs.
  final List<(String, String)> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in options)
        GestureDetector(
          onTap: () => onToggle(o.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(color: selected.contains(o.$1) ? p.primary : p.tile, borderRadius: BorderRadius.circular(14)),
            child: Text(o.$2, style: TextStyle(color: selected.contains(o.$1) ? p.onPrimary : p.text, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
    ]);
  }
}

/// A confirmation with two or three choices. Returns the chosen value, or null if dismissed.
Future<String?> askChoice(BuildContext context, {required String title, required String body, required List<(String, String, ButtonKind)> choices}) {
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: d.pal.card,
      title: Text(title, style: TextStyle(color: d.pal.text, fontWeight: FontWeight.w800)),
      content: Text(body, style: TextStyle(color: d.pal.muted, height: 1.35)),
      actions: [
        for (final c in choices)
          TextButton(
            onPressed: () => Navigator.of(d).pop(c.$1),
            child: Text(c.$2, style: TextStyle(color: c.$3 == ButtonKind.danger ? d.pal.red : (c.$3 == ButtonKind.primary ? d.pal.primary : d.pal.text), fontWeight: FontWeight.w700)),
          ),
      ],
    ),
  );
}
