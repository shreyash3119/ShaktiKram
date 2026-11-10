import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/sync_models.dart';

/// One row of the server's `devices` table.
class DeviceRecord {
  const DeviceRecord({
    required this.id,
    required this.label,
    required this.platform,
    this.createdAt,
    this.lastSeenAt,
    this.revokedAt,
  });

  final String id;
  final String label;
  final String platform;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;

  factory DeviceRecord.fromJson(Map<String, dynamic> json) {
    DateTime? when(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return DeviceRecord(
      id: json['id'] as String,
      label: (json['label'] as String?) ?? '',
      platform: (json['platform'] as String?) ?? 'mobile',
      createdAt: when(json['created_at']),
      lastSeenAt: when(json['last_seen_at']),
      revokedAt: when(json['revoked_at']),
    );
  }
}

/// The server calls the app uses for sign-in and device management (contract: stage1_functions.md).
/// Implementations throw [BackendError]. Only `core/backend` talks to Supabase.
abstract class BackendGateway {
  /// `api_claim_owner`. Safe to repeat for the owner.
  Future<void> claimOwner();

  /// `api_register_device`. Safe to repeat. Also renames the device.
  Future<DeviceRecord> registerDevice({required String id, required String label, required String platform});

  /// `api_list_devices`.
  Future<List<DeviceRecord>> listDevices();

  /// `api_revoke_device`.
  Future<DeviceRecord> revokeDevice(String id);

  /// `api_apply_operations`: sends queued changes (at most 500). One result per operation.
  /// [requestId] is new for each call.
  Future<List<OpResult>> applyOperations({
    required String deviceId,
    required String requestId,
    required List<OutboxOp> operations,
  });

  /// `api_pull_changes`: changed rows after [sinceRev], at most [limit] (1 to 500).
  Future<PullPage> pullChanges({required String deviceId, required int sinceRev, int limit = 200});
}

/// Replaced in `main.dart` (and in tests).
final backendGatewayProvider = Provider<BackendGateway>((ref) {
  throw UnimplementedError('backendGatewayProvider must be overridden');
});
