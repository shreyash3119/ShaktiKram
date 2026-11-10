import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_models.dart';

/// The phone's copy of the data and the queue of changes waiting to be sent.
///
/// Screens read records from here (architecture rule 4) and write through [saveLocal], which stores the change
/// and queues it in one step (rule 2). Only the sync engine calls the other write methods.
abstract class LocalStore {
  // ---- Reading ----

  /// One record (the full server-shaped row, with local edits applied), or null.
  Future<Map<String, dynamic>?> get(String entity, String id);

  /// Records of one table, without soft-deleted rows unless asked. [localDate] is `YYYY-MM-DD`.
  /// Newest first by `occurred_at` when present, otherwise by id.
  Future<List<Map<String, dynamic>>> list(String entity, {String? localDate, bool includeDeleted = false, int? limit});

  Future<int> recordCount();

  // ---- Writing from the app ----

  /// Applies the change to the local copy and queues it for the server, together.
  /// Fills `baseRev` from the record's last known server revision. Returns the stored operation.
  Future<OutboxOp> saveLocal(OutboxOp op);

  // ---- Sync engine ----

  /// Pending operations with `seq` greater than [afterSeq], oldest first.
  Future<List<OutboxOp>> pendingOps({int afterSeq = 0, int limit = 100});

  /// Records the server's answer for [op].
  Future<void> recordResult(OutboxOp op, OpResult result);

  /// Stores pulled rows and moves the pull cursor to [nextRev], together.
  Future<void> applyPulled(List<PulledRow> rows, int nextRev);

  Future<int> lastRev();
  Future<DateTime?> lastSyncAt();
  Future<void> setLastSyncAt(DateTime time);

  // ---- Status ----

  Future<int> pendingCount();

  /// Operations the server refused or that lost a conflict.
  Future<List<OutboxOp>> issues();
  Future<int> issueCount();

  /// Removes a refused or conflicting operation from the list once the owner has seen it.
  Future<void> dismissIssue(String opId);
}

/// Replaced in `main.dart` (and in tests).
final localStoreProvider = Provider<LocalStore>((ref) {
  throw UnimplementedError('localStoreProvider must be overridden');
});
