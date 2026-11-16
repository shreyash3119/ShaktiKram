# Home UI redesign

Applies after Training stages 1 and 2. Nothing here changes `backend/`, `shared/` or the database schema.

| Design | Code (`home_screen.dart`) |
| --- | --- |
| Header: bell with count, refresh | `_HeaderButtons`, `_AlertsDialog` |
| Today card with status pill (5 states) | `_TodayCard`, `_InProgressBody` |
| "Today's status" dialog | `showTodayStatus` / `_StatusDialog` |
| Log weight / Log meal / Add water / History | `_QuickTiles`, `showLogWeight`, `_AddWaterDialog` |
| Readiness dial + Consistency | `_ReadinessAndConsistency` |
| Lifestyle today + weight row | `_LifestyleCard` |
| Insights + Muscle priority | `_InsightsCard` |
| "Updated … Decision support only" line | `_FreshnessNote` |

## Status mapping
| Status | What it does |
| --- | --- |
| Rest | plans today as a rest day (`setScheduleDay(rest: true)`) |
| Skipped | marks today's schedule entry `skipped` (creates one if none) — `markDaySkipped` |
| In progress | starts the planned workout, or continues the running one |
| Completed | finishes the running workout (after a confirm), or, with none running, records a finished workout with no sets and links today's entry — `completeWithoutSets`. It is shown but never counted, as the dialog note says |
| Plan for tomorrow (Skipped card) | today's entry becomes `rescheduled`, tomorrow gets the same plan — `moveDayToTomorrow` |

The pill shows the state derived from the data: a running workout is In progress; a completed entry or any finished workout today is Completed; then Skipped; then Rest; otherwise "Set status". Rest and Skipped are refused while a workout is running.

## Removed
Recent activity, Highlights, Alerts, Quick actions, Body overview, Quick log weight, the sync chip and the "More" label. Their content moved: alerts → bell dialog; weight → Log weight dialog and the Lifestyle card; readiness reasons and deload → tap the dial; the full insight list → tap Insights.

## Assumptions
- No Pause button (no paused state exists).
- The Completed card's design is cut off in the image; it shows the workout name, a "View workout" button, or the not-counted sentence.
- "Exercise x of y" counts exercises that are not skipped; the bar shows exercises with a logged working set.
- Streak and Longest show "–" until the server briefing has loaded.
- History opens the Training tab (it cannot open a given sub-tab).
- Sync status is no longer shown on Home; the refresh button syncs and refreshes the briefing. Full status stays in Settings.
- Add water offers +250 / 500 / 750 / 1000 ml.
