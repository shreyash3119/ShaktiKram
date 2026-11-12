import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/routing/app_shell.dart';
import 'package:shaktikram/core/sync/sync_status.dart';
import 'package:shaktikram/core/widgets/controls.dart';
import 'package:shaktikram/features/home/presentation/home_screen.dart';

import 'support/fakes.dart';

/// These tests run as a signed-in, registered phone, so the app opens on Home.
Future<void> _pumpApp(WidgetTester tester, {List<Override> extra = const []}) async {
  final h = Harness.ready();
  await tester.pumpWidget(ProviderScope(overrides: [...h.overrides, ...extra], child: const ShaktiKramApp()));
  await tester.pumpAndSettle();
}

Finder _navLabel(String label) => find.descendant(of: find.byType(AppBottomBar), matching: find.text(label));

/// A line that only that screen shows (its subtitle).
Map<String, String> _subtitles() => {
      'Home': dateLine(DateTime.now()),
      'Training': 'Splits, exercises and workouts',
      'Progress': 'Your history and change over time',
      'Lifestyle': 'Recovery, nutrition and daily activity',
      'Reports': 'Analyze history and export',
      'Settings': 'Profile, sync, preferences and data',
    };

Future<void> _tapPill(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(PillTabs).first, matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on Home and shows the six sections', (tester) async {
    await _pumpApp(tester);

    expect(find.text(_subtitles()['Home']!), findsOneWidget);
    expect(find.text(greetingFor(DateTime.now())), findsOneWidget);
    for (final label in ['Home', 'Training', 'Progress', 'Lifestyle', 'Reports', 'Settings']) {
      expect(_navLabel(label), findsOneWidget, reason: 'missing section $label');
    }
  });

  testWidgets('tapping each section opens its screen', (tester) async {
    await _pumpApp(tester);

    for (final label in ['Training', 'Progress', 'Lifestyle', 'Reports', 'Settings', 'Home']) {
      await tester.tap(_navLabel(label));
      await tester.pumpAndSettle();
      expect(find.text(_subtitles()[label]!), findsOneWidget, reason: 'screen for $label did not open');
    }
  });

  testWidgets('the Home header shows the sync status', (tester) async {
    await _pumpApp(tester);
    expect(find.text('Synced'), findsOneWidget);
  });

  testWidgets('the sync indicator shows the waiting count', (tester) async {
    await _pumpApp(tester, extra: [
      syncStatusProvider.overrideWith(() => _FixedSync(const SyncStatus(SyncPhase.pending, pendingCount: 3))),
    ]);

    expect(find.text('3 waiting'), findsOneWidget);
  });

  testWidgets('Home shows today card, readiness, and marks placeholder data', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Today · Day 1 of 4'), findsOneWidget);
    expect(find.text('Chest + Shoulders'), findsWidgets);
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Readiness check-in'), findsOneWidget);
    expect(find.text('Sample values'), findsWidgets);
  });

  testWidgets('Training sub-tabs switch the content', (tester) async {
    await _pumpApp(tester);
    await tester.tap(_navLabel('Training'));
    await tester.pumpAndSettle();

    // Quick actions is further down the Overview than the first screenful, so scroll to it.
    await tester.scrollUntilVisible(find.text('Quick actions'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Quick actions'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await _tapPill(tester, 'Splits');
    expect(find.text('Your splits'), findsOneWidget);
    await _tapPill(tester, 'Exercises');
    expect(find.text('Exercise library'), findsOneWidget);
    await _tapPill(tester, 'History');
    expect(find.textContaining('Finished workouts show up here'), findsOneWidget);
    await _tapPill(tester, 'Schedule');
    expect(find.text('Schedule · this week'), findsOneWidget);
  });

  testWidgets('Progress, Lifestyle and Reports sub-tabs switch the content', (tester) async {
    await _pumpApp(tester);

    await tester.tap(_navLabel('Progress'));
    await tester.pumpAndSettle();
    await _tapPill(tester, 'Goals');
    expect(find.text('Goal milestones'), findsOneWidget);

    await tester.tap(_navLabel('Lifestyle'));
    await tester.pumpAndSettle();
    await _tapPill(tester, 'Nutrition');
    expect(find.text('Nutrition today'), findsOneWidget);

    await tester.tap(_navLabel('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Performance overview'), findsOneWidget);
  });
}

class _FixedSync extends SyncStatusNotifier {
  _FixedSync(this._value);
  final SyncStatus _value;

  @override
  SyncStatus build() => _value;
}
