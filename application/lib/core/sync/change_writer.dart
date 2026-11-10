import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/uuid.dart';
import '../db/entities.dart';
import '../db/local_store.dart';
import '../db/sync_models.dart';
import 'sync_status.dart';

/// Keys the server does not accept in a payload (contract section 10).
const forbiddenPayloadKeys = {'rev', 'created_at', 'updated_at', 'device_id', 'deleted_at'};

/// The one way features change data (architecture rule 2): store locally, queue, then try to sync.
class ChangeWriter {
  ChangeWriter(this._ref, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Ref _ref;
  final DateTime Function() _clock;

  LocalStore get _store => _ref.read(localStoreProvider);

  Map<String, dynamic> _clean(Map<String, dynamic> payload) => {
        for (final e in payload.entries)
          if (!forbiddenPayloadKeys.contains(e.key)) e.key: e.value,
      };

  void _checkWritable(String entity) {
    if (!isWritableEntity(entity)) {
      throw ArgumentError('$entity cannot be changed from the app.');
    }
  }

  Future<void> _after() async {
    final status = _ref.read(syncStatusProvider.notifier);
    await status.refresh();
    // Not awaited: the change is already safe on the phone.
    unawaited(status.syncNow());
  }

  /// Creates a record (no [id]) or changes one. Returns the record id.
  Future<String> upsert(String entity, Map<String, dynamic> payload, {String? id, String? reason}) async {
    _checkWritable(entity);
    final recordId = id ?? (payload['id'] as String?) ?? newUuidV7();
    await _store.saveLocal(OutboxOp(
      opId: newUuidV7(),
      entity: entity,
      action: 'upsert',
      recordId: recordId,
      clientUpdatedAt: _clock().toUtc(),
      reason: reason,
      payload: {..._clean(payload), 'id': recordId},
    ));
    await _after();
    return recordId;
  }

  /// Soft-deletes a record.
  Future<void> delete(String entity, String id, {String? reason}) async {
    _checkWritable(entity);
    await _store.saveLocal(OutboxOp(
      opId: newUuidV7(),
      entity: entity,
      action: 'delete',
      recordId: id,
      clientUpdatedAt: _clock().toUtc(),
      reason: reason,
    ));
    await _after();
  }

  /// Adds a new version of a versioned record. [payload] needs `entity_id`; it may set `effective_from`.
  Future<String> newVersion(String entity, Map<String, dynamic> payload, {String? reason}) async {
    _checkWritable(entity);
    final recordId = (payload['id'] as String?) ?? newUuidV7();
    await _store.saveLocal(OutboxOp(
      opId: newUuidV7(),
      entity: entity,
      action: 'new_version',
      recordId: recordId,
      clientUpdatedAt: _clock().toUtc(),
      reason: reason,
      payload: {..._clean(payload), 'id': recordId},
    ));
    await _after();
    return recordId;
  }
}

final changeWriterProvider = Provider<ChangeWriter>((ref) => ChangeWriter(ref));
