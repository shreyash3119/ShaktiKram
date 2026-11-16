# Progress UI redesign

Applies on top of commit `54ba463`. Nothing here changes `backend/`, `shared/` or the schema.

| Design | Code |
| --- | --- |
| Header: "Updated 2 min ago" + info button | `ProgressScreen`, `_AboutDialog` |
| Underlined text tabs | `UnderlineTabs` (`core/widgets/section_widgets.dart`, shared with Lifestyle) |
| Overview: 4 stat tiles, Strength trends, Training exposure | `_Overview` |
| Strength: 3 summary rows + "Nothing to show yet" | `_StrengthTab` |
| Body: weight card with 1M/3M/6M/1Y, Log weight; composition and weight rows | `_BodyWeight`, `_BodyRows` |
| Muscles: Your ratings, exposure bars, little direct work | `_MuscleRatings`, `_Exposure`, `_WeakPoints` |
| Goals: goal cards, New goal, Archived goals, Milestones | `_GoalsTab` |

## Assumptions
- **Header subtitle** is the age of the newest server answer among the daily briefing, strength trends, goal progress and exposure ("Not updated yet" when none). The info button explains what is on the phone and what the server calculates, with "Refresh now".
- **Freshness lines** (`Calculated by the server 5 h ago · Refresh`) now appear only when an answer is old, offline or failed. A healthy answer adds nothing.
- **Strength rows** open like an accordion: tapping a row shows its detail card (trends list, per-exercise chart, PR list) under the summary. The first row that has data opens by default.
- **Stat tile bars**: the streak bar is streak ÷ longest streak, the goal bar is the server's progress %. Latest record and Weight show an empty track, as drawn.
- **"See streak"** opens the Training tab (it has no streak view of its own).
- **Body composition** row shows the latest body-fat reading and opens a dialog with fat mass, lean mass and the estimate note. With no reading it links to Lifestyle. The **Weight** row opens the measurement history.
- **Exposure bars**: longer and darker = more direct sets (last 4 weeks, most first).
- **Goals**: archived = goals not in the active list (status archived). Tapping a goal still opens the existing actions sheet.
- Removed: Recent highlights, the "Show archived goals" switch, the separate Measurement history and Body (last measured) cards. Their data is reachable as described above.
- The weight dialog is Home's `showLogWeight`.
