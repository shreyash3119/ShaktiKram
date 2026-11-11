import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/uuid.dart';
import '../db/entities.dart';
import '../db/local_store.dart';
import '../db/sync_models.dart';
import 'sync_status.dart';

/// Keys the server does not accept in a payload (contract section 10).
const forbiddenPayloadKeys = {'rev', 'created_at', 'updated_at', 'device_id', 'deleted_at'};

/// One change to make. Build it, then hand one or several to [ChangeWriter.apply].
class PendingChange {
  /// Creates a record (no [id]) or changes one. The id is made here so other changes in the same step can refer to it.
  PendingChange.upsert(this.entity, Map<String, dynamic> payload, {String? id, this.reason})
      : action = 'upsert',
        id = id ?? (payload['id'] as String?) ?? newUuidV7(),
        payload = _clean(payload);

  /// Soft-deletes a record.
  PendingChange.delete(this.entity, this.id, {this.reason})
      : action = 'delete',
        payload = const {};

  /// Adds a new version of a versioned record. [payload] needs `entity_id`; it may set `effective_from`.
  PendingChange.newVersion(this.entity, Map<String, dynamic> payload, {this.reason})
      : action = 'new_version',
        id = (payload['id'] as String?) ?? newUuidV7(),
        payload = _clean(payload);

  final String entity;
  final String action;
  final String id;
  final Map<String, dynamic> payload;
  final String? reason;

  static Map<String, dynamic> _clean(Map<String, dynamic> payload) => {
        for (final e in payload.entries)
          if (!forbiddenPayloadKeys.contains(e.key)) e.key: e.value,
      };
}

/// The one way features change data (architecture rule 2): store locally, queue, then try to sync.
class ChangeWriter {
  ChangeWriter(this._ref, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Ref _ref;
  final DateTime Function() _clock;

  LocalStore get _store => _ref.read(localStoreProvider);

  /// Stores and queues all [changes] as one step: all of them are saved, or none. Returns the record ids in order.
  /// Changes later in the list see the earlier ones, so a record and the records that point at it can go together.
  Future<List<String>> apply(List<PendingChange> changes) async {
    for (final c in changes) {
      if (!isWritableEntity(c.entity)) throw ArgumentError('${c.entity} cannot be changed from the app.');
    }
    final now = _clock().toUtc();
    await _store.saveLocalAll([
      for (final c in changes)
        OutboxOp(
          opId: newUuidV7(),
          entity: c.entity,
          action: c.action,
          recordId: c.id,
          clientUpdatedAt: now,
          reason: c.reason,
          payload: c.action == 'delete' ? const {} : {...c.payload, 'id': c.id},
        ),
    ]);
    await _after();
    return [for (final c in changes) c.id];
  }

  Future<void> _after() async {
    final status = _ref.read(syncStatusProvider.notifier);
    await status.refresh();
    // Not awaited: the change is already safe on the phone.
    unawaited(status.syncNow());
  }

  /// Creates a record (no [id]) or changes one. Returns the record id.
  Future<String> upsert(String entity, Map<String, dynamic> payload, {String? id, String? reason}) async =>
      (await apply([PendingChange.upsert(entity, payload, id: id, reason: reason)])).single;

  /// Soft-deletes a record.
  Future<void> delete(String entity, String id, {String? reason}) => apply([PendingChange.delete(entity, id, reason: reason)]);

  /// Adds a new version of a versioned record. [payload] needs `entity_id`; it may set `effective_from`.
  Future<String> newVersion(String entity, Map<String, dynamic> payload, {String? reason}) async =>
      (await apply([PendingChange.newVersion(entity, payload, reason: reason)])).single;
}

final changeWriterProvider = Provider<ChangeWriter>((ref) => ChangeWriter(ref));
