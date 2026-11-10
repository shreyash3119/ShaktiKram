import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/db/store_logic.dart';

import 'support/memory_local_store.dart';
import 'support/store_contract.dart';

void main() {
  runStoreContract('in memory', () async => MemoryLocalStore());

  group('extractRefs', () {
    test('picks up uuid links and skips ids that are not links', () {
      final refs = extractRefs({
        'id': uid(1),
        'session_id': uid(2),
        'exercise_id': uid(3),
        'device_id': uid(4),
        'previous_version_id': null,
        'template_id': 'not-a-uuid',
        'name': uid(5),
      });
      expect(refs, {'session_id': uid(2), 'exercise_id': uid(3)});
    });
  });
}
