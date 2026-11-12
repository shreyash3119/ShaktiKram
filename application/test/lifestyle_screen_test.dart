import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/routing/app_shell.dart';
import 'package:shaktikram/core/widgets/controls.dart';

import 'support/fakes.dart';

Future<Harness> _open(WidgetTester tester) async {
  final h = Harness.ready();
  await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(AppBottomBar), matching: find.text('Lifestyle')));
  await tester.pumpAndSettle();
  return h;
}

/// Scrolls [target] fully into view and waits for the layout before tapping it.
Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _pill(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(PillTabs).first, matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty phone shows empty states, not sample numbers', (tester) async {
    await _open(tester);
    expect(find.text('Today’s lifestyle'), findsOneWidget);
    expect(find.text('No target set'), findsWidgets);
    await _pill(tester, 'Supplements');
    expect(find.text('No supplements added yet.'), findsOneWidget);
  });

  testWidgets('adding water saves a log on the phone', (tester) async {
    final h = await _open(tester);
    await tester.scrollUntilVisible(find.text('+ 250 ml'), 300, scrollable: find.byType(Scrollable).first);
    await _tapVisible(tester, find.text('+ 250 ml'));
    final logs = await h.local.list('water_logs');
    expect(logs.single['amount_ml'], 250);
    expect(find.text('250 ml today'), findsOneWidget);
  });

  testWidgets('steps are saved once a day and saving again edits the same record', (tester) async {
    final h = await _open(tester);
    await _pill(tester, 'Activity');
    final field = find.byKey(const Key('steps-field'));
    await tester.enterText(field, '4200');
    await _tapVisible(tester, find.text('Save'));
    expect(find.text('4200 steps'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('steps-field')), '9000');
    await _tapVisible(tester, find.text('Save'));
    final rows = await h.local.list('daily_steps');
    expect(rows.single['steps'], 9000);
    expect(find.text('9000 steps'), findsOneWidget);
  });

  testWidgets('a supplement can be added and marked taken', (tester) async {
    final h = await _open(tester);
    await _pill(tester, 'Supplements');
    await tester.enterText(find.byKey(const Key('supplement-name')), 'Creatine');
    await tester.scrollUntilVisible(find.text('Save supplement'), 300, scrollable: find.byType(Scrollable).first);
    await _tapVisible(tester, find.text('Save supplement'));
    expect((await h.local.list('supplements')).single['name'], 'Creatine');
    expect(await h.local.list('supplement_phases'), hasLength(1));

    await tester.scrollUntilVisible(find.text('Taken'), -300, scrollable: find.byType(Scrollable).first);
    await _tapVisible(tester, find.text('Taken'));
    expect((await h.local.list('supplement_logs')).single['outcome'], 'taken');
  });
}
