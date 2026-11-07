import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

/// Replaced in `main.dart` (and in tests).
final backendGatewayProvider = Provider<BackendGateway>((ref) {
  throw UnimplementedError('backendGatewayProvider must be overridden');
});
