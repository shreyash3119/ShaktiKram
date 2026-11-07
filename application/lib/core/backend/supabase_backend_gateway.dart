import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend_error.dart';
import 'backend_gateway.dart';

/// Supabase RPC implementation of [BackendGateway].
class SupabaseBackendGateway implements BackendGateway {
  SupabaseBackendGateway(this._client);

  final SupabaseClient _client;

  /// Calls an RPC and returns the `data` part of the response envelope.
  Future<dynamic> _rpc(String function, [Map<String, dynamic>? params]) async {
    try {
      final response = await _client.rpc(function, params: params);
      if (response is Map && response.containsKey('data')) return response['data'];
      return response;
    } on PostgrestException catch (e) {
      throw BackendError.fromRaw(httpCode: e.code, message: e.message);
    } on AuthException catch (e) {
      throw BackendError('unauthorized', e.message);
    } catch (_) {
      throw const BackendError.unreachable();
    }
  }

  @override
  Future<void> claimOwner() async {
    await _rpc('api_claim_owner');
  }

  @override
  Future<DeviceRecord> registerDevice({required String id, required String label, required String platform}) async {
    final data = await _rpc('api_register_device', {'p_device_id': id, 'p_label': label, 'p_platform': platform});
    return DeviceRecord.fromJson(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<List<DeviceRecord>> listDevices() async {
    final data = await _rpc('api_list_devices');
    return (data as List).map((e) => DeviceRecord.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<DeviceRecord> revokeDevice(String id) async {
    final data = await _rpc('api_revoke_device', {'p_device_id': id});
    return DeviceRecord.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
