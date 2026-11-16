# Reports UI redesign

Restyles the Reports screen (`reports_screen.dart`, `report_sections.dart`, `export_tab.dart`) to the new designs. Data, providers and
exports are unchanged. Not compiled or run here (no Flutter SDK); run `flutter analyze` and `flutter test`.

| Design | Code |
|---|---|
| Underline tabs (7, scroll sideways) | `UnderlineTabs`, keys `tab-<label>` |
| "Updated 12 min ago" and info button | Subtitle once a report is on the phone; `reports-info` opens "About reports" with a Refresh button |
| Period pills and stepper on every tab | Now also shown on Export; the compare switch is on Overview only |
| Freshness line | Only shown when updating, offline, failed or stale |
| Empty states | `NoteRow` (info tile and sentence) |
| Workouts | Compact Attendance / Training context rows when there is nothing; detailed cards otherwise |
| Strength | One card per exercise with fact chips, Estimated 1RM trend, Personal records |
| Body, Lifestyle | "Nothing logged this period" card with summary rows; detailed cards when data exists |
| Muscle exposure | Two-tone bar per muscle (direct, supporting) |
| Goals | Empty state with "Go to Progress"; Milestones as one "None yet" row |
| Export | Export a report, Saved on this phone (XLS/PDF badge, date, size, options), Backup |

## Assumptions
- Footnotes move out of cards into `InfoLine`s.
- The "Compare" switch is hidden on tabs other than Overview, so a comparison set there still applies to Export.
- Old `PillTabs`-based tab tests use `tab-<label>` keys; saved-file rows now show a badge instead of "Excel report ·".
