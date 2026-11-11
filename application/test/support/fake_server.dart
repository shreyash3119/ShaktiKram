import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/backend/backend_gateway.dart';
import 'package:shaktikram/core/db/entities.dart';
import 'package:shaktikram/core/db/sync_models.dart';

/// A stand-in for the real server that follows the rules of `pfs_dispatch` / `pfs_apply_op` / `api_pull_changes`
/// (backend `20261106000500_sync_core.sql`): global revisions, idempotent `op_id`, the three record classes, the
/// conflict rule, soft delete, and device checks. It lets the whole write path run in `flutter test` without Supabase.
/// It is only as right as that reading of the backend; the live check in Settings is what proves the real server.
class FakeServer implements BackendGateway {
  /// The server's clock. Tests move it forward.
  DateTime now = DateTime.utc(2026, 11, 10, 10);

  /// Fields that must be present when a record is created (stand-ins for NOT NULL columns).
  final Map<String, List<String>> requiredFields = {
    'meals': ['title', 'category'],
    'goals': ['type', 'title'],
    'body_measurements': ['occurred_at', 'local_date', 'measurement_type', 'value'],
  };

  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  final Map<String, Map<String, dynamic>> _opLog = {};
  final Map<String, DeviceRecord> _devices = {};
  int _rev = 0;
  int applyCalls = 0;

  /// Next response is lost after the server has already applied the request.
  bool dropNextResponse = false;

  /// Every request is refused as if the network were down.
  bool offline = false;

  Map<String, dynamic>? row(String entity, String id) => tables[entity]?[id];

  int get revision => _rev;

  void _requireOnline() {
    if (offline) throw const BackendError.unreachable();
  }

  void _requireDevice(String id) {
    final d = _devices[id];
    if (d == null) throw const BackendError('unauthorized', 'device is not registered');
    if (d.isRevoked) throw const BackendError('device_revoked', 'this device was revoked');
  }

  // ---- devices ----

  @override
  Future<void> claimOwner() async => _requireOnline();

  @override
  Future<DeviceRecord> registerDevice({required String id, required String label, required String platform}) async {
    _requireOnline();
    final old = _devices[id];
    if (old != null && old.isRevoked) throw const BackendError('device_revoked', 'this device was revoked');
    return _devices[id] = DeviceRecord(id: id, label: label, platform: platform);
  }

  @override
  Future<List<DeviceRecord>> listDevices() async {
    _requireOnline();
    return _devices.values.toList();
  }

  @override
  Future<DeviceRecord> revokeDevice(String id) async {
    _requireOnline();
    final d = _devices[id];
    if (d == null) throw const BackendError('not_found', 'device not found');
    return _devices[id] = DeviceRecord(id: d.id, label: d.label, platform: d.platform, revokedAt: now);
  }

  // ---- writes ----

  @override
  Future<List<OpResult>> applyOperations({
    required String deviceId,
    required String requestId,
    required List<OutboxOp> operations,
  }) async {
    _requireOnline();
    _requireDevice(deviceId);
    applyCalls++;
    final ordered = [...operations]..sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));
    final results = [for (final op in ordered) _applyOne(op, deviceId)];
    if (dropNextResponse) {
      dropNextResponse = false;
      throw const BackendError.unreachable();
    }
    return results;
  }

  OpResult _applyOne(OutboxOp op, String device) {
    final seen = _opLog[op.opId];
    if (seen != null) {
      return OpResult(
        opId: op.opId,
        result: 'duplicate',
        originalResult: seen['result'] as String,
        errorCode: seen['error_code'] as String?,
        rev: seen['rev'] as int?,
      );
    }
    String result;
    int? rev;
    String? code;
    String? message;
    try {
      final out = _dispatch(op, device);
      result = out.$1;
      rev = out.$2;
    } on BackendError catch (e) {
      result = 'rejected';
      code = e.code;
      message = e.message;
    }
    _opLog[op.opId] = {'result': result, 'rev': rev, 'error_code': code};
    return OpResult(opId: op.opId, result: result, rev: rev, errorCode: code, message: message);
  }

  (String, int?) _dispatch(OutboxOp op, String device) {
    final info = syncedEntities[op.entity];
    if (info == null || !info.clientWritable) {
      throw BackendError('validation_failed', 'unknown or read-only entity ${op.entity}');
    }
    for (final key in ['rev', 'created_at', 'updated_at', 'device_id', 'deleted_at']) {
      if (op.payload.containsKey(key)) throw BackendError('validation_failed', 'unknown or protected field(s): $key');
    }
    final table = tables.putIfAbsent(op.entity, () => {});
    final clientTime = op.clientUpdatedAt.isAfter(now.add(const Duration(minutes: 5))) ? now.add(const Duration(minutes: 5)) : op.clientUpdatedAt;

    if (op.action == 'new_version') {
      if (info.recordClass != RecordClass.versioned) {
        throw BackendError('validation_failed', '${op.entity} is not a versioned table');
      }
      final entityId = op.payload['entity_id'] as String?;
      if (entityId == null) throw const BackendError('validation_failed', 'entity_id is required');
      final versions = table.values.where((r) => r['entity_id'] == entityId && r['deleted_at'] == null).toList()
        ..sort((a, b) => (b['version'] as int).compareTo(a['version'] as int));
      final id = (op.payload['id'] as String?) ?? 'v-${table.length + 1}';
      if (versions.isNotEmpty) {
        final current = versions.first;
        final from = op.payload['effective_from'] != null ? DateTime.parse(op.payload['effective_from'] as String) : now;
        if (current['effective_to'] == null) {
          if (from.isBefore(DateTime.parse(current['effective_from'] as String))) {
            throw const BackendError('version_conflict', 'a new version cannot start before the current one');
          }
          current['effective_to'] = from.toUtc().toIso8601String();
          current['rev'] = ++_rev;
        }
      }
      table[id] = _stamp({
        ...op.payload,
        'id': id,
        'version': (versions.isEmpty ? 0 : versions.first['version'] as int) + 1,
        'effective_from': op.payload['effective_from'] ?? now.toIso8601String(),
        'effective_to': null,
      }, device, created: true);
      return ('applied', table[id]!['rev'] as int);
    }

    final id = op.recordId;
    if (id == null) throw const BackendError('validation_failed', 'record_id is required');
    final existing = table[id];

    if (op.action == 'upsert') {
      if (info.recordClass == RecordClass.versioned) {
        throw const BackendError('validation_failed', 'use new_version for versioned tables');
      }
      if (existing == null) {
        for (final field in requiredFields[op.entity] ?? const <String>[]) {
          if (op.payload[field] == null) throw BackendError('validation_failed', 'null value in column $field');
        }
        table[id] = _stamp({...op.payload, 'id': id}, device, created: true);
        return ('applied', table[id]!['rev'] as int);
      }
      final base = op.baseRev;
      final current = existing['rev'] as int;
      if (base == null || (info.recordClass == RecordClass.appendOnly && base != current)) return ('duplicate', current);
      if (_conflicts(info, existing, base, device, clientTime)) return ('conflict', current);
      existing.addAll({...op.payload}..remove('id'));
      _touch(existing, device);
      return ('applied', existing['rev'] as int);
    }

    if (op.action == 'delete') {
      if (info.recordClass == RecordClass.versioned) {
        throw const BackendError('immutable_record', 'version rows cannot be deleted');
      }
      if (existing == null) throw BackendError('not_found', '${op.entity} $id does not exist');
      if (op.baseRev != null && _conflicts(info, existing, op.baseRev!, device, clientTime)) {
        return ('conflict', existing['rev'] as int);
      }
      if (existing['deleted_at'] == null) {
        existing['deleted_at'] = now.toIso8601String();
        _touch(existing, device);
      }
      return ('applied', existing['rev'] as int);
    }
    throw BackendError('validation_failed', 'unknown action ${op.action}');
  }

  /// A conflict needs a different device to have written the row since base_rev, and the server copy to be at least
  /// as new as the client's change.
  bool _conflicts(EntityInfo info, Map<String, dynamic> existing, int base, String device, DateTime clientTime) {
    return info.recordClass == RecordClass.editable &&
        base < (existing['rev'] as int) &&
        existing['device_id'] != device &&
        !clientTime.isAfter(DateTime.parse(existing['updated_at'] as String));
  }

  Map<String, dynamic> _stamp(Map<String, dynamic> record, String device, {required bool created}) {
    if (created) record['created_at'] = now.toIso8601String();
    record['deleted_at'] = null;
    _touch(record, device);
    return record;
  }

  void _touch(Map<String, dynamic> record, String device) {
    record['rev'] = ++_rev;
    record['updated_at'] = now.toIso8601String();
    record['device_id'] = device;
  }

  // ---- pull ----

  @override
  Future<PullPage> pullChanges({required String deviceId, required int sinceRev, int limit = 200}) async {
    _requireOnline();
    _requireDevice(deviceId);
    final all = <PulledRow>[
      for (final t in tables.entries)
        for (final r in t.value.values)
          if ((r['rev'] as int) > sinceRev) PulledRow(entity: t.key, rev: r['rev'] as int, record: Map<String, dynamic>.from(r)),
    ]..sort((a, b) => a.rev.compareTo(b.rev));
    final more = all.length > limit;
    final rows = more ? all.sublist(0, limit) : all;
    return PullPage(rows: rows, nextRev: rows.isEmpty ? sinceRev : rows.last.rev, hasMore: more);
  }
}
