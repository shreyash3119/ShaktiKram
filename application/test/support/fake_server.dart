import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/backend/backend_gateway.dart';
import 'package:shaktikram/core/db/entities.dart';
import 'package:shaktikram/core/db/sync_models.dart';

/// A stand-in for the real server that follows the rules of `pfs_dispatch` / `pfs_apply_op` / `api_pull_changes`
/// (backend `20261106000500_sync_core.sql`): global revisions, idempotent `op_id`, the three record classes, the
/// conflict rule, soft delete, and device checks. It lets the whole write path run in `flutter test` without Supabase.
/// It is only as right as that reading of the backend; the live check in Settings is what proves the real server.
class FakeServer implements BackendGateway {
  /// Answers for the read-only insight functions and views; tests fill these in.
  final Map<String, Object?> insightAnswers = {};
  final Map<String, List<Map<String, dynamic>>> viewRows = {};

  @override
  Future<Object?> callInsight(String function, {Map<String, dynamic>? params}) async {
    if (offline) throw const BackendError.unreachable();
    return insightAnswers[function];
  }

  @override
  Future<List<Map<String, dynamic>>> readView(String view, {Map<String, Object>? equals, String? orderBy, bool descending = false, int? limit}) async {
    if (offline) throw const BackendError.unreachable();
    return viewRows[view] ?? const [];
  }

  /// The server's clock. Tests move it forward.
  DateTime now = DateTime.utc(2026, 11, 10, 10);

  /// Fields that must be present when a record is created (stand-ins for NOT NULL columns).
  final Map<String, List<String>> requiredFields = {
    'meals': ['title', 'category'],
    'goals': ['type', 'title'],
    'body_measurements': ['occurred_at', 'local_date', 'measurement_type', 'value'],
    'workout_sessions': ['occurred_at', 'local_date', 'tz_offset_minutes'],
    'session_exercises': ['session_id', 'exercise_id', 'position'],
    'sets': ['session_exercise_id', 'set_number', 'occurred_at', 'local_date', 'tz_offset_minutes'],
  };

  /// Column defaults applied when a record is created.
  final Map<String, Map<String, dynamic>> defaults = {
    'workout_sessions': {'status': 'in_progress', 'paused_seconds': 0},
    'session_exercises': {'status': 'done'},
    'sets': {'set_type': 'working', 'completed': true},
  };

  /// Foreign keys the database enforces: entity, field, parent table.
  final Map<String, Map<String, String>> foreignKeys = {
    'workout_sessions': {
      'schedule_entry_id': 'schedule_entries',
      'split_version_id': 'split_versions',
      'split_day_id': 'split_days',
      'template_version_id': 'template_versions',
    },
    'session_exercises': {
      'session_id': 'workout_sessions',
      'exercise_id': 'exercises',
      'template_exercise_id': 'template_exercises',
    },
    'sets': {'session_exercise_id': 'session_exercises'},
    'schedule_entries': {'session_id': 'workout_sessions'},
    'injuries': {'body_region_id': 'body_regions'},
    'injury_updates': {'injury_id': 'injuries'},
    'pain_entries': {'body_region_id': 'body_regions', 'injury_id': 'injuries', 'checkin_id': 'daily_checkins'},
    'exercise_restrictions': {'injury_id': 'injuries', 'exercise_id': 'exercises'},
    'supplement_phases': {'entity_id': 'supplements'},
    'supplement_logs': {'supplement_id': 'supplements', 'phase_id': 'supplement_phases'},
    'meal_plan_entries': {'meal_id': 'meals', 'replaced_by_meal_id': 'meals'},
  };

  /// Puts a record on the server as if it had been there already (reference data, a plan made earlier).
  void seed(String entity, Map<String, dynamic> record) {
    final r = {...record, 'rev': ++_rev, 'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String(), 'device_id': 'seed', 'deleted_at': record['deleted_at']};
    tables.putIfAbsent(entity, () => {})[r['id'] as String] = r;
  }

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
        final merged = {...?defaults[op.entity], ...op.payload, 'id': id};
        for (final field in requiredFields[op.entity] ?? const <String>[]) {
          if (merged[field] == null) throw BackendError('validation_failed', 'null value in column $field');
        }
        _validate(op.entity, merged, table);
        if (op.entity == 'session_exercises') _copyPrescription(merged);
        table[id] = _stamp(merged, device, created: true);
        return ('applied', table[id]!['rev'] as int);
      }
      final base = op.baseRev;
      final current = existing['rev'] as int;
      if (base == null || (info.recordClass == RecordClass.appendOnly && base != current)) return ('duplicate', current);
      if (_conflicts(info, existing, base, device, clientTime)) return ('conflict', current);
      final merged = {...existing, ...op.payload, 'id': id};
      _validate(op.entity, merged, table);
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

  /// The trigger `pfs_session_exercise_snapshot`: an exercise created from a template row keeps a copy of its prescription.
  void _copyPrescription(Map<String, dynamic> row) {
    final teId = row['template_exercise_id'];
    final te = teId == null ? null : tables['template_exercises']?[teId];
    if (te == null || row['prescription_snapshot'] != null) return;
    final exercise = tables['exercises']?[te['exercise_id']];
    row['prescription_snapshot'] = {
      'template_version_id': te['template_version_id'],
      'template_exercise_id': te['id'],
      'exercise_id': te['exercise_id'],
      'exercise_name': exercise?['name'],
      'target_sets': te['target_sets'],
      'rep_min': te['rep_min'],
      'rep_max': te['rep_max'],
      'start_weight_kg': te['start_weight_kg'],
      'rest_s': te['rest_s'],
    };
  }

  /// The database rules that matter to the workout screens: references, uniqueness, value ranges, vocabularies,
  /// and `local_date` agreeing with `occurred_at` and `tz_offset_minutes`.
  void _validate(String entity, Map<String, dynamic> row, Map<String, Map<String, dynamic>> table) {
    for (final fk in (foreignKeys[entity] ?? const <String, String>{}).entries) {
      final ref = row[fk.key];
      if (ref != null && tables[fk.value]?[ref] == null) {
        throw BackendError('reference_missing', 'insert or update on $entity violates foreign key ${fk.key}');
      }
    }
    bool alive(Map<String, dynamic> r) => r['deleted_at'] == null && r['id'] != row['id'];
    if (entity == 'sets' && row['deleted_at'] == null) {
      if (table.values.any((r) =>
          alive(r) &&
          r['session_exercise_id'] == row['session_exercise_id'] &&
          r['set_type'] == row['set_type'] &&
          r['set_number'] == row['set_number'])) {
        throw const BackendError('validation_failed', 'duplicate key value violates unique constraint uq_sets_number');
      }
      final rpe = row['rpe'];
      if (rpe != null && ((rpe as num) < 1 || rpe > 10 || rpe * 2 != (rpe * 2).round())) throw const BackendError('validation_failed', 'ck_sets_rpe');
      final rir = row['rir'];
      if (rir != null && ((rir as num) < 0 || rir > 10)) throw const BackendError('validation_failed', 'ck_sets_rir');
      final weight = row['weight_kg'];
      if (weight != null && (weight as num) < 0) throw const BackendError('validation_failed', 'ck_sets_weight_nonnegative');
      if (!['warmup', 'working'].contains(row['set_type'])) throw const BackendError('validation_failed', 'ck_sets_set_type_values');
    }
    if (entity == 'session_exercises' && row['deleted_at'] == null) {
      if (table.values.any((r) => alive(r) && r['session_id'] == row['session_id'] && r['position'] == row['position'])) {
        throw const BackendError('validation_failed', 'duplicate key value violates unique constraint uq_session_exercises_position');
      }
      if (!['done', 'skipped', 'added'].contains(row['status'])) throw const BackendError('validation_failed', 'ck_session_exercises_status_values');
    }
    if (entity == 'workout_sessions') {
      if (!['in_progress', 'paused', 'completed', 'abandoned'].contains(row['status'])) {
        throw const BackendError('validation_failed', 'ck_workout_sessions_status_values');
      }
      if (row['status'] == 'completed' && row['ended_at'] == null) throw const BackendError('validation_failed', 'ck_workout_sessions_completed_has_end');
      final ended = row['ended_at'];
      if (ended != null && DateTime.parse(ended as String).isBefore(DateTime.parse(row['occurred_at'] as String))) {
        throw const BackendError('validation_failed', 'ck_workout_sessions_end_after_start');
      }
    }
    _validateLifestyle(entity, row, table, alive);
    if (row['occurred_at'] != null && row['tz_offset_minutes'] != null && row['local_date'] != null) {
      final at = DateTime.parse(row['occurred_at'] as String).toUtc();
      final local = at.add(Duration(minutes: (row['tz_offset_minutes'] as num).toInt()));
      String two(int n) => n.toString().padLeft(2, '0');
      final expected = '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}';
      if (row['local_date'] != expected) {
        throw BackendError('validation_failed', 'local_date ${row['local_date']} does not match occurred_at and tz_offset_minutes ($expected)');
      }
    }
  }

  /// The Stage 3 rules the Lifestyle screens depend on: one check-in and one step count per day, unique supplement
  /// names, value ranges and the check constraints that tie fields together.
  void _validateLifestyle(String entity, Map<String, dynamic> row, Map<String, Map<String, dynamic>> table, bool Function(Map<String, dynamic>) alive) {
    Never fail(String name) => throw BackendError('validation_failed', name);
    final live = row['deleted_at'] == null;
    switch (entity) {
      case 'daily_checkins':
        if (live && table.values.any((r) => alive(r) && r['local_date'] == row['local_date'])) fail('uq_daily_checkins_local_date');
        for (final k in ['energy', 'sleep_quality', 'soreness', 'fatigue', 'motivation', 'stress']) {
          final v = row[k];
          if (v != null && ((v as num) < 1 || v > 5)) fail('ck_daily_checkins_$k');
        }
      case 'daily_steps':
        if (live && table.values.any((r) => alive(r) && r['local_date'] == row['local_date'])) fail('uq_daily_steps_local_date');
        if ((row['steps'] as num) < 0) fail('ck_daily_steps_steps_nonnegative');
      case 'sleep_logs':
        final d = row['duration_s'] as num;
        if (d <= 0 || d > 86400) fail('ck_sleep_logs_duration');
        if (row['sleep_at'] != null && row['wake_at'] != null && !DateTime.parse(row['wake_at'] as String).isAfter(DateTime.parse(row['sleep_at'] as String))) {
          fail('ck_sleep_logs_wake_after_sleep');
        }
      case 'water_logs':
        if ((row['amount_ml'] as num) <= 0) fail('ck_water_logs_amount_positive');
      case 'cardio_sessions':
        if ((row['duration_s'] as num) <= 0) fail('ck_cardio_sessions_duration_positive');
        if (!['walking', 'running', 'cycling', 'treadmill', 'stairmaster', 'elliptical', 'custom'].contains(row['activity'])) fail('ck_cardio_sessions_activity_values');
        if (row['activity'] == 'custom' && row['custom_activity'] == null) fail('ck_cardio_sessions_custom_has_name');
      case 'body_measurements':
        if ((row['value'] as num) <= 0) fail('ck_body_measurements_value_positive');
        if (row['measurement_type'] == 'body_fat' && (row['method'] == null || (row['value'] as num) >= 100)) fail('ck_body_measurements_body_fat');
      case 'injuries':
        if (row['status'] == 'resolved' && row['resolved_on'] == null) fail('ck_injuries_resolved_has_date');
        final resolved = row['resolved_on'] as String?;
        if (resolved != null && resolved.compareTo(row['start_date'] as String) < 0) fail('ck_injuries_resolved_after_start');
      case 'pain_entries':
        final l = row['level'] as num;
        if (l < 0 || l > 10) fail('ck_pain_entries_level');
      case 'exercise_restrictions':
        if (row['exercise_id'] == null && row['movement'] == null) fail('ck_exercise_restrictions_target');
      case 'supplements':
        final name = (row['name'] as String).trim().toLowerCase();
        if (live && table.values.any((r) => alive(r) && (r['name'] as String).trim().toLowerCase() == name)) fail('uq_supplements_name_alive');
      case 'supplement_logs':
        if (!['taken', 'missed', 'skipped'].contains(row['outcome'])) fail('ck_supplement_logs_outcome_values');
      case 'meal_plan_entries':
        if (row['status'] == 'replaced' && row['replaced_by_meal_id'] == null) fail('ck_meal_plan_entries_replaced_has_meal');
        if ((row['servings'] as num) <= 0) fail('ck_meal_plan_entries_servings_positive');
    }
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
