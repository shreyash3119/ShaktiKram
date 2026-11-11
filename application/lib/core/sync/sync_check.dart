import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/local_store.dart';
import 'change_writer.dart';
import 'sync_status.dart';

class CheckStep {
  const CheckStep(this.name, this.passed, this.detail);

  final String name;
  final bool passed;
  final String detail;
}

/// A live end-to-end test of the write path for development: creates a meal named "SYNC CHECK ...", changes it, then
/// deletes it (soft delete), syncing and reading back after each step. Uses whatever Supabase project the app is
/// configured for, so it must only be run against a development project. It stops at the first failed step.
class SyncCheck {
  SyncCheck({required this.store, required this.writer, required this.sync, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final LocalStore store;
  final ChangeWriter writer;

  /// Runs a full sync round and returns a problem in plain words, or null when it went fine.
  final Future<String?> Function() sync;
  final DateTime Function() _clock;

  static const entity = 'meals';

  Future<List<CheckStep>> run() async {
    final steps = <CheckStep>[];
    bool fail(String name, String detail) {
      steps.add(CheckStep(name, false, detail));
      return false;
    }

    final issuesBefore = await store.issueCount();
    final title = 'SYNC CHECK ${_clock().toUtc().toIso8601String()}';

    // 1. Create on the phone.
    final id = await writer.upsert(entity, {'title': title, 'category': 'snack', 'notes': 'Created by the sync check. Safe to delete.'});
    final local = await store.get(entity, id);
    if (local == null || local['title'] != title) {
      fail('Save on the phone', 'The new record was not found in the local database.');
      return steps;
    }
    steps.add(const CheckStep('Save on the phone', true, 'Stored locally before anything was sent.'));

    // 2. Send it and read it back.
    var problem = await sync();
    if (problem != null) {
      fail('Create on the server', problem);
      return steps;
    }
    var back = await store.get(entity, id);
    final rev1 = back?['rev'];
    if (await store.pendingCount() != 0 || await store.issueCount() > issuesBefore) {
      final issue = (await store.issues()).isEmpty ? null : (await store.issues()).last;
      fail('Create on the server', 'Not accepted: ${issue?.errorCode ?? 'still waiting'} ${issue?.message ?? ''}'.trim());
      return steps;
    }
    if (rev1 is! int || back?['created_at'] == null) {
      fail('Create on the server', 'The server copy did not come back with a revision.');
      return steps;
    }
    steps.add(CheckStep('Create on the server', true, 'Accepted. Revision $rev1.'));

    // 3. Edit.
    await writer.upsert(entity, {'title': '$title (edited)'}, id: id);
    problem = await sync();
    back = await store.get(entity, id);
    final rev2 = back?['rev'];
    if (problem != null) {
      fail('Edit on the server', problem);
      return steps;
    }
    if (back?['title'] != '$title (edited)' || rev2 is! int || rev2 <= rev1 || await store.pendingCount() != 0) {
      fail('Edit on the server', 'The edit did not come back from the server (revision $rev1 to $rev2).');
      return steps;
    }
    steps.add(CheckStep('Edit on the server', true, 'Accepted. Revision $rev2.'));

    // 4. Delete.
    await writer.delete(entity, id);
    problem = await sync();
    back = await store.get(entity, id);
    final rev3 = back?['rev'];
    if (problem != null) {
      fail('Delete on the server', problem);
      return steps;
    }
    if (back?['deleted_at'] == null || rev3 is! int || rev3 <= rev2 || await store.pendingCount() != 0) {
      fail('Delete on the server', 'The delete did not come back from the server.');
      return steps;
    }
    if ((await store.list(entity)).any((r) => r['id'] == id)) {
      fail('Delete on the server', 'The record still shows in the list.');
      return steps;
    }
    steps.add(CheckStep('Delete on the server', true, 'Marked deleted. Revision $rev3.'));

    if (await store.issueCount() > issuesBefore) {
      fail('Final state', 'New problems were recorded in Settings.');
    } else {
      steps.add(const CheckStep('Final state', true, 'Nothing waiting, no new problems.'));
    }
    return steps;
  }
}

final syncCheckProvider = Provider<SyncCheck>((ref) {
  return SyncCheck(
    store: ref.read(localStoreProvider),
    writer: ref.read(changeWriterProvider),
    sync: () async {
      await ref.read(syncStatusProvider.notifier).syncNow();
      final status = ref.read(syncStatusProvider);
      return switch (status.phase) {
        SyncPhase.offline => 'No connection to the server.',
        SyncPhase.error when status.message != null => status.message,
        _ => null,
      };
    },
  );
});
