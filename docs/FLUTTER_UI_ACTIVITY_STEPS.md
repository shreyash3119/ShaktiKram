# Lifestyle → Activity: compact steps UI and Steps History

UI only. No change to Health Connect import, `StepImportService`, `LifestyleService.setSteps`, the database or `backend/`.

## Activity tab (top to bottom)
1. **Steps card** (`StepsSummaryCard`, key `steps-card`): today's total, "of <goal> today", and a seven-day mini bar chart (today highlighted). Tap opens Steps History.
2. **One short row**: the **Health Connect tile** (icon, name, one line of status; tap to connect, retry or update; key `step-import-button`) and the **Manual log** button (key `manual-steps`).
3. **Log cardio** and **Hydration**: unchanged.

The old "Phone and watch steps / Update now" card and the full-size "Steps today" card are gone.

## Manual log dialog
A centred `ModalCard`, not a page. Steps field (`steps-field`), "Change day" (date picker, past days only), Save (`steps-save`). It calls `setSteps(n, localDate: day)` with source `manual`, so saving the same day again edits that day's record, and the import never overwrites it. A note shows when a count already exists for the day.

## Steps History (`/lifestyle/steps`)
- Day / Week / Month tabs, previous / next (next disabled on the current period).
- Total for the period; Week and Month also show the daily average (over days that have a count).
- Bar chart with a goal line when a step target is set.
- Date-wise list (newest first) with the source: Health Connect, Typed by hand or Estimate. In Week and Month, tapping a row opens that day.

## Assumptions
- Only one number per day is stored, so the **Day** tab charts the seven days ending on the chosen day, with that day highlighted.
- Weeks run Monday to Sunday, as in Reports.
- The tile shows short status text instead of the long explanation; Android's own permission screen explains read-only access.
- The history reads all saved days from the phone (up to 2000) through `stepHistoryProvider`.

## Not verified
Not compiled or run here (no Flutter SDK). Run `flutter pub get && dart format . && flutter analyze && flutter test`.
