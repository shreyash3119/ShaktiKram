import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/sync/sync_status.dart';

import 'support/fakes.dart';

/// These tests run as a signed-in, registered phone, so the app opens on Home.
Future<void> _pumpApp(WidgetTester tester, {List<Override> extra = const []}) async {
  final h = Harness.ready();
  await tester.pumpWidget(ProviderScope(overrides: [...h.overrides, ...extra], child: const ShaktiKramApp()));
  await tester.pumpAndSettle();
}

Finder _navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Finder _appBarTitle(String title) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(title));

void main() {
  testWidgets('opens on Home and shows the six sections', (tester) async {
    await _pumpApp(tester);

    expect(_appBarTitle('Home'), findsOneWidget);
    for (final label in ['Home', 'Training', 'Progress', 'Lifestyle', 'Reports', 'Settings']) {
      expect(_navLabel(label), findsOneWidget, reason: 'missing section $label');
    }
  });

  testWidgets('tapping each section opens its screen', (tester) async {
    await _pumpApp(tester);

    for (final label in ['Training', 'Progress', 'Lifestyle', 'Reports', 'Settings', 'Home']) {
      await tester.tap(_navLabel(label));
      await tester.pumpAndSettle();
      expect(_appBarTitle(label), findsOneWidget, reason: 'screen for $label did not open');
    }
  });

  testWidgets('the sync indicator shows a status on every screen', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Synced'), findsOneWidget);
    await tester.tap(_navLabel('Training'));
    await tester.pumpAndSettle();
    expect(find.text('Synced'), findsOneWidget);
  });

  testWidgets('the sync indicator shows the waiting count', (tester) async {
    await _pumpApp(tester, extra: [
      syncStatusProvider.overrideWith(() => _FixedSync(const SyncStatus(SyncPhase.pending, pendingCount: 3))),
    ]);

    expect(find.text('3 waiting'), findsOneWidget);
  });

  testWidgets('Home shows today card, check-in card and metric placeholders', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Daily check-in'), findsOneWidget);
    expect(find.text('Workout streak'), findsOneWidget);
    expect(find.text('Current weight'), findsOneWidget);
    expect(find.text('Steps today'), findsOneWidget);
  });
}

class _FixedSync extends SyncStatusNotifier {
  _FixedSync(this._value);
  final SyncStatus _value;

  @override
  SyncStatus build() => _value;
}
