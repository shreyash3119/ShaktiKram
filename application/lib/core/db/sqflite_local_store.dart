import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'local_store.dart';
import 'schema.dart';
import 'store_logic.dart';
import 'sync_models.dart';

/// [LocalStore] on SQLite (sqflite). One generic table holds every synced record as JSON.
class SqfliteLocalStore implements LocalStore {
  SqfliteLocalStore._(this._db);

  final Database _db;

  static Future<SqfliteLocalStore> open({String? path}) async {
    final target = path ?? p.join(await getDatabasesPath(), 'shaktikram.db');
    final db = await openDatabase(
      target,
      version: databaseVersion,
      onCreate: (db, version) async {
        for (final statement in [...schemaV1, ...migrationV2]) {
          await db.execute(statement);
        }
      },
      onUpgrade: _upgrade,
    );
    return SqfliteLocalStore._(db);
  }

  /// Moves an existing database to [databaseVersion] one step at a time. Never deletes records.
  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      for (final statement in migrationV2) {
        await db.execute(statement);
      }
      // Fill the new columns for the records already on the phone.
      final rows = await db.query('records', columns: ['entity', 'id', 'data']);
      final batch = db.batch();
      for (final row in rows) {
        final data = Map<String, dynamic>.from(jsonDecode(row['data'] as String) as Map);
        batch.update('records', {'occurred_at': occurredAtOf(data)}, where: 'entity = ? AND id = ?', whereArgs: [row['entity'], row['id']]);
        for (final ref in extractRefs(data).entries) {
          batch.insert('record_refs', {'entity': row['entity'], 'id': row['id'], 'field': ref.key, 'ref': ref.value},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> close() => _db.close();

  // ---- helpers ----

  Map<String, dynamic> _decode(Object? json) => Map<String, dynamic>.from(jsonDecode(json as String) as Map);

  OutboxOp _op(Map<String, Object?> r) => OutboxOp(
        seq: r['seq'] as int,
        opId: r['op_id'] as String,
        entity: r['entity'] as String,
        action: r['action'] as String,
        recordId: r['record_id'] as String?,
        baseRev: r['base_rev'] as int?,
        clientUpdatedAt: DateTime.parse(r['client_updated_at'] as String),
        reason: r['reason'] as String?,
        payload: _decode(r['payload']),
        state: OpState.values.firstWhere((s) => s.name == r['state']),
        attempts: r['attempts'] as int,
        errorCode: r['error_code'] as String?,
        message: r['message'] as String?,
      );

  Future<Map<String, Object?>?> _row(DatabaseExecutor db, String entity, String id) async {
    final rows = await db.query('records', where: 'entity = ? AND id = ?', whereArgs: [entity, id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _putRecord(
    DatabaseExecutor db,
    String entity,
    String id, {
    required int? serverRev,
    required String? serverData,
    required Map<String, dynamic> data,
    required bool dirty,
  }) async {
    await db.insert(
      'records',
      {
        'entity': entity,
        'id': id,
        'server_rev': serverRev,
        'server_data': serverData,
        'data': jsonEncode(data),
        'dirty': dirty ? 1 : 0,
        'deleted': isDeleted(data) ? 1 : 0,
        'local_date': localDateOf(data),
        'occurred_at': occurredAtOf(data),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.delete('record_refs', where: 'entity = ? AND id = ?', whereArgs: [entity, id]);
    for (final ref in extractRefs(data).entries) {
      await db.insert('record_refs', {'entity': entity, 'id': id, 'field': ref.key, 'ref': ref.value});
    }
  }

  // ---- reading ----

  @override
  Future<Map<String, dynamic>?> get(String entity, String id) async {
    final row = await _row(_db, entity, id);
    return row == null ? null : _decode(row['data']);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String entity, {String? localDate, bool includeDeleted = false, int? limit}) async {
    final where = StringBuffer('entity = ?');
    final args = <Object?>[entity];
    if (!includeDeleted) where.write(' AND deleted = 0');
    if (localDate != null) {
      where.write(' AND local_date = ?');
      args.add(localDate);
    }
    final rows = await _db.query(
      'records',
      columns: ['data'],
      where: where.toString(),
      whereArgs: args,
      orderBy: "COALESCE(occurred_at, '') DESC, id DESC",
      limit: limit,
    );
    return [for (final r in rows) _decode(r['data'])];
  }

  @override
  Future<List<Map<String, dynamic>>> listByRef(String entity, String field, String refId, {bool includeDeleted = false}) async {
    final rows = await _db.rawQuery(
      'SELECT r.data AS data FROM record_refs f '
      'JOIN records r ON r.entity = f.entity AND r.id = f.id '
      'WHERE f.entity = ? AND f.field = ? AND f.ref = ?${includeDeleted ? '' : ' AND r.deleted = 0'} '
      "ORDER BY COALESCE(r.occurred_at, '') DESC, r.id DESC",
      [entity, field, refId],
    );
    return [for (final r in rows) _decode(r['data'])];
  }

  @override
  Future<int> recordCount() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM records WHERE deleted = 0');
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  // ---- writing from the app ----

  @override
  Future<OutboxOp> saveLocal(OutboxOp op) async => (await saveLocalAll([op])).single;

  @override
  Future<List<OutboxOp>> saveLocalAll(List<OutboxOp> ops) {
    return _db.transaction((txn) async => [for (final op in ops) await _saveIn(txn, op)]);
  }

  Future<OutboxOp> _saveIn(DatabaseExecutor txn, OutboxOp op) async {
    {
      final id = op.recordId;
      final existing = id == null ? null : await _row(txn, op.entity, id);
      final baseRev = op.baseRev ?? (existing?['server_rev'] as int?);
      final seq = await txn.insert('outbox', {
        'op_id': op.opId,
        'entity': op.entity,
        'action': op.action,
        'record_id': id,
        'base_rev': baseRev,
        'client_updated_at': op.clientUpdatedAt.toUtc().toIso8601String(),
        'reason': op.reason,
        'payload': jsonEncode(op.payload),
        'state': OpState.pending.name,
      });

      if (id != null && op.action != 'new_version') {
        final current = existing == null ? null : _decode(existing['data']);
        final next = op.action == 'delete'
            ? (current == null ? null : overlayDelete(current, op.clientUpdatedAt))
            : overlayUpsert(current, id, op.payload);
        if (next != null) {
          await _putRecord(
            txn,
            op.entity,
            id,
            serverRev: existing?['server_rev'] as int?,
            serverData: existing?['server_data'] as String?,
            data: next,
            dirty: true,
          );
        }
      }
      return op.copyWith(seq: seq, baseRev: baseRev);
    }
  }

  // ---- sync engine ----

  @override
  Future<List<OutboxOp>> pendingOps({int afterSeq = 0, int limit = 100}) async {
    final rows = await _db.query(
      'outbox',
      where: "state = 'pending' AND seq > ?",
      whereArgs: [afterSeq],
      orderBy: 'seq ASC',
      limit: limit,
    );
    return rows.map(_op).toList();
  }

  @override
  Future<void> recordResult(OutboxOp op, OpResult result) {
    return _db.transaction((txn) async {
      final outcome = result.outcome;
      final id = op.recordId;

      Future<void> revertToServer() async {
        if (id == null) return;
        final row = await _row(txn, op.entity, id);
        if (row == null) return;
        final serverData = row['server_data'] as String?;
        if (serverData == null) {
          await txn.delete('records', where: 'entity = ? AND id = ?', whereArgs: [op.entity, id]);
          await txn.delete('record_refs', where: 'entity = ? AND id = ?', whereArgs: [op.entity, id]);
        } else {
          await _putRecord(txn, op.entity, id,
              serverRev: row['server_rev'] as int?, serverData: serverData, data: _decode(serverData), dirty: false);
        }
      }

      Future<void> clearDirtyIfDone() async {
        if (id == null) return;
        final left = await txn.rawQuery(
          "SELECT COUNT(*) AS c FROM outbox WHERE entity = ? AND record_id = ? AND state = 'pending'",
          [op.entity, id],
        );
        if ((Sqflite.firstIntValue(left) ?? 0) == 0) {
          await txn.update('records', {'dirty': 0}, where: 'entity = ? AND id = ?', whereArgs: [op.entity, id]);
        }
      }

      if (outcome == 'applied') {
        await txn.delete('outbox', where: 'op_id = ?', whereArgs: [op.opId]);
        final rev = result.rev;
        if (id != null && rev != null) {
          await txn.update(
            'outbox',
            {'base_rev': rev},
            where: "entity = ? AND record_id = ? AND state = 'pending' AND (base_rev IS NULL OR base_rev < ?)",
            whereArgs: [op.entity, id, rev],
          );
          final row = await _row(txn, op.entity, id);
          if (row != null && ((row['server_rev'] as int?) ?? 0) < rev) {
            await txn.update('records', {'server_rev': rev}, where: 'entity = ? AND id = ?', whereArgs: [op.entity, id]);
          }
        }
        await clearDirtyIfDone();
      } else if (outcome == 'conflict') {
        await txn.update('outbox', {'state': OpState.conflict.name, 'error_code': result.issueCode ?? 'conflict_stale_rev', 'message': result.issueMessage},
            where: 'op_id = ?', whereArgs: [op.opId]);
        await revertToServer();
      } else {
        final code = result.issueCode;
        if (shouldRetry(code, op.attempts)) {
          await txn.update('outbox', {'attempts': op.attempts + 1, 'error_code': code, 'message': result.issueMessage},
              where: 'op_id = ?', whereArgs: [op.opId]);
        } else {
          await txn.update(
              'outbox',
              {'state': OpState.rejected.name, 'attempts': op.attempts + 1, 'error_code': code, 'message': result.issueMessage},
              where: 'op_id = ?', whereArgs: [op.opId]);
          await revertToServer();
        }
      }
    });
  }

  @override
  Future<void> applyPulled(List<PulledRow> rows, int nextRev) {
    return _db.transaction((txn) async {
      for (final row in rows) {
        final id = row.record['id'] as String?;
        if (id == null) continue;
        final existing = await _row(txn, row.entity, id);
        final storedRev = existing?['server_rev'] as int?;
        if (storedRev != null && row.rev < storedRev) continue;
        final dirty = (existing?['dirty'] as int? ?? 0) == 1;
        await _putRecord(
          txn,
          row.entity,
          id,
          serverRev: row.rev,
          serverData: jsonEncode(row.record),
          data: dirty && existing != null ? _decode(existing['data']) : row.record,
          dirty: dirty,
        );
      }
      await txn.insert('sync_state', {'key': 'last_rev', 'value': '$nextRev'}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<String?> _state(String key) async {
    final rows = await _db.query('sync_state', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<int> lastRev() async => int.tryParse(await _state('last_rev') ?? '') ?? 0;

  @override
  Future<DateTime?> lastSyncAt() async {
    final v = await _state('last_sync_at');
    return v == null ? null : DateTime.tryParse(v);
  }

  @override
  Future<void> setLastSyncAt(DateTime time) async {
    await _db.insert('sync_state', {'key': 'last_sync_at', 'value': time.toUtc().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- status ----

  @override
  Future<int> pendingCount() async {
    final rows = await _db.rawQuery("SELECT COUNT(*) AS c FROM outbox WHERE state = 'pending'");
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  @override
  Future<List<OutboxOp>> issues() async {
    final rows = await _db.query('outbox', where: "state != 'pending'", orderBy: 'seq ASC');
    return rows.map(_op).toList();
  }

  @override
  Future<int> issueCount() async {
    final rows = await _db.rawQuery("SELECT COUNT(*) AS c FROM outbox WHERE state != 'pending'");
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  @override
  Future<void> dismissIssue(String opId) async {
    await _db.delete('outbox', where: "op_id = ? AND state != 'pending'", whereArgs: [opId]);
  }
}
