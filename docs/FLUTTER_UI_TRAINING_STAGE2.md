# Training UI, stage 2: editors and exercise details

Applies on top of stage 1. Nothing here changes `backend/`, `shared/` or the database schema.

| Design | Code |
| --- | --- |
| Add exercise (bottom sheet) | `training_exercise_screens.dart` → `_ExerciseForm` (add layout) |
| Edit exercise (full page) | same form, edit layout, opened as a full-screen route |
| Exercise details (full page) | `_ExerciseDetailPage` |
| New template | `_TemplateEditor` in `training_management_screens.dart` |
| New split | `_SplitEditor` in the same file |

Shared pieces are in `training_editor_widgets.dart` (`EditorPanel`, `DashedButton`, `SquareIconButton`, `MuscleChip`, `AddChip`, `MuscleGroupPicker`, `pickMuscles`, `pickEquipment`).
`FieldBox` gained optional `textAlign`, `suffix` and `multiline`; the defaults are unchanged, so other screens look the same.

## Assumptions
- **Equipment is one item per exercise** (the data model has a single `equipment_id`). The Add sheet shows the chosen item as a removable chip plus "+ Add equipment" / "Change equipment"; the Edit page uses a dropdown-style row. The design shows two chips (Barbell, Flat bench); supporting several needs a schema change, so it is left out.
- **Movement type on Edit** shows Compound / Isolation only, as designed. An exercise with no category shows neither selected until one is tapped; "Not set" stays on the Add sheet.
- **Stats on the details page** come from the personal records already on the phone: "Best set" is the heaviest `max_weight` record (kg × reps), "Est. 1RM" the best `est_1rm` record. With no records both show "—".
- **Archive** keeps the existing behaviour (no confirmation, nothing deleted); an archived exercise shows an "Archived" chip and a "Use this exercise again" button.
- Muscle group tabs are ordered Arms, Back, Chest, Shoulders, Core, Legs, then any other group. A muscle chosen as main cannot also be chosen as helping (and the reverse).
- The split day count reads "n of 7" for weekly splits and "n days" otherwise; "+ Add day" is disabled at 7 days for weekly.

## Not changed
Template and split behaviour, validation messages, the Duplicate / Delete template buttons, and the split actions sheet.
