import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/routing/app_shell.dart';
import 'package:shaktikram/core/theme/app_theme.dart';
import 'package:shaktikram/features/training/presentation/training_editor_widgets.dart';

Widget _host(Widget child, {double width = 360}) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: Center(child: SizedBox(width: width, child: child)),
  ),
);

void main() {
  const labels = [
    'Home',
    'Training',
    'Progress',
    'Lifestyle',
    'Reports',
    'Settings',
  ];

  testWidgets('bottom bar: only the selected section shows its name', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder:
            (context, setState) => _host(
              AppBottomBar(
                currentIndex: selected,
                onSelected: (i) => setState(() => selected = i),
              ),
            ),
      ),
    );
    for (var i = 0; i < labels.length; i++) {
      await tester.tap(find.byKey(Key('nav-${labels[i]}')));
      await tester.pumpAndSettle();
      expect(selected, i);
      for (final l in labels) {
        expect(find.text(l), l == labels[i] ? findsOneWidget : findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('long muscle names wrap inside a narrow chip row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            MuscleChip(
              'Transverse abdominis (deep core muscles)',
              selected: true,
              helping: true,
            ),
            MuscleChip('Upper abs (rectus abdominis)', selected: true),
          ],
        ),
        width: 220,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
