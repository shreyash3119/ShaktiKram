# Readiness and deload rules

## Readiness ("Should I go today?")
Decision support only. It is not medical advice and not a guarantee that training is safe.

Wellness score (1 to 5, higher is better) is the average of: energy, sleep quality, motivation as entered, and soreness, fatigue, stress reversed (`6 - value`).
It needs at least 3 answers, otherwise there is no score.

Level, first match wins:
1. `review`: an injury is flagged for review (`injury_review_flag`), or recent pain is 7 or more (`high_pain`), or pain is flagged and recent pain is 5 or more (`pain_reported`). The summary suggests reviewing the symptoms, never a training decision.
2. `lighter`: wellness under 2.5 (`low_wellness`), slept under 5 hours (`short_sleep`), soreness 4 or more (`high_soreness`), fatigue 4 or more (`high_fatigue`).
3. `no_checkin`: no check-in today.
4. `limited_data`: a check-in with fewer than 3 answers.
5. `proceed`: the session may be reasonable; adjust as the warm-up feels.

Recent pain means the highest pain entry in the last 3 days that is not tied to a resolved injury.

## Deload signals
Patterns that may justify considering a deload. It never says one is necessary. Signals:
- `long_block`: 6 or more weeks since the last deload (or since the first workout when there was none).
- `persistent_fatigue`: at least 5 recent check-ins (last 10), fatigue 4 or more in at least half.
- `persistent_soreness`: the same for soreness.
- `performance_decline`: 2 or more exercises with a `declining` trend, trained in the last 3 weeks.
- `short_sleep`: at least 4 nights in the last 7 with an average under 6 hours.

Level: no signals `none`; one `watch`; two or more `consider_reviewing_deload`.
