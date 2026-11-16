# Lifestyle UI redesign

Restyles `application/lib/features/lifestyle/presentation/lifestyle_screen.dart` to the new designs. State, providers and
`LifestyleService` calls are unchanged. Not compiled or run here (no Flutter SDK); run `flutter analyze` and `flutter test`.

| Design | Code |
|---|---|
| Underline tabs | `UnderlineTabs` (keys `tab-<label>`) |
| `+ Log` button | `lifestyle-log` opens "Log something": switches tab or opens the Add water dialog |
| Overview tiles | Sleep, Meals, Water, Steps (`tile-*`); links go to Recovery or Nutrition (targets live there) |
| Readiness | Server briefing level and reasoning; "Start/Update check-in" goes to Recovery |
| Hydration | +250, +500, Other (dialog), last 3 logs with Remove |
| Recovery | Sleep, Daily check-in (inline 1-5), Pain check-in (0-10), Injuries and Restrictions rows opening dialogs |
| Nutrition | Today, Today's meals, Add a meal, Saved meals (only if any), Targets |
| Supplements | Today list, Add a supplement (times per day 1-4) |
| Activity | Steps, Log cardio, Hydration |

## Assumptions
- Pain keeps a "Where" region chips row (not in the design) because `logPain` requires a body region.
- The Daily check-in no longer shows notes and the pain flag; saved values are kept when saving again.
- The Sleep tile has no target, so its link is "Log sleep".
- Old `PillTabs`-based tab tests now use `tab-<label>` keys.
