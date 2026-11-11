import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shaktikram/core/auth/auth_service.dart';
import 'package:shaktikram/core/auth/device_store.dart';
import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/backend/backend_gateway.dart';
import 'package:shaktikram/core/db/local_store.dart';
import 'package:shaktikram/core/db/sync_models.dart';

import 'memory_local_store.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({this.hasSession = false, this.email});

  @override
  bool hasSession;

  @override
  String? email;

  /// Set to make the next sign-in fail.
  Object? signInError;

  int signInCalls = 0;
  int signOutCalls = 0;
  String? lastSignInEmail;

  final _changes = StreamController<bool>.broadcast();

  @override
  Stream<bool> get signedInChanges => _changes.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    lastSignInEmail = email;
    final error = signInError;
    if (error != null) throw error;
    hasSession = true;
    this.email = email;
    _changes.add(true);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    hasSession = false;
    email = null;
    _changes.add(false);
  }

  /// Simulates the server ending the session (for example a rejected refresh token).
  void endSessionFromServer() {
    hasSession = false;
    _changes.add(false);
  }
}

class FakeGateway implements BackendGateway {
  final List<String> calls = [];

  BackendError? claimError;
  BackendError? registerError;
  BackendError? listError;
  List<DeviceRecord> devices = [];

  /// Sync: errors to throw, answers to give, and a record of what was sent.
  BackendError? applyError;

  /// Simulates a server that accepts sync again once the device is registered.
  bool clearApplyErrorOnRegister = false;
  BackendError? pullError;
  final List<List<OutboxOp>> sentBatches = [];
  final List<int> pullSince = [];

  /// Makes the Nth call to [pullChanges] fail as if the network dropped (1 is the first call).
  int? failPullAtCall;
  int _pullCalls = 0;

  /// Answer for an operation id. Default is applied with rev 1.
  OpResult Function(OutboxOp op) onApply = (op) => OpResult(opId: op.opId, result: 'applied', rev: 1);

  /// Pages handed out by [pullChanges], in order. When empty, an empty final page is returned.
  final List<PullPage> pullPages = [];

  @override
  Future<void> claimOwner() async {
    calls.add('claimOwner');
    final error = claimError;
    if (error != null) throw error;
  }

  @override
  Future<DeviceRecord> registerDevice({required String id, required String label, required String platform}) async {
    calls.add('registerDevice:$id:$label');
    if (clearApplyErrorOnRegister) applyError = null;
    final error = registerError;
    if (error != null) throw error;
    return DeviceRecord(id: id, label: label, platform: platform);
  }

  @override
  Future<List<DeviceRecord>> listDevices() async {
    calls.add('listDevices');
    final error = listError;
    if (error != null) throw error;
    return List.of(devices);
  }

  @override
  Future<DeviceRecord> revokeDevice(String id) async {
    calls.add('revoke:$id');
    final index = devices.indexWhere((d) => d.id == id);
    final old = devices[index];
    final revoked = DeviceRecord(
      id: old.id,
      label: old.label,
      platform: old.platform,
      lastSeenAt: old.lastSeenAt,
      revokedAt: DateTime.utc(2026, 11, 7),
    );
    devices[index] = revoked;
    return revoked;
  }

  @override
  Future<List<OpResult>> applyOperations({
    required String deviceId,
    required String requestId,
    required List<OutboxOp> operations,
  }) async {
    calls.add('apply:${operations.length}');
    final error = applyError;
    if (error != null) throw error;
    sentBatches.add(List.of(operations));
    return [for (final op in operations) onApply(op)];
  }

  @override
  Future<PullPage> pullChanges({required String deviceId, required int sinceRev, int limit = 200}) async {
    calls.add('pull:$sinceRev');
    final error = pullError;
    if (error != null) throw error;
    if (failPullAtCall == ++_pullCalls) throw const BackendError.unreachable();
    pullSince.add(sinceRev);
    if (pullPages.isEmpty) return PullPage(rows: const [], nextRev: sinceRev, hasMore: false);
    return pullPages.removeAt(0);
  }
}

class InMemoryDeviceStore implements DeviceStore {
  InMemoryDeviceStore({this.id, this.labelValue, this.isRegistered = false});

  String? id;
  String? labelValue;
  bool isRegistered;

  @override
  Future<String?> deviceId() async => id;

  @override
  Future<void> saveDeviceId(String value) async => id = value;

  @override
  Future<String?> label() async => labelValue;

  @override
  Future<void> saveLabel(String value) async => labelValue = value;

  @override
  Future<bool> registered() async => isRegistered;

  @override
  Future<void> setRegistered(bool value) async => isRegistered = value;
}

/// A signed-in, registered phone: the app opens straight to Home without calling the server.
class Harness {
  Harness.ready()
      : auth = FakeAuthService(hasSession: true, email: 'owner@example.com'),
        gateway = FakeGateway(),
        store = InMemoryDeviceStore(id: 'device-1', labelValue: 'Test phone', isRegistered: true);

  /// No session stored: the sign-in screen opens.
  Harness.signedOut()
      : auth = FakeAuthService(),
        gateway = FakeGateway(),
        store = InMemoryDeviceStore(id: 'device-1');

  /// A session exists but this device is not registered yet.
  Harness.signedInUnregistered()
      : auth = FakeAuthService(hasSession: true, email: 'owner@example.com'),
        gateway = FakeGateway(),
        store = InMemoryDeviceStore(id: 'device-1');

  final FakeAuthService auth;
  final FakeGateway gateway;
  final InMemoryDeviceStore store;
  final MemoryLocalStore local = MemoryLocalStore();

  List<Override> get overrides => overridesWith(gateway);

  /// The same app set-up, talking to another backend (for example the fake server).
  List<Override> overridesWith(BackendGateway backend) => [
        localStoreProvider.overrideWithValue(local),
        authServiceProvider.overrideWithValue(auth),
        backendGatewayProvider.overrideWithValue(backend),
        deviceStoreProvider.overrideWithValue(store),
      ];
}
