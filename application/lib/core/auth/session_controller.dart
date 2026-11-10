import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/backend_error.dart';
import '../backend/backend_gateway.dart';
import 'auth_service.dart';
import 'device_store.dart';
import 'uuid.dart';

/// Where the owner is in the sign-in and device set-up flow.
enum SessionPhase {
  /// Reading what is stored on this device.
  checking,

  /// No session. Show the sign-in screen.
  signedOut,

  /// Signed in, registering this device. If [SessionState.message] is set, the attempt failed and can be retried.
  connecting,

  /// Signed in and registered. The app is usable, offline or online.
  ready,

  /// The owner removed this device from the server.
  revoked,
}

const defaultDeviceLabel = 'Android phone';

class SessionState {
  const SessionState({
    required this.phase,
    this.email,
    this.deviceId,
    this.deviceLabel,
    this.message,
  });

  const SessionState.checking() : this(phase: SessionPhase.checking);

  final SessionPhase phase;
  final String? email;
  final String? deviceId;
  final String? deviceLabel;

  /// A problem or notice for the current screen.
  final String? message;
}

/// Owns sign-in, device registration and sign-out.
///
/// Offline start: if a session and a completed registration are stored, the app opens as [SessionPhase.ready]
/// without calling the server. The server is only needed for the first sign-in and registration.
class SessionController extends Notifier<SessionState> {
  String? _deviceId;

  /// True while this controller is signing out itself, so the resulting auth event is not treated as a surprise.
  bool _signingOut = false;

  AuthService get _auth => ref.read(authServiceProvider);
  BackendGateway get _gateway => ref.read(backendGatewayProvider);
  DeviceStore get _store => ref.read(deviceStoreProvider);

  @override
  SessionState build() {
    final subscription = _auth.signedInChanges.listen(_onAuthChanged);
    ref.onDispose(subscription.cancel);
    Future.microtask(_start);
    return const SessionState.checking();
  }

  void _onAuthChanged(bool signedIn) {
    if (signedIn || _signingOut) return;
    final phase = state.phase;
    if (phase == SessionPhase.checking || phase == SessionPhase.signedOut) return;
    unawaited(_toSignedOut(message: 'You were signed out. Sign in again.'));
  }

  Future<String> _loadDeviceId() async {
    final existing = _deviceId ?? await _store.deviceId();
    if (existing != null) return _deviceId = existing;
    final created = newUuidV4();
    await _store.saveDeviceId(created);
    return _deviceId = created;
  }

  Future<void> _start() async {
    final id = await _loadDeviceId();
    if (!_auth.hasSession) {
      state = const SessionState(phase: SessionPhase.signedOut);
      return;
    }
    if (await _store.registered()) {
      state = SessionState(
        phase: SessionPhase.ready,
        email: _auth.email,
        deviceId: id,
        deviceLabel: await _store.label() ?? defaultDeviceLabel,
      );
      return;
    }
    await _connect();
  }

  /// Signs in, then registers this device. Throws [AuthFailure] if the sign-in fails.
  /// If registration fails afterwards, the state becomes [SessionPhase.connecting] with a message.
  Future<void> signIn({required String email, required String password, String? deviceLabel}) async {
    await _auth.signIn(email: email.trim(), password: password);
    final label = deviceLabel?.trim();
    await _connect(label: (label == null || label.isEmpty) ? null : label);
  }

  /// Tries the registration again after a failure.
  Future<void> retry() => _connect();

  Future<void> _connect({String? label}) async {
    final id = await _loadDeviceId();
    final deviceLabel = label ?? await _store.label() ?? defaultDeviceLabel;
    state = SessionState(phase: SessionPhase.connecting, email: _auth.email, deviceId: id, deviceLabel: deviceLabel);
    try {
      await _gateway.claimOwner();
      await _gateway.registerDevice(id: id, label: deviceLabel, platform: 'mobile');
      await _store.saveLabel(deviceLabel);
      await _store.setRegistered(true);
      state = SessionState(phase: SessionPhase.ready, email: _auth.email, deviceId: id, deviceLabel: deviceLabel);
    } on BackendError catch (e) {
      if (e.isNotOwner) {
        await _toSignedOut(message: 'This account is not the owner of this app.');
      } else if (e.isDeviceRevoked) {
        state = SessionState(phase: SessionPhase.revoked, email: _auth.email, deviceId: id, deviceLabel: deviceLabel);
      } else {
        state = SessionState(
          phase: SessionPhase.connecting,
          email: _auth.email,
          deviceId: id,
          deviceLabel: deviceLabel,
          message: e.userMessage,
        );
      }
    }
  }

  /// Signs out of this device. The device id is kept so signing in again reuses it,
  /// except after the owner removed this device: the server never accepts a removed id again, so a new one is made.
  Future<void> signOut() => _toSignedOut();

  /// Registers this device again without leaving the app, for when the server does not know it
  /// (for example after the server data was reset). Returns true when the device is registered.
  Future<bool> reRegisterDevice() async {
    final id = await _loadDeviceId();
    final label = state.deviceLabel ?? await _store.label() ?? defaultDeviceLabel;
    try {
      await _gateway.claimOwner();
      await _gateway.registerDevice(id: id, label: label, platform: 'mobile');
      await _store.setRegistered(true);
      return true;
    } on BackendError catch (e) {
      if (e.isNotOwner) {
        await _toSignedOut(message: 'This account is not the owner of this app.');
      } else if (e.isDeviceRevoked) {
        markRevoked();
      }
      return false;
    }
  }

  Future<void> _toSignedOut({String? message}) async {
    _signingOut = true;
    try {
      if (state.phase == SessionPhase.revoked) {
        final fresh = newUuidV4();
        await _store.saveDeviceId(fresh);
        _deviceId = fresh;
      }
      try {
        await _auth.signOut();
      } catch (_) {
        // The local session is cleared even when the server cannot be reached.
      }
      await _store.setRegistered(false);
      state = SessionState(phase: SessionPhase.signedOut, message: message);
    } finally {
      _signingOut = false;
    }
  }

  /// Called when the server answers `device_revoked` (the sync client does this in the next step).
  void markRevoked() {
    state = SessionState(
      phase: SessionPhase.revoked,
      email: state.email,
      deviceId: state.deviceId,
      deviceLabel: state.deviceLabel,
    );
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);
