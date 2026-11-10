// Runs the real SQLite store on a phone or emulator:
//   flutter test integration_test/sqlite_store_test.dart -d <device id>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:shaktikram/core/db/schema.dart';
import 'package:shaktikram/core/db/sqflite_local_store.dart';
import 'package:sqflite/sqflite.dart';

import '../test/support/store_contract.dart';

var _n = 0;

Future<String> _freshPath() async {
  final path = p.join(await getDatabasesPath(), 'test_${DateTime.now().microsecondsSinceEpoch}_${_n++}.db');
  await deleteDatabase(path);
  return path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  runStoreContract('SQLite', () async => SqfliteLocalStore.open(path: await _freshPath()));

  test('data and the pull cursor survive closing and reopening the database', () async {
    final path = await _freshPath();
    final first = await SqfliteLocalStore.open(path: path);
    await first.applyPulled([pulled('exercises', 3, {'id': uid(1), 'name': 'Squat'})], 3);
    await first.saveLocal(op('op-1', 'goals', uid(2), {'id': uid(2), 'title': 'Cut'}));
    await first.setLastSyncAt(DateTime.utc(2026, 11, 10, 9));
    await first.close();

    final second = await SqfliteLocalStore.open(path: path);
    expect((await second.get('exercises', uid(1)))!['name'], 'Squat');
    expect((await second.get('goals', uid(2)))!['title'], 'Cut');
    expect(await second.lastRev(), 3);
    expect(await second.pendingCount(), 1);
    expect(await second.lastSyncAt(), isNotNull);
    await second.close();
  });

  test('a version 1 database is upgraded without losing records or queued changes', () async {
    final path = await _freshPath();
    final old = await openDatabase(path, version: 1, onCreate: (db, v) async {
      for (final statement in schemaV1) {
        await db.execute(statement);
      }
    });
    await old.insert('records', {
      'entity': 'sets',
      'id': uid(1),
      'server_rev': 4,
      'server_data': '{"id":"${uid(1)}"}',
      'data': '{"id":"${uid(1)}","session_exercise_id":"${uid(100)}","occurred_at":"2026-11-10T07:00:00Z"}',
      'dirty': 0,
      'deleted': 0,
    });
    await old.insert('outbox', {
      'op_id': 'op-old',
      'entity': 'goals',
      'action': 'upsert',
      'record_id': uid(2),
      'client_updated_at': '2026-11-10T07:00:00Z',
      'payload': '{"id":"${uid(2)}"}',
    });
    await old.insert('sync_state', {'key': 'last_rev', 'value': '4'});
    await old.close();

    final store = await SqfliteLocalStore.open(path: path);
    expect(await store.listByRef('sets', 'session_exercise_id', uid(100)), hasLength(1));
    expect((await store.list('sets')).single['id'], uid(1));
    expect(await store.pendingCount(), 1);
    expect(await store.lastRev(), 4);
    await store.close();
  });
}
