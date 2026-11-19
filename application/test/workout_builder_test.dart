import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/sync/change_writer.dart';
import 'package:shaktikram/features/training/data/training_management_service.dart';
import 'package:shaktikram/features/training/data/training_providers.dart';

import 'support/fakes.dart';

/// Opens the Workout start page on a phone holding two exercises and one template.
Future<(Harness, ProviderContainer)> _open(WidgetTester tester) async {
  final h = Harness.ready();
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()),
  );
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(tester.element(find.byType(ShaktiKramApp)));
  final bench = await c.read(changeWriterProvider).upsert('exercises', {
    'name': 'Bench press',
    'category': 'compound',
    'is_custom': true,
  });
  await c.read(changeWriterProvider).upsert('exercises', {
    'name': 'Cable fly',
    'category': 'isolation',
    'is_custom': true,
  });
  await c.read(trainingManagementServiceProvider).createTemplate(
    name: 'Push day',
    exercises: [
      TemplateExerciseDraft(exerciseId: bench, targetSets: 4, repMin: 6, repMax: 8),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start workout'));
  await tester.pumpAndSettle();
  return (h, c);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('the start page shows the tiles and starts with nothing chosen', (tester) async {
    final (h, _) = await _open(tester);
    expect(find.text('Templates'), findsOneWidget);
    expect(find.text('1 saved'), findsOneWidget);
    expect(find.text('Add exercise'), findsOneWidget);
    expect(find.text('Search 2'), findsOneWidget);
    expect(find.text('Save template'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.pumpAndSettle();
    expect((await h.local.list('workout_sessions')).single['status'], 'in_progress');
    expect(await h.local.list('session_exercises'), isEmpty);
    await _close(tester);
  });

  testWidgets('the picker searches, adds and removes, and Done returns the list', (tester) async {
    final (h, _) = await _open(tester);
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
    expect(find.text('0 in this workout'), findsOneWidget);
    expect(find.text('2 exercises'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('picker-search')), 'fly');
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 results for “fly”'), findsOneWidget);
    expect(find.text('Bench press'), findsNothing);

    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('Done · 1 added'), findsOneWidget);

    await tester.tap(find.text('Added'));
    await tester.pumpAndSettle();
    expect(find.text('Added'), findsNothing);
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('picker-done')));
    await tester.pumpAndSettle();
    expect(find.text('Your workout · 1 exercise'), findsOneWidget);
    expect(find.text('Cable fly'), findsOneWidget);
    expect(find.text('Start workout · 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.pumpAndSettle();
    final rows = await h.local.list('session_exercises');
    expect(rows.length, 1);
    expect(rows.single['status'], 'added');
    await _close(tester);
  });

  testWidgets('a template is loaded with its targets and keeps its link when started unchanged', (tester) async {
    final (h, _) = await _open(tester);
    await tester.tap(find.byKey(const Key('open-templates')));
    await tester.pumpAndSettle();
    expect(find.text('Choose one to load its exercises'), findsOneWidget);
    expect(find.textContaining('v1 · 1 exercise'), findsOneWidget);

    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(find.text('Your workout · 1 exercise'), findsOneWidget);
    expect(find.textContaining('4 × 6–8'), findsWidgets);

    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.pumpAndSettle();
    final session = (await h.local.list('workout_sessions')).single;
    expect(session['template_version_id'], isNotNull);
    final row = (await h.local.list('session_exercises')).single;
    expect(row['template_exercise_id'], isNotNull);
    await _close(tester);
  });

  testWidgets('an edited list is started without claiming the template', (tester) async {
    final (h, _) = await _open(tester);
    await tester.tap(find.byKey(const Key('open-templates')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picker-done')));
    await tester.pumpAndSettle();
    expect(find.text('Start workout · 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('start-workout')));
    await tester.pumpAndSettle();
    expect((await h.local.list('workout_sessions')).single['template_version_id'], isNull);
    expect((await h.local.list('session_exercises')).length, 2);
    await _close(tester);
  });

  testWidgets('removing a row takes it off the list', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('open-templates')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('remove-draft-0')));
    await tester.pumpAndSettle();
    expect(find.text('Your workout'), findsOneWidget);
    expect(find.text('Start workout'), findsWidgets);
    await _close(tester);
  });
}
