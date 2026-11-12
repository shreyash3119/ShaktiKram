import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/routing/app_shell.dart';
import 'package:shaktikram/core/widgets/controls.dart';

import 'support/fakes.dart';
import 'support/store_contract.dart';

Future<void> _open(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()));
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(AppBottomBar), matching: find.text('Progress')));
  await tester.pumpAndSettle();
}

Future<void> _pill(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(PillTabs).first, matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty phone shows empty states, not sample numbers', (tester) async {
    final h = Harness.ready();
    await _open(tester, h);
    expect(find.text('None yet'), findsOneWidget);
    expect(find.textContaining('Personal records are found by the server'), findsOneWidget);
    await _pill(tester, 'Goals');
    expect(find.text('No goals yet.'), findsOneWidget);
  });

  testWidgets('records and goals on the phone are shown, goal progress comes from the server', (tester) async {
    final h = Harness.ready();
    await h.local.applyPulled([
      pulled('personal_records', 1, {'id': uid(1), 'kind': 'max_weight', 'value': 85, 'achieved_on': '2026-11-10', 'session_id': uid(50), 'exercise_id': uid(60)}),
      pulled('goals', 2, {'id': uid(2), 'type': 'strength', 'title': 'Bench 90 kg', 'status': 'active', 'start_date': '2026-10-01', 'target_value': 90}),
    ], 2);
    h.gateway.viewRows['v_goal_progress'] = [
      {'goal_id': uid(2), 'title': 'Bench 90 kg', 'goal_status': 'active', 'progress_status': 'on_track', 'progress_pct': 80, 'reached': false, 'current_value': 85, 'target_value': 90},
    ];
    await _open(tester, h);
    expect(find.textContaining('Heaviest weight'), findsWidgets);
    await _pill(tester, 'Goals');
    expect(find.text('Bench 90 kg'), findsWidgets);
    expect(find.textContaining('On track (80%)'), findsOneWidget);
  });

  testWidgets('when the server cannot be reached the saved answer stays and is labelled offline', (tester) async {
    final h = Harness.ready();
    await h.local.applyPulled([
      pulled('goals', 1, {'id': uid(2), 'type': 'strength', 'title': 'Bench 90 kg', 'status': 'active', 'start_date': '2026-10-01'}),
    ], 1);
    await h.local.writeInsight('view:v_goal_progress', '[{"goal_id":"${uid(2)}","title":"Bench 90 kg","goal_status":"active","progress_status":"behind","progress_pct":40}]', DateTime.now().subtract(const Duration(hours: 5)));
    h.gateway.insightError = const BackendError.unreachable();
    await _open(tester, h);
    await _pill(tester, 'Goals');
    expect(find.textContaining('Behind (40%)'), findsOneWidget);
    expect(find.byKey(const Key('insight-status')), findsWidgets);
  });
}
