import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/sync/change_writer.dart';
import 'package:shaktikram/features/home/presentation/home_screen.dart';

import 'support/fakes.dart';

void main() {
  test('weightPayload builds a valid body_measurements row', () {
    final payload = weightPayload(78.4, DateTime.utc(2026, 11, 8, 7));
    expect(payload['measurement_type'], 'weight');
    expect(payload['value'], 78.4);
    expect(payload['source'], 'manual');
    expect(payload['occurred_at'], '2026-11-08T07:00:00.000Z');
    expect((payload['local_date'] as String).length, 10);
    expect(payload.keys.toSet().intersection(forbiddenPayloadKeys), isEmpty);
  });

  test('ChangeWriter refuses read-only tables', () async {
    final h = Harness.ready();
    final container = ProviderContainer(overrides: h.overrides);
    addTearDown(container.dispose);
    expect(
      () => container.read(changeWriterProvider).upsert('personal_records', {}),
      throwsArgumentError,
    );
  });

  test(
    'ChangeWriter saves locally, queues the change and fills the row id',
    () async {
      final h = Harness.ready();
      final container = ProviderContainer(overrides: h.overrides);
      addTearDown(container.dispose);
      final id = await container.read(changeWriterProvider).upsert(
        'body_measurements',
        {
          ...weightPayload(78, DateTime.utc(2026, 11, 8, 7)),
          'updated_at': 'nope',
        },
      );
      final stored = await h.local.get('body_measurements', id);
      expect(stored!['id'], id);
      expect(stored.containsKey('updated_at'), isFalse);
      expect((await h.local.pendingOps()).single.entity, 'body_measurements');
    },
  );

  testWidgets('Log weight saves to the phone', (tester) async {
    final h = Harness.ready();
    await tester.pumpWidget(
      ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-log-weight')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quick-weight-field')), '77.5');
    await tester.tap(find.byKey(const Key('quick-weight-save')));
    await tester.pumpAndSettle();
    final rows = await h.local.list('body_measurements');
    expect(rows.single['value'], 77.5);
    expect(
      find.text('Weight saved on this phone. It will sync when online.'),
      findsOneWidget,
    );
    // The Lifestyle card now shows it.
    expect(find.textContaining('77.5 kg'), findsOneWidget);
  });

  testWidgets('Log weight refuses a value that cannot be right', (tester) async {
    final h = Harness.ready();
    await tester.pumpWidget(
      ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-weight-log')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quick-weight-field')), '5');
    await tester.tap(find.byKey(const Key('quick-weight-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a weight between 20 and 400 kg.'), findsOneWidget);
    expect(await h.local.list('body_measurements'), isEmpty);
  });
}
