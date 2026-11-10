import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/routing/app_shell.dart';

import 'support/fakes.dart';

Future<void> _openSession(WidgetTester tester) async {
  final h = Harness.ready();
  await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start workout'));
  await tester.pumpAndSettle();
}

/// The session screen has a running clock, so end each test by removing the screen.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('Start workout opens the session without the bottom bar', (tester) async {
    await _openSession(tester);

    expect(find.text('Incline Dumbbell Press'), findsOneWidget);
    expect(find.byType(AppBottomBar), findsNothing);
    expect(find.textContaining('Exercise 2 of 7'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('confirming a set records it and starts the rest timer', (tester) async {
    await _openSession(tester);

    await tester.ensureVisible(find.byKey(const Key('confirm-set')));
    await tester.tap(find.byKey(const Key('confirm-set')));
    await tester.pump();
    expect(find.text('Enter weight and reps first.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));

    await tester.ensureVisible(find.byKey(const Key('reps-field')));
    await tester.enterText(find.byKey(const Key('reps-field')), '9');
    await tester.tap(find.byKey(const Key('confirm-set')));
    await tester.pump();

    expect(find.textContaining('Set 2 recorded'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('leaving asks first and Keep going stays', (tester) async {
    await _openSession(tester);

    await tester.tap(find.byKey(const Key('session-back')));
    await tester.pumpAndSettle();
    expect(find.text('Leave workout?'), findsOneWidget);

    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(find.text('Leave workout?'), findsNothing);
    expect(find.text('Incline Dumbbell Press'), findsOneWidget);
    await _close(tester);
  });
}
