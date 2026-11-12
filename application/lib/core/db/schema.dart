/// SQLite schema of the phone database, with one list of statements per version.
///
/// Rules: a new version only ever adds a new list here and a step in `SqfliteLocalStore._upgrade`.
/// Existing statements are never edited, and no migration deletes user data.
const databaseVersion = 3;

/// Version 1 (step 4): records, the outbox and the sync cursor.
const schemaV1 = <String>[
  '''
CREATE TABLE records (
  entity TEXT NOT NULL,
  id TEXT NOT NULL,
  server_rev INTEGER,
  server_data TEXT,
  data TEXT NOT NULL,
  dirty INTEGER NOT NULL DEFAULT 0,
  deleted INTEGER NOT NULL DEFAULT 0,
  local_date TEXT,
  PRIMARY KEY (entity, id)
)''',
  'CREATE INDEX records_by_date ON records (entity, deleted, local_date)',
  '''
CREATE TABLE outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  op_id TEXT NOT NULL UNIQUE,
  entity TEXT NOT NULL,
  action TEXT NOT NULL,
  record_id TEXT,
  base_rev INTEGER,
  client_updated_at TEXT NOT NULL,
  reason TEXT,
  payload TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  error_code TEXT,
  message TEXT
)''',
  'CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT)',
];

/// Version 2 (phase 3): indexed columns for the queries the feature screens need.
/// - `occurred_at` orders event records (sets, check-ins, measurements) newest first without reading every row.
/// - `record_refs` lists the links from a record to other records (`session_id`, `exercise_id`, ...), so "all sets
///   of this session" or "all versions of this plan" is an index lookup.
const migrationV2 = <String>[
  'ALTER TABLE records ADD COLUMN occurred_at TEXT',
  'CREATE INDEX records_by_time ON records (entity, deleted, occurred_at)',
  '''
CREATE TABLE record_refs (
  entity TEXT NOT NULL,
  id TEXT NOT NULL,
  field TEXT NOT NULL,
  ref TEXT NOT NULL,
  PRIMARY KEY (entity, id, field)
)''',
  'CREATE INDEX record_refs_by_ref ON record_refs (entity, field, ref)',
];

/// Version 3 (phase 7): the cache for insights the server calculates (daily briefing, trends, goal progress, ...).
/// One row per cached answer. It holds copies only: dropping a row loses nothing that is not on the server, and it is
/// never part of sync. `payload` is the server's JSON; `fetched_at` is when this phone received it.
const migrationV3 = <String>[
  '''
CREATE TABLE insight_cache (
  key TEXT PRIMARY KEY,
  payload TEXT NOT NULL,
  fetched_at TEXT NOT NULL
)''',
];
