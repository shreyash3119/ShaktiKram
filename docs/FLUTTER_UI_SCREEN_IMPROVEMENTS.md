# Screen improvements (requirements checklist)

Implements `ShaktiKram_Screen_Improvements_Requirements.docx`. Not compiled or run here (no Flutter SDK).

| Req | Status |
|---|---|
| 2.1 Training top tabs | Done: `UnderlineTabs` (underline, scrolls sideways, keeps the active tab in view) |
| 2.2 Exercise icons | Done: icon comes from the equipment (`equipment_groups.dart`): free weights, machine, cable, bodyweight, cardio. Stretching/mobility icon needs training types (below) |
| 2.3 Training types | **Not done, needs a decision** (below) |
| 2.4 Machines section | Done on the phone: groups worked out from the equipment key (Machines, Free weights, Accessories, Bodyweight, Cardio). No new table. Unknown or custom keys go to Accessories |
| 2.5 Equipment selector | Done: search, group filters, group headings, alphabetical, selected state, count, fixed Done. "Add equipment" is not shown: there is no create-equipment flow yet |
| 2.6 Exercise cards | Done: equipment icon, name, primary muscle and equipment line, compound/isolation badge, equipment-group filter chips next to the muscle-group chips. Training-type filter waits for 2.3 |
| 2.7 Edit exercise | Equipment row uses the new icon and selector; training type waits for 2.3 |
| 3.1 to 3.5 Settings | Done: hub rows have no trailing summaries; Sign out and Danger zone / Clear data are only on Account (same confirmations, Clear data still does nothing) |

## Why training types are not in this patch
- `exercises.category` is limited by a database check to `compound` or `isolation`, and there is no training-type column or table.
- Sync only accepts known columns, so a phone-only field would not reach the server or backups.
- Storing it needs a backend migration (and the shared vocabulary), which was not part of this request.

## Test changes
- Training and Progress tab helpers use the `tab-<label>` keys. This also fixes two Progress tab taps in `management_screens_test.dart` that still looked for the old pill tabs.
