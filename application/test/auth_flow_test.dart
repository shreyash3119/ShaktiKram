import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/app.dart';
import 'package:shaktikram/core/auth/auth_service.dart';
import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/backend/backend_gateway.dart';

import 'support/fakes.dart';

Future<void> _pump(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(ProviderScope(overrides: h.overrides, child: const ShaktiKramApp()));
  await tester.pumpAndSettle();
}

Finder _navLabel(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
Finder _appBarTitle(String title) => find.descendant(of: find.byType(AppBar), matching: find.text(title));

Future<void> _fillAndSubmit(WidgetTester tester, {String email = 'owner@example.com', String password = 'secret'}) async {
  await tester.enterText(find.byKey(const Key('email-field')), email);
  await tester.enterText(find.byKey(const Key('password-field')), password);
  await tester.tap(find.byKey(const Key('sign-in-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no session: the sign-in screen shows, with no way to create an account', (tester) async {
    await _pump(tester, Harness.signedOut());

    expect(find.byKey(const Key('sign-in-button')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.textContaining('Create account'), findsNothing);
    expect(find.textContaining('Sign up'), findsNothing);
    expect(find.textContaining('Register'), findsNothing);
  });

  testWidgets('empty fields are checked before anything is sent', (tester) async {
    final h = Harness.signedOut();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('sign-in-button')));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(h.auth.signInCalls, 0);
  });

  testWidgets('signing in registers the device and opens Home', (tester) async {
    final h = Harness.signedOut();
    await _pump(tester, h);

    await _fillAndSubmit(tester);

    expect(_appBarTitle('Home'), findsOneWidget);
    expect(h.gateway.calls, ['claimOwner', 'registerDevice:device-1:Android phone']);
  });

  testWidgets('a wrong password shows a message and stays on sign-in', (tester) async {
    final h = Harness.signedOut();
    h.auth.signInError = const AuthFailure(AuthFailureKind.invalidCredentials);
    await _pump(tester, h);

    await _fillAndSubmit(tester, password: 'wrong');

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(find.byKey(const Key('sign-in-button')), findsOneWidget);
    expect(h.gateway.calls, isEmpty);
  });

  testWidgets('registration failing offline shows a retry, and retry opens Home', (tester) async {
    final h = Harness.signedOut();
    h.gateway.registerError = const BackendError.unreachable();
    await _pump(tester, h);

    await _fillAndSubmit(tester);
    expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    h.gateway.registerError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(_appBarTitle('Home'), findsOneWidget);
  });

  testWidgets('a removed device sees the revoked screen', (tester) async {
    final h = Harness.signedOut();
    h.gateway.registerError = const BackendError('device_revoked', 'this device was revoked');
    await _pump(tester, h);

    await _fillAndSubmit(tester);
    expect(find.text('This device was removed'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('a registered phone opens straight to Home with no sign-in and no server call', (tester) async {
    final h = Harness.ready();
    await _pump(tester, h);

    expect(_appBarTitle('Home'), findsOneWidget);
    expect(find.byKey(const Key('sign-in-button')), findsNothing);
    expect(h.gateway.calls, isEmpty);
  });

  testWidgets('Settings shows the account and device, and sign out returns to sign-in', (tester) async {
    final h = Harness.ready();
    await _pump(tester, h);

    await tester.tap(_navLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('owner@example.com'), findsOneWidget);
    expect(find.text('Test phone'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sign-out-tile')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Sign out')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sign-in-button')), findsOneWidget);
    expect(h.auth.signOutCalls, 1);
  });

  testWidgets('Devices lists devices and removes another one after confirming', (tester) async {
    final h = Harness.ready();
    h.gateway.devices = [
      const DeviceRecord(id: 'device-1', label: 'Test phone', platform: 'mobile'),
      const DeviceRecord(id: 'device-2', label: 'Old phone', platform: 'mobile'),
    ];
    await _pump(tester, h);

    await tester.tap(_navLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage devices'));
    await tester.pumpAndSettle();

    expect(_appBarTitle('Devices'), findsOneWidget);
    expect(find.text('Old phone'), findsOneWidget);
    expect(find.textContaining('Active · This device'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Remove'), findsOneWidget, reason: 'this device cannot be removed here');

    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Remove')));
    await tester.pumpAndSettle();

    expect(h.gateway.calls, contains('revoke:device-2'));
    expect(find.textContaining('Removed'), findsOneWidget);
  });

  testWidgets('Devices shows an error with retry when the list cannot load', (tester) async {
    final h = Harness.ready();
    h.gateway.listError = const BackendError.unreachable();
    await _pump(tester, h);

    await tester.tap(_navLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage devices'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot reach the server'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
