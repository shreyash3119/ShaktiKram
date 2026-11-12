# Phase 7: Progress and Home

## What changed
- **Insight cache** (SQLite schema v3, table `insight_cache`): server-calculated answers are saved with the time they were fetched. `InsightRepository` returns the saved answer at once and refreshes in the background. A failed refresh keeps the saved answer and records the error, so offline is explicit. Freshness: briefing 15 min, views 30 min to 1 h.
- **BackendGateway** gained `callInsight(function, params)` and `readView(view, ...)`. Both are read-only; no backend change.
- **Progress screen**: PRs, achievements, goals and measurements are read from SQLite. Trends, per-session bests, goal progress and milestones, body composition, exposure and muscle ratings come from the cache and show a status line ("Calculated by the server 2 h ago", "Offline. Showing the answer from ...") with a Refresh link.
- **Home** is a composition: today's plan, running session, recent sessions, logs and records from the phone; readiness, deload, streak, trends and weak points from `api_daily_briefing`. The quick weight card is unchanged.
- Removed design-only cards: status toggle, weekly summary (volume/time), records duplicate, photos, compare periods, volume/frequency charts. They need data the backend does not expose yet.

## Rules kept
- No progression, PR, e1RM or readiness logic in Flutter. Widgets only format server values.
- Trends and suggestions are labelled as observations; fat and lean mass as estimates; muscle ratings as the person's own.

## Decisions for you
1. Sign-out does not clear the insight cache (same device, same owner). Say if it should.
2. "Workouts this week" on Home counts completed sessions on the phone; volume and active time are left out until a backend summary exists.
3. Charts use the last 300 `v_exercise_session_best` rows and 60 `v_body_composition` rows.

## Backend requests / pending
- None new. Still open from earlier: F5 (`api_next_targets` caching), Stage 5 exports (D18), optional `paused_at` on `workout_sessions`.

## Verified
Nothing was compiled or run in this environment (no Flutter SDK); only bracket/quote checks. Run `flutter pub get`, `flutter analyze`, `flutter test`. New tests: `insight_cache_test`, `progress_data_test`, `progress_screen_test`, `home_screen_test`.
