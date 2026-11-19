import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/routing/app_shell.dart';
import 'package:shaktikram/core/widgets/section_widgets.dart';

import 'support/fakes.dart';

Future<void> _open(WidgetTester tester) async {
  final h = Harness.ready();
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()),
  );
  await tester.pumpAndSettle();
}

int _main(WidgetTester tester) =>
    tester.widget<AppBottomBar>(find.byType(AppBottomBar)).currentIndex;

int _sub(WidgetTester tester) =>
    tester.widget<UnderlineTabs>(find.byType(UnderlineTabs)).index;

/// A swipe on the page itself, above the bottom bar.
Future<void> _swipePage(WidgetTester tester, {required bool left, double distance = 300}) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.flingFrom(
    Offset(size.width / 2, size.height / 2),
    Offset(left ? -distance : distance, 0),
    1500,
  );
  await tester.pumpAndSettle();
}

Future<void> _tapNav(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(Key('nav-$label')));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sections without sub-tabs swipe between main tabs', (tester) async {
    await _open(tester);
    expect(_main(tester), 0);
    await _swipePage(tester, left: false); // before the first tab: nothing
    expect(_main(tester), 0);
    await _swipePage(tester, left: true);
    expect(_main(tester), 1);

    await _tapNav(tester, 'Settings');
    expect(_main(tester), 5);
    await _swipePage(tester, left: true); // after the last tab: nothing
    expect(_main(tester), 5);
    await _swipePage(tester, left: false);
    expect(_main(tester), 4);
  });

  testWidgets('a section with sub-tabs swipes its sub-tabs and never the main tab', (tester) async {
    await _open(tester);
    await _tapNav(tester, 'Training');
    expect(_sub(tester), 0);
    await _swipePage(tester, left: false); // before the first sub-tab: nothing
    expect(_main(tester), 1);
    expect(_sub(tester), 0);

    await _swipePage(tester, left: true);
    expect(_sub(tester), 1);
    expect(_main(tester), 1);
    await _swipePage(tester, left: false);
    expect(_sub(tester), 0);

    for (var i = 0; i < 6; i++) {
      await _swipePage(tester, left: true);
    }
    expect(_sub(tester), 4); // the last sub-tab; more swipes do not leave Training
    expect(_main(tester), 1);
  });

  testWidgets('tapping a sub-tab and swiping stay in step', (tester) async {
    await _open(tester);
    await _tapNav(tester, 'Training');
    await tester.tap(find.byKey(const Key('tab-Exercises')));
    await tester.pumpAndSettle();
    expect(_sub(tester), 2);
    await _swipePage(tester, left: true);
    expect(_sub(tester), 3);
  });

  testWidgets('a small drag does not navigate', (tester) async {
    await _open(tester);
    await tester.dragFrom(const Offset(200, 300), const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(_main(tester), 0);
  });

  testWidgets('each section keeps its sub-tab when you switch away and back', (tester) async {
    await _open(tester);
    await _tapNav(tester, 'Training');
    await _swipePage(tester, left: true);
    await _swipePage(tester, left: true);
    expect(_sub(tester), 2);
    await _tapNav(tester, 'Progress');
    expect(_main(tester), 2);
    await _tapNav(tester, 'Training');
    expect(_sub(tester), 2);
  });

  testWidgets('Back: sub-tab -> first sub-tab -> Home, then twice to exit', (tester) async {
    var exits = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _open(tester);
    await _tapNav(tester, 'Training');
    await _swipePage(tester, left: true);
    await _swipePage(tester, left: true);
    expect(_sub(tester), 2);

    await _back(tester);
    expect(_sub(tester), 0);
    expect(_main(tester), 1);

    await _back(tester);
    expect(_main(tester), 0);
    expect(find.text('Press back again to exit.'), findsNothing);
    expect(exits, 0);

    await _back(tester); // first Back on Home
    expect(find.text('Press back again to exit.'), findsOneWidget);
    expect(exits, 0);
    await _back(tester); // second, within two seconds
    expect(exits, 1);
  });

  testWidgets('the exit message appears again once the two seconds have passed', (tester) async {
    await _open(tester);
    await _back(tester);
    expect(find.text('Press back again to exit.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await _back(tester);
    expect(find.text('Press back again to exit.'), findsOneWidget);
  });

  testWidgets('Back closes a dialog first', (tester) async {
    await _open(tester);
    await _tapNav(tester, 'Progress');
    await tester.tap(find.byKey(const Key('progress-info')));
    await tester.pumpAndSettle();
    expect(find.text('About these numbers'), findsWidgets);
    await _back(tester);
    expect(find.text('About these numbers'), findsNothing);
    expect(_main(tester), 2);
  });
}
