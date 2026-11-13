# Physical phone testing: fixes and missing features

Source: `ShaktiKram_Mobile_App_Screen_Issues_and_Requirements.docx` (your phone inspection). Scope: `application/` and `docs/` only. Nothing in `backend/` or `shared/` changed.

## Decisions you gave
1. **Seed data stays.** The two exercises and two goals from `seed.sql` are kept. They can now be edited, stopped (exercises) or archived (goals).
2. **The Nov 12 test workout is not a bug.** An empty workout never counts: not as a completed workout, an achievement, a statistic or training exposure.
3. **Finishing a workout with no sets** shows "No sets logged" with **Return to workout** or **Discard workout**. It is never completed.
4. **No hardcoded sample values.** Empty states are shown instead.

## What changed

| Area | Change |
|---|---|
| Empty workouts | Finish is blocked for a workout with no logged working set (discard or return). History lists existing empty workouts as "No sets logged, not counted" and lets you discard them. Home, Training and Progress count only finished workouts that have a logged working set. An achievement that the server found from an empty workout is hidden. Monthly totals use only workouts with sets. |
| Training overview | Hard-coded "Training insights" replaced by monthly totals from the server's `v_session_summary` (cached, with an age label). "Quick actions" now has working buttons. |
| Exercises | Add, edit and stop using exercises (past workouts keep them). Muscles, category, equipment, notes. Detail sheet. Search plus category, muscle-group and equipment filters. |
| Templates | Create, edit (saved as a new version), duplicate, delete. Reorder exercises; sets, rep range, rest. |
| Splits | Create (weekly, rolling or custom), edit (new version), activate (the other becomes inactive), stop following, duplicate, archive. Days can be rest days or use a template. |
| Schedule | Two-week list; tap a day to plan it from the active split, mark rest, or clear it. "Plan 4 weeks from the split" fills empty days only. A finished day is never changed. Today's plan (Home and Training) uses the day's template at its newest version. |
| Goals | Create, edit, pause, resume, complete, archive, reopen. Manual progress entries for goals the app cannot measure itself. Milestones: add, edit, delete. Completed and archived goals no longer show a progress bar. |
| Muscles | "Rate your muscles" (1 to 5) saves an assessment. Earlier ones are kept. "Nothing flagged" now says "Not enough data to assess" when there is nothing to assess from. |
| Lifestyle | Only the Recovery and readiness card changed: it shows the server's readiness (same as Home) instead of a placeholder. |
| Plumbing | The newest version number now counts as current, so a version saved offline shows at once. `ManagementError` messages are shown inline in forms. |

## Not bugs (expected empty states)
Strength trends, PR history, e1RM chart, body-composition, exposure and goal progress stay empty until finished workouts with sets and the server calculation exist. One weight reading draws no line (two are needed).

## Home vs Training
Several "Home" items in the report (Training insights, Active split, quick-action text) were Training Overview cards. Home now shows today's plan, readiness, consistency, body, lifestyle, insights, recent activity, highlights and alerts, all from real data or empty states.

## Limits and open points
- **Not compiled or run here** (no Flutter SDK). Only bracket and quote checks were done. Run `flutter pub get`, `flutter analyze`, `flutter test` and send me any output.
- The server-side streak, records and exposure are the backend's. The app cannot remove an achievement the server already created; it hides one tied to an empty workout.
- Edits that clear a field (for example removing a goal deadline) send `null`. If the backend rejects that, the change stays queued and the Sync status shows it. Check once on the phone.
- Reports and Settings screens were not in the inspection and still show sample cards (Phase 8).

## Phone test steps
1. **Empty workout:** Training > Overview > Start an empty workout > Start empty workout > Finish workout. Expect "No sets logged". Tap Return to workout (stays open), then Finish workout > Discard workout. History should not list it.
2. **Existing Nov 12 workout:** Training > History. It shows "No sets logged, not counted". Open it, tap Discard this workout, confirm. Home "Workouts this week" and the highlights should not include it.
3. **Exercise:** Training > Exercises > Add an exercise. Name, one main muscle, Save. Search it, filter by muscle group, open it, Edit, then "Stop using this exercise" and turn on "Show exercises not in use".
4. **Template:** Training > Splits > New template. Name it, add two exercises, set sets and reps, Save. Open it, change a set count, Save (version 2).
5. **Split:** Create a split, add two days (one with the template, one rest), turn on "Make this the active split", Save. Open the split to see Edit, Duplicate, Archive.
6. **Schedule:** Training > Schedule. Tap today, choose a day of your split. Tap "Plan 4 weeks". Back on Home, "Today" shows the planned day and Start workout opens it.
7. **Log a real set:** Start the planned workout, log one working set, Finish. History shows it counted; the monthly totals card fills (may take a sync).
8. **Goals:** Progress > Goals > New goal (title, type, measured how, target). Open the seed goal "Lean bulk": it shows Completed with no bar; Edit it or Reopen it. Record progress on a manual goal. Add a milestone.
9. **Muscles:** Progress > Muscles > Rate your muscles. Tap levels, Save. The list shows your ratings.
10. **Offline:** Turn on airplane mode and repeat steps 3 and 5. Everything saves; turn it off and check Sync shows 0 waiting.
11. **Persistence:** Close the app fully and reopen: everything above is still there.
