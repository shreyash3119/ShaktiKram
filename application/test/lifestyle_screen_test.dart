import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';

import 'support/fakes.dart';

Future<Harness> _open(WidgetTester tester) async {
  final h = Harness.ready();
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('nav-Lifestyle')));
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
  await tester.tap(find.byKey(Key('tab-$label')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty phone shows empty states, not sample numbers', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Recovery and readiness'), findsOneWidget);
    expect(find.text('Start check-in'), findsOneWidget);
    await _pill(tester, 'Nutrition');
    expect(find.text('No target set'), findsWidgets);
    expect(find.text('No meals yet. Add one below.'), findsOneWidget);
    await _pill(tester, 'Supplements');
    expect(find.text('None added yet.'), findsOneWidget);
  });

  testWidgets('adding water saves a log on the phone', (tester) async {
    final h = await _open(tester);
    await tester.scrollUntilVisible(
      find.text('+250 ml'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await _tapVisible(tester, find.text('+250 ml'));
    final logs = await h.local.list('water_logs');
    expect(logs.single['amount_ml'], 250);
    expect(find.text('Hydration · 250 ml'), findsOneWidget);
  });

  Future<void> logSteps(WidgetTester tester, String value) async {
    await _tapVisible(tester, find.byKey(const Key('manual-steps')));
    // A centred dialog, not a new page: the Activity tab stays underneath it.
    expect(find.text('Log steps'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('steps-field')), value);
    await tester.tap(find.byKey(const Key('steps-save')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'steps are saved once a day and saving again edits the same record',
    (tester) async {
      final h = await _open(tester);
      await _pill(tester, 'Activity');
      await logSteps(tester, '4200');
      expect(find.text('Log steps'), findsNothing);
      expect(find.text('4,200'), findsOneWidget);

      await logSteps(tester, '9000');
      final rows = await h.local.list('daily_steps');
      expect(rows.single['steps'], 9000);
      expect(rows.single['source'], 'manual');
      expect(find.text('9,000'), findsOneWidget);
    },
  );

  testWidgets('a bad steps entry keeps the dialog open and saves nothing', (
    tester,
  ) async {
    final h = await _open(tester);
    await _pill(tester, 'Activity');
    await logSteps(tester, '');
    expect(find.text('Log steps'), findsOneWidget);
    expect(await h.local.list('daily_steps'), isEmpty);
  });

  testWidgets('the Steps card opens the history with Day, Week and Month', (
    tester,
  ) async {
    await _open(tester);
    await _pill(tester, 'Activity');
    await logSteps(tester, '5000');
    await _tapVisible(tester, find.byKey(const Key('steps-card')));

    // Opens on Week: today's steps are the week's total and appear in the date list.
    expect(find.byKey(const Key('steps-total')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('steps-total'))).data,
      '5,000',
    );
    expect(find.text('5,000 steps'), findsOneWidget);

    // Going back a week shows an empty period; next is available again, and disabled on the current one.
    await tester.tap(find.byKey(const Key('steps-prev')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('steps-total'))).data, '0');
    expect(find.text('No steps saved for these days.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('steps-next')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<IconButton>(find.byKey(const Key('steps-next'))).onPressed,
      isNull,
    );

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('steps-total'))).data,
      '5,000',
    );
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsWidgets);

    await tester.tap(find.byKey(const Key('steps-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('steps-card')), findsOneWidget);
  });

  testWidgets('a supplement can be added and marked taken', (tester) async {
    final h = await _open(tester);
    await _pill(tester, 'Supplements');
    await tester.enterText(
      find.byKey(const Key('supplement-name')),
      'Creatine',
    );
    await tester.scrollUntilVisible(
      find.text('Save supplement'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await _tapVisible(tester, find.text('Save supplement'));
    expect((await h.local.list('supplements')).single['name'], 'Creatine');
    expect(await h.local.list('supplement_phases'), hasLength(1));

    await tester.scrollUntilVisible(
      find.text('Taken'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await _tapVisible(tester, find.text('Taken'));
    expect((await h.local.list('supplement_logs')).single['outcome'], 'taken');
  });
}
