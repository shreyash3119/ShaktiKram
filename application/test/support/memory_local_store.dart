import 'package:shaktikram/core/db/local_store.dart';
import 'package:shaktikram/core/db/store_logic.dart';
import 'package:shaktikram/core/db/sync_models.dart';

class _Rec {
  _Rec({this.serverRev, this.serverData, required this.data, this.dirty = false});
  int? serverRev;
  Map<String, dynamic>? serverData;
  Map<String, dynamic> data;
  bool dirty;
}

/// Same rules as the SQLite store, in memory. For tests.
class MemoryLocalStore implements LocalStore {
  final Map<String, _Rec> _records = {};
  final List<OutboxOp> _outbox = [];
  int _seq = 0;
  int _lastRev = 0;
  DateTime? _lastSync;

  String _key(String entity, String id) => '$entity/$id';

  @override
  Future<Map<String, dynamic>?> get(String entity, String id) async => _records[_key(entity, id)]?.data;

  @override
  Future<List<Map<String, dynamic>>> list(String entity, {String? localDate, bool includeDeleted = false, int? limit}) async {
    final out = <Map<String, dynamic>>[];
    _records.forEach((key, rec) {
      if (!key.startsWith('$entity/')) return;
      if (!includeDeleted && isDeleted(rec.data)) return;
      if (localDate != null && localDateOf(rec.data) != localDate) return;
      out.add(rec.data);
    });
    out.sort(compareNewestFirst);
    return limit == null || out.length <= limit ? out : out.sublist(0, limit);
  }

  @override
  Future<int> recordCount() async => _records.values.where((r) => !isDeleted(r.data)).length;

  @override
  Future<OutboxOp> saveLocal(OutboxOp op) async {
    final id = op.recordId;
    final existing = id == null ? null : _records[_key(op.entity, id)];
    final baseRev = op.baseRev ?? existing?.serverRev;
    final stored = op.copyWith(seq: ++_seq, baseRev: baseRev);
    _outbox.add(stored);
    if (id != null && op.action != 'new_version') {
      final next = op.action == 'delete'
          ? (existing == null ? null : overlayDelete(existing.data, op.clientUpdatedAt))
          : overlayUpsert(existing?.data, id, op.payload);
      if (next != null) {
        _records[_key(op.entity, id)] =
            _Rec(serverRev: existing?.serverRev, serverData: existing?.serverData, data: next, dirty: true);
      }
    }
    return stored;
  }

  @override
  Future<List<OutboxOp>> pendingOps({int afterSeq = 0, int limit = 100}) async =>
      _outbox.where((o) => o.state == OpState.pending && o.seq! > afterSeq).take(limit).toList();

  void _revert(OutboxOp op) {
    final id = op.recordId;
    if (id == null) return;
    final rec = _records[_key(op.entity, id)];
    if (rec == null) return;
    if (rec.serverData == null) {
      _records.remove(_key(op.entity, id));
    } else {
      rec.data = Map<String, dynamic>.from(rec.serverData!);
      rec.dirty = false;
    }
  }

  @override
  Future<void> recordResult(OutboxOp op, OpResult result) async {
    final index = _outbox.indexWhere((o) => o.opId == op.opId);
    if (index < 0) return;
    final outcome = result.outcome;
    final id = op.recordId;
    if (outcome == 'applied') {
      _outbox.removeAt(index);
      final rev = result.rev;
      if (id != null && rev != null) {
        for (var i = 0; i < _outbox.length; i++) {
          final o = _outbox[i];
          if (o.entity == op.entity && o.recordId == id && o.state == OpState.pending && (o.baseRev == null || o.baseRev! < rev)) {
            _outbox[i] = o.copyWith(baseRev: rev);
          }
        }
        final rec = _records[_key(op.entity, id)];
        if (rec != null && (rec.serverRev ?? 0) < rev) rec.serverRev = rev;
      }
      if (id != null) {
        final left = _outbox.any((o) => o.entity == op.entity && o.recordId == id && o.state == OpState.pending);
        if (!left) _records[_key(op.entity, id)]?.dirty = false;
      }
    } else if (outcome == 'conflict') {
      _outbox[index] = _outbox[index].copyWith(state: OpState.conflict, errorCode: result.errorCode ?? 'conflict_stale_rev', message: result.message);
      _revert(op);
    } else if (shouldRetry(result.errorCode, op.attempts)) {
      _outbox[index] = _outbox[index].copyWith(attempts: op.attempts + 1, errorCode: result.errorCode, message: result.message);
    } else {
      _outbox[index] = _outbox[index]
          .copyWith(state: OpState.rejected, attempts: op.attempts + 1, errorCode: result.errorCode, message: result.message);
      _revert(op);
    }
  }

  @override
  Future<void> applyPulled(List<PulledRow> rows, int nextRev) async {
    for (final row in rows) {
      final id = row.record['id'] as String?;
      if (id == null) continue;
      final existing = _records[_key(row.entity, id)];
      if (existing?.serverRev != null && row.rev < existing!.serverRev!) continue;
      final dirty = existing?.dirty ?? false;
      _records[_key(row.entity, id)] = _Rec(
        serverRev: row.rev,
        serverData: Map<String, dynamic>.from(row.record),
        data: dirty && existing != null ? existing.data : Map<String, dynamic>.from(row.record),
        dirty: dirty,
      );
    }
    _lastRev = nextRev;
  }

  @override
  Future<int> lastRev() async => _lastRev;

  @override
  Future<DateTime?> lastSyncAt() async => _lastSync;

  @override
  Future<void> setLastSyncAt(DateTime time) async => _lastSync = time;

  @override
  Future<int> pendingCount() async => _outbox.where((o) => o.state == OpState.pending).length;

  @override
  Future<List<OutboxOp>> issues() async => _outbox.where((o) => o.state != OpState.pending).toList();

  @override
  Future<int> issueCount() async => _outbox.where((o) => o.state != OpState.pending).length;

  @override
  Future<void> dismissIssue(String opId) async => _outbox.removeWhere((o) => o.opId == opId && o.state != OpState.pending);
}
