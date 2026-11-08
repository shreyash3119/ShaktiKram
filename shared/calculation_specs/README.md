# Calculation rules

Each rule is written once here in plain language, has one implementation per layer, and shares test cases in `../test_vectors/`.
The server rule is a SQL function (`calc_*`) that takes one JSON object and returns one JSON object. The phone implements only what it
needs offline (next-set suggestion, PR detection, readiness) and must pass the same test cases. If server and phone disagree, a test fails.

Every result carries `value_kind`: `suggestion` (what the app proposes), `observation` (a pattern in your records), `estimated`, or
`user_assessment`. Nothing calculated is called `measured`. Nothing here diagnoses or gives medical advice, and no suggestion is applied automatically.

| Rule | Spec | Server implementation | Test cases | Offline on phone |
| --- | --- | --- | --- | --- |
| Estimated 1RM | `strength.md` | `calc_e1rm`, `pfs_e1rm` | `e1rm.json` | yes |
| Next-session suggestion | `strength.md` | `calc_progression`, `api_next_targets` | `progression.json` | yes |
| Personal records | `strength.md` | `pfs_detect_prs` (deferred trigger) | `backend/tests/94_stage4_records.test.sql` | yes (cases to be added with the Dart code) |
| Trend and plateau | `strength.md` | `calc_trend`, `v_exercise_trends` | `trend.json` | no |
| Readiness | `readiness_deload.md` | `calc_readiness`, `api_readiness` | `readiness.json` | yes |
| Deload signals | `readiness_deload.md` | `calc_deload_signal`, `api_deload_signals` | `deload.json` | no |
| Goal progress | `goals_alternatives.md` | `calc_goal_progress`, `v_goal_progress` | `goal_progress.json` | no |
| Alternatives, weak-point suggestions | `goals_alternatives.md` | `api_exercise_alternatives`, `api_weak_point_suggestions` | `backend/tests/95_stage4_insights.test.sql` | no |
| Daily briefing | `goals_alternatives.md` | `api_daily_briefing` | `backend/tests/95_stage4_insights.test.sql` | no |

Status: every threshold below is **proposed**. Change a number by editing the spec, the test cases and a new migration together.
