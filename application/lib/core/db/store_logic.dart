/// Rules for how a queued change shows up in the local copy. Shared by every [LocalStore] implementation.
library;

/// The record as it should look right after the user's change, before the server confirms it.
Map<String, dynamic> overlayUpsert(Map<String, dynamic>? current, String id, Map<String, dynamic> payload) {
  return {...?current, ...payload, 'id': id};
}

Map<String, dynamic> overlayDelete(Map<String, dynamic> current, DateTime now) {
  return {...current, 'deleted_at': now.toUtc().toIso8601String()};
}

bool isDeleted(Map<String, dynamic> record) => record['deleted_at'] != null;

String? localDateOf(Map<String, dynamic> record) {
  final value = record['local_date'];
  return value is String ? value : null;
}

/// How many times a `reference_missing` answer is retried before the operation is shown as refused.
const maxReferenceRetries = 5;

/// What to do with a refused operation: retry later or give up.
bool shouldRetry(String? errorCode, int attemptsSoFar) => errorCode == 'reference_missing' && attemptsSoFar + 1 < maxReferenceRetries;

/// Newest first by `occurred_at`, then by id (UUIDv7 ids are time ordered).
int compareNewestFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
  final ao = (a['occurred_at'] as String?) ?? '';
  final bo = (b['occurred_at'] as String?) ?? '';
  final byTime = bo.compareTo(ao);
  if (byTime != 0) return byTime;
  return ((b['id'] as String?) ?? '').compareTo((a['id'] as String?) ?? '');
}

/// When an event record happened (UTC text), used to order and index event tables.
String? occurredAtOf(Map<String, dynamic> record) {
  final value = record['occurred_at'];
  return value is String ? value : null;
}

final _uuidPattern = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Fields that hold ids which are not links to another record.
const _notRecordLinks = {'id', 'device_id', 'op_id', 'request_id', 'auth_user_id'};

/// The links from a record to other records: every `*_id` field holding a uuid (`session_id`, `exercise_id`,
/// `entity_id`, `previous_version_id`, ...). Indexed so child records can be found quickly.
Map<String, String> extractRefs(Map<String, dynamic> record) {
  return {
    for (final e in record.entries)
      if (e.key.endsWith('_id') && !_notRecordLinks.contains(e.key) && e.value is String && _uuidPattern.hasMatch(e.value as String))
        e.key: e.value as String,
  };
}
