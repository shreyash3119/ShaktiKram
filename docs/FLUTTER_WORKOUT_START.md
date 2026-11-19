# Workout start, exercise picker and templates

Implements the designs `8a_WorkoutStart`, `8b_WorkoutAddExercise` and `8c_WorkoutTemplates`.

## Screens
- **Workout start** (`workout_builder.dart`): shown when no workout is running (Home / Training "Start workout") and when a
  day opened from the Workout Calendar has no exercises yet. Today's plan card, Templates and Add exercise tiles, Your
  splits (day pills, "Use Day N", other splits), Repeat a past session, and "Your workout" (drag to reorder, remove, note).
  Fixed bottom bar: Save template and Start workout · N. Nothing is written until Start, so going back loses nothing.
- **Add exercise** (`exercise_picker_screen.dart`): search, muscle-group and equipment filters, Recently used, A–Z/Z–A,
  "Show N more", Create custom exercise (opens the existing Add exercise sheet), Done · N added. Also used by the
  "Search exercises" button inside a running workout (adds to the end).
- **Templates** (`workout_templates_screen.dart`): current templates with version, exercise count and when last used;
  Use loads it into the Workout start list; "+ New template" opens the existing template editor.

## Data and rules
- Everything reads the existing providers (templates, splits, schedule, sessions, exercises). No backend or schema change.
- `WorkoutSessionService` gained two additive methods, `startSessionWith` and `addPlannedExercises`, that write the same
  rows as `startSession`/`addExercise`. A session is linked to a template version only if the list is still exactly the
  template's exercises, in order; otherwise it is an ordinary workout (exercises from the template keep their sets x reps
  targets).
- Save template uses the existing `createTemplate` (sets/reps targets kept for exercises that came from a template).
- "Sample values" in the design is a design note and is not shown.

## Add / Edit exercise
Layout and behaviour unchanged. Both now sit on the page background with card-coloured panels, the same label, title and
field styles as the other screens, and no outlines (`EditorPanel(color, bordered)`, `FieldBox(bordered)`,
`showEditorSheet(background)` are optional parameters; other screens are unaffected).
