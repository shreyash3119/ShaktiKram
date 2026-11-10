/// How the server treats changes to a table (docs/TECHNICAL_CONTRACT.md section 10, rule 4).
enum RecordClass {
  /// Ordinary records. An edit names `base_rev`; another device's newer write wins.
  editable,

  /// Facts such as sets and check-ins. A re-sent create is ignored; a correction needs the current rev.
  appendOnly,

  /// Plan versions. Changed only with `new_version`.
  versioned,
}

class EntityInfo {
  const EntityInfo(this.recordClass, {this.clientWritable = true});

  final RecordClass recordClass;

  /// False for tables the database fills itself (records, achievements, status events).
  final bool clientWritable;
}

/// Every table the server returns from `api_pull_changes` (56 tables, from `pfs_attach` in the Stage 1 to 4 migrations).
/// Keep in step with `shared/api_contracts/`. A table missing here is still stored locally when pulled,
/// but cannot be written from the app until it is added.
const syncedEntities = <String, EntityInfo>{
  'achievements': EntityInfo(RecordClass.appendOnly, clientWritable: false),
  'body_measurements': EntityInfo(RecordClass.appendOnly),
  'body_regions': EntityInfo(RecordClass.editable),
  'break_events': EntityInfo(RecordClass.appendOnly),
  'cardio_sessions': EntityInfo(RecordClass.appendOnly),
  'daily_checkins': EntityInfo(RecordClass.editable),
  'daily_steps': EntityInfo(RecordClass.editable),
  'deload_periods': EntityInfo(RecordClass.editable),
  'equipment': EntityInfo(RecordClass.editable),
  'equipment_status_events': EntityInfo(RecordClass.appendOnly),
  'exercise_alternatives': EntityInfo(RecordClass.editable),
  'exercise_muscles': EntityInfo(RecordClass.editable),
  'exercise_reference': EntityInfo(RecordClass.editable),
  'exercise_restrictions': EntityInfo(RecordClass.editable),
  'exercises': EntityInfo(RecordClass.editable),
  'goal_progress': EntityInfo(RecordClass.appendOnly),
  'goal_status_events': EntityInfo(RecordClass.appendOnly, clientWritable: false),
  'goals': EntityInfo(RecordClass.editable),
  'gym_decisions': EntityInfo(RecordClass.appendOnly),
  'injuries': EntityInfo(RecordClass.editable),
  'injury_updates': EntityInfo(RecordClass.appendOnly),
  'meal_components': EntityInfo(RecordClass.editable),
  'meal_ingredients': EntityInfo(RecordClass.editable),
  'meal_plan_entries': EntityInfo(RecordClass.editable),
  'meals': EntityInfo(RecordClass.editable),
  'media_assets': EntityInfo(RecordClass.editable),
  'milestones': EntityInfo(RecordClass.editable),
  'muscle_assessment_items': EntityInfo(RecordClass.appendOnly),
  'muscle_assessments': EntityInfo(RecordClass.appendOnly),
  'muscle_priorities': EntityInfo(RecordClass.versioned),
  'muscles': EntityInfo(RecordClass.editable),
  'pain_entries': EntityInfo(RecordClass.appendOnly),
  'personal_records': EntityInfo(RecordClass.appendOnly, clientWritable: false),
  'personal_targets': EntityInfo(RecordClass.versioned),
  'planned_breaks': EntityInfo(RecordClass.editable),
  'profile_versions': EntityInfo(RecordClass.versioned),
  'reminder_rules': EntityInfo(RecordClass.editable),
  'schedule_entries': EntityInfo(RecordClass.editable),
  'session_exercises': EntityInfo(RecordClass.editable),
  'sets': EntityInfo(RecordClass.appendOnly),
  'settings': EntityInfo(RecordClass.editable),
  'sleep_logs': EntityInfo(RecordClass.editable),
  'split_day_muscles': EntityInfo(RecordClass.editable),
  'split_days': EntityInfo(RecordClass.editable),
  'split_status_events': EntityInfo(RecordClass.appendOnly, clientWritable: false),
  'split_versions': EntityInfo(RecordClass.versioned),
  'splits': EntityInfo(RecordClass.editable),
  'supplement_logs': EntityInfo(RecordClass.appendOnly),
  'supplement_phases': EntityInfo(RecordClass.versioned),
  'supplements': EntityInfo(RecordClass.editable),
  'template_exercises': EntityInfo(RecordClass.editable),
  'template_versions': EntityInfo(RecordClass.versioned),
  'water_logs': EntityInfo(RecordClass.appendOnly),
  'weak_point_events': EntityInfo(RecordClass.appendOnly),
  'workout_sessions': EntityInfo(RecordClass.editable),
  'workout_templates': EntityInfo(RecordClass.editable),
};

bool isWritableEntity(String entity) => syncedEntities[entity]?.clientWritable ?? false;
