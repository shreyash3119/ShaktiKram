import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/time/local_stamp.dart';

import 'support/fakes.dart';
import 'support/store_contract.dart';

Future<void> _open(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _briefing(String date) => {
  'date': date,
  'plan': {'status': 'planned', 'is_rest_day': false, 'planned_exercises': 5},
  'readiness': {
    'level': 'moderate',
    'reasoning': ['You logged 5.5 hours of sleep.'],
    'note': 'Decision support only.',
    'value_kind': 'suggestion',
  },
  'deload': {'level': 'none', 'reasoning': []},
  'streak': {'current_streak': 4, 'longest_streak': 9},
  'trends': [
    {'exercise': 'Squat', 'signal': 'plateau', 'change_pct': 0.4},
  ],
};

void main() {
  testWidgets('Home shows the server briefing with its freshness line', (
    tester,
  ) async {
    final h = Harness.ready();
    final today = localStampOf(DateTime.now()).localDate;
    h.gateway.insightAnswers['api_daily_briefing'] = _briefing(today);

    await _open(tester, h);

    expect(find.byKey(const Key('readiness-level')), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);

    // The reasons are one tap away, in the readiness dialog.
    await tester.tap(find.byKey(const Key('readiness-dial')));
    await tester.pumpAndSettle();
    expect(find.text('You logged 5.5 hours of sleep.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dialog-close')));
    await tester.pumpAndSettle();

    // Scroll to the Insights card before checking its contents.
    await tester.scrollUntilVisible(
      find.byKey(const Key('home-insights')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Squat: Plateau'), findsOneWidget);
    expect(find.byKey(const Key('insight-status')), findsWidgets);
    expect(find.text('Decision support only, not medical advice.'), findsOneWidget);
  });

  testWidgets('offline, Home keeps the saved briefing and says so', (
    tester,
  ) async {
    final h = Harness.ready();
    final today = localStampOf(DateTime.now()).localDate;
    await h.local.writeInsight(
      'daily_briefing:$today',
      '{"date":"$today","readiness":{"level":"low","reasoning":[]}}',
      DateTime.now().subtract(const Duration(hours: 3)),
    );
    h.gateway.insightError = const BackendError.unreachable();
    await _open(tester, h);

    expect(find.text('Low'), findsOneWidget);
    expect(find.textContaining('Offline'), findsWidgets);
  });

  testWidgets('an unfinished session on the phone shows as a notification', (
    tester,
  ) async {
    final h = Harness.ready();

    await h.local.applyPulled([
      pulled('workout_sessions', 1, {
        'id': uid(1),
        'occurred_at': DateTime.now().toUtc().toIso8601String(),
        'local_date': localStampOf(DateTime.now()).localDate,
        'status': 'in_progress',
        'name': 'Push A',
      }),
    ], 1);

    await _open(tester, h);

    expect(find.text('Resume workout'), findsOneWidget);

    // The bell counts it, and the notifications dialog lists it.
    expect(
      find.descendant(
        of: find.byKey(const Key('home-bell-badge')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('home-bell')));
    await tester.pumpAndSettle();
    expect(find.text('Unfinished session'), findsOneWidget);
  });
}
