import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/auth/auth_service.dart';
import 'package:shaktikram/core/auth/session_controller.dart';
import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/routing/app_router.dart';

import 'support/fakes.dart';

Future<ProviderContainer> _start(Harness h) async {
  final container = ProviderContainer(overrides: h.overrides);
  addTearDown(container.dispose);
  container.read(sessionControllerProvider);
  await pumpEventQueue();
  return container;
}

SessionState _state(ProviderContainer c) => c.read(sessionControllerProvider);
SessionController _controller(ProviderContainer c) => c.read(sessionControllerProvider.notifier);

void main() {
  test('no stored session: signed out, and a device id is created', () async {
    final h = Harness.signedOut()..store.id = null;
    final c = await _start(h);

    expect(_state(c).phase, SessionPhase.signedOut);
    expect(h.store.id, isNotNull);
    expect(h.gateway.calls, isEmpty);
  });

  test('stored session and registration: opens ready without calling the server', () async {
    final h = Harness.ready();
    final c = await _start(h);

    expect(_state(c).phase, SessionPhase.ready);
    expect(_state(c).email, 'owner@example.com');
    expect(_state(c).deviceLabel, 'Test phone');
    expect(h.gateway.calls, isEmpty);
  });

  test('stored session but not registered: registers this device', () async {
    final h = Harness.signedInUnregistered();
    final c = await _start(h);

    expect(_state(c).phase, SessionPhase.ready);
    expect(h.gateway.calls, ['claimOwner', 'registerDevice:device-1:$defaultDeviceLabel']);
    expect(h.store.isRegistered, isTrue);
  });

  test('sign-in trims the email and device name, registers, and becomes ready', () async {
    final h = Harness.signedOut();
    final c = await _start(h);

    await _controller(c).signIn(email: ' owner@example.com ', password: 'secret', deviceLabel: '  Gym phone ');

    expect(h.auth.lastSignInEmail, 'owner@example.com');
    expect(h.gateway.calls, ['claimOwner', 'registerDevice:device-1:Gym phone']);
    expect(_state(c).phase, SessionPhase.ready);
    expect(h.store.labelValue, 'Gym phone');
    expect(h.store.isRegistered, isTrue);
  });

  test('wrong password: the failure reaches the caller and nothing is registered', () async {
    final h = Harness.signedOut();
    h.auth.signInError = const AuthFailure(AuthFailureKind.invalidCredentials);
    final c = await _start(h);

    await expectLater(
      _controller(c).signIn(email: 'owner@example.com', password: 'wrong'),
      throwsA(isA<AuthFailure>()),
    );
    expect(_state(c).phase, SessionPhase.signedOut);
    expect(h.gateway.calls, isEmpty);
  });

  test('registration fails offline, then retry succeeds', () async {
    final h = Harness.signedOut();
    h.gateway.registerError = const BackendError.unreachable();
    final c = await _start(h);

    await _controller(c).signIn(email: 'owner@example.com', password: 'secret');
    expect(_state(c).phase, SessionPhase.connecting);
    expect(_state(c).message, contains('Cannot reach the server'));
    expect(h.store.isRegistered, isFalse);

    h.gateway.registerError = null;
    await _controller(c).retry();
    expect(_state(c).phase, SessionPhase.ready);
    expect(_state(c).message, isNull);
    expect(h.store.isRegistered, isTrue);
  });

  test('a removed device ends in the revoked phase', () async {
    final h = Harness.signedOut();
    h.gateway.registerError = const BackendError('device_revoked', 'this device was revoked');
    final c = await _start(h);

    await _controller(c).signIn(email: 'owner@example.com', password: 'secret');
    expect(_state(c).phase, SessionPhase.revoked);
  });

  test('an account that is not the owner is signed out with a clear message', () async {
    final h = Harness.signedOut();
    h.gateway.claimError = const BackendError('unauthorized', 'this app already has an owner');
    final c = await _start(h);

    await _controller(c).signIn(email: 'someone@example.com', password: 'secret');
    expect(_state(c).phase, SessionPhase.signedOut);
    expect(_state(c).message, 'This account is not the owner of this app.');
    expect(h.auth.signOutCalls, 1);
    expect(h.gateway.calls, ['claimOwner']);
  });

  test('sign out clears the registration but keeps the device id', () async {
    final h = Harness.ready();
    final c = await _start(h);

    await _controller(c).signOut();
    expect(_state(c).phase, SessionPhase.signedOut);
    expect(h.auth.signOutCalls, 1);
    expect(h.store.isRegistered, isFalse);
    expect(h.store.id, 'device-1');
  });

  test('the server ending the session returns to sign-in with a notice', () async {
    final h = Harness.ready();
    final c = await _start(h);

    h.auth.endSessionFromServer();
    await pumpEventQueue();
    expect(_state(c).phase, SessionPhase.signedOut);
    expect(_state(c).message, contains('signed out'));
  });

  test('signing out of a removed device makes a new device id, so signing in again can work', () async {
    final h = Harness.ready();
    final c = await _start(h);

    _controller(c).markRevoked();
    await _controller(c).signOut();
    expect(_state(c).phase, SessionPhase.signedOut);
    expect(h.store.id, isNotNull);
    expect(h.store.id, isNot('device-1'));

    await _controller(c).signIn(email: 'owner@example.com', password: 'secret');
    expect(_state(c).phase, SessionPhase.ready);
    expect(_state(c).deviceId, h.store.id);
    expect(h.gateway.calls.last, startsWith('registerDevice:${h.store.id}'));
  });

  test('reRegisterDevice: registers quietly and stays ready', () async {
    final h = Harness.ready();
    final c = await _start(h);

    expect(await _controller(c).reRegisterDevice(), isTrue);
    expect(_state(c).phase, SessionPhase.ready);
    expect(h.gateway.calls, ['claimOwner', 'registerDevice:device-1:Test phone']);
  });

  test('reRegisterDevice: a removed device ends in revoked, and a failure is reported', () async {
    final h = Harness.ready();
    final c = await _start(h);

    h.gateway.registerError = const BackendError('device_revoked', 'this device was revoked');
    expect(await _controller(c).reRegisterDevice(), isFalse);
    expect(_state(c).phase, SessionPhase.revoked);

    final h2 = Harness.ready();
    final c2 = await _start(h2);
    h2.gateway.registerError = const BackendError.unreachable();
    expect(await _controller(c2).reRegisterDevice(), isFalse);
    expect(_state(c2).phase, SessionPhase.ready);
  });

  test('markRevoked moves a ready session to revoked', () async {
    final c = await _start(Harness.ready());

    _controller(c).markRevoked();
    expect(_state(c).phase, SessionPhase.revoked);
    expect(_state(c).deviceId, 'device-1');
  });

  group('sessionRedirect', () {
    test('ready: stay in the app, leave the gate screens', () {
      expect(sessionRedirect(SessionPhase.ready, AppRoutes.training), isNull);
      expect(sessionRedirect(SessionPhase.ready, AppRoutes.devices), isNull);
      for (final gate in AppRoutes.gateRoutes) {
        expect(sessionRedirect(SessionPhase.ready, gate), AppRoutes.home);
      }
    });

    test('every other phase is held on its own screen', () {
      expect(sessionRedirect(SessionPhase.checking, AppRoutes.home), AppRoutes.splash);
      expect(sessionRedirect(SessionPhase.checking, AppRoutes.splash), isNull);
      expect(sessionRedirect(SessionPhase.signedOut, AppRoutes.home), AppRoutes.signIn);
      expect(sessionRedirect(SessionPhase.signedOut, AppRoutes.signIn), isNull);
      expect(sessionRedirect(SessionPhase.connecting, AppRoutes.home), AppRoutes.connecting);
      expect(sessionRedirect(SessionPhase.revoked, AppRoutes.settings), AppRoutes.revoked);
    });
  });
}
