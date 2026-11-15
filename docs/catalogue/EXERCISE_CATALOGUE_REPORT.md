# ShaktiKram exercise catalogue: report and instructions

Prepared from the repository `main` branch (commit `594ffb5`). Nothing here has been run against your live Supabase project and nothing has been pushed.
The SQL was tested on a throwaway local PostgreSQL 16 database built from all 31 repository migrations (details in section 9).

## 1. Schema inspection report

| Item | What the repository defines |
|---|---|
| `exercises` | `id` (uuid), `name` (not blank), `is_custom` (default true), `category`, `equipment_id` (FK to `equipment`), `introduced_on`, `removed_on`, `notes`, plus the common columns `created_at, updated_at, deleted_at, rev, device_id`. Migrations `20261106000300` and `20261107000100`. |
| Category values | `ck_exercises_category_values`: `'compound'` or `'isolation'` (or NULL). |
| Unique key | `uq_exercises_name_alive` on `lower(name)` where `deleted_at is null`. **Name is unique ignoring case** among live rows, so the script skips a name that already exists instead of using `ON CONFLICT (name)`. |
| `exercise_muscles` | `id, exercise_id (FK), muscle_id (FK), role` plus common columns. Unique: `uq_exercise_muscles_alive` on `(exercise_id, muscle_id)` where not deleted. |
| Roles | `ck_exercise_muscles_role_values`: `'primary'`, `'secondary'`, `'indirect'`. The app writes primary and secondary only. |
| One primary rule | Not enforced by the database. The backend views (`v_*` exposure, record detection, alternatives) read the **primary** link only, so this catalogue gives every exercise exactly one primary, and the script never adds a second one. |
| `muscles` | `key` (unique), `group_key`, `label`, `is_custom`. 29 seeded rows. |
| `equipment` | `key` (unique), `label`, `is_available_at_gym`, `is_custom`. 27 seeded rows. |
| Reference guard | `pfs_reference_guard` protects `muscles`, `equipment`, `body_regions` from client edits. It is not attached to `exercises`, so built-in exercises stay editable from the app. |
| Triggers on exercises / exercise_muscles | `a_pfs_before_write` (sets `rev`, `updated_at`, keeps ids you supply), `b_pfs_block_delete` (no hard deletes), `z_pfs_audit` (audits updates). No insert audit. |
| RLS and grants | RLS on; only the owner may `select`; no direct client writes. The SQL Editor runs as `postgres`, which is not affected, so it can insert. |
| Existing seed exercises | ids `md5('seed-ex-1')` = `a2aa281c-377b-7519-250e-f6a179ecb16a` (Bench press) and `md5('seed-ex-2')` = `17f2d66c-4c80-e1c5-a446-d445e3ff0e30` (Lat pulldown). I checked both hashes. |
| Reference ids | Muscles and equipment use `md5('muscles:<key>')` / `md5('equipment:<key>')`. The script looks them up by `key`, so it works whatever the ids are. |

### Flutter side
- `Exercise` model reads `id, name, category, equipment_id, notes, is_custom, removed_on`. `isInactive` means `removed_on` is set.
- The exercise library (Training > Exercises) filters by category (compound/isolation), muscle group (the `group_key` of the primary muscle link), and equipment id. It lists primary and secondary links from `exercise_muscles`.
- My exercise editor creates custom exercises (`is_custom = true`) and writes `primary` and `secondary` links through the change queue. This catalogue changes none of that.
- Both tables are in the synced set, so rows added on the server reach the phone through the normal `api_pull_changes` revision cursor.

### Schema limits and how this catalogue handles them
- **No description column.** The one-sentence description is stored in `notes`.
- **No "active" flag.** Active means `removed_on IS NULL`; the script leaves `removed_on` empty.
- **One equipment per exercise.** Benches, racks and bars cannot be listed together: a barbell squat is `barbell`, not `barbell + squat_rack`.
- **No cardio exercises.** Treadmill, bike, stair-master and elliptical exist as equipment but this is a strength catalogue, so none are used.
- **NULL equipment is never used.** The reference table has a `bodyweight` item, so bodyweight exercises use it and the equipment filter keeps working.
- **Muscle groups are `chest, shoulders, back, arms, legs, core`.** There is no "lower back", "biceps", "triceps", "abs" or "obliques" group. Mapping: lower back is `spinal_erectors` (group back); biceps, triceps and forearms are group arms; abs and obliques are group core; calves, glutes, hamstrings, quads are group legs.
- **No separate soleus, hip flexors or neck.** Seated calf raise maps to `calves`.

## 2. Existing muscle reference mapping (29, reused, none created)

| Muscle key | Group | Exercises with it as primary |
|---|---|---:|
| `upper_chest` | chest | 6 |
| `middle_chest` | chest | 9 |
| `lower_chest` | chest | 4 |
| `front_delts` | shoulders | 9 |
| `side_delts` | shoulders | 4 |
| `rear_delts` | shoulders | 6 |
| `upper_traps` | back | 2 |
| `middle_traps` | back | 2 |
| `lower_traps` | back | 0 |
| `lats` | back | 19 |
| `rhomboids` | back | 0 |
| `spinal_erectors` | back | 3 |
| `biceps` | arms | 9 |
| `brachialis` | arms | 2 |
| `triceps_long_head` | arms | 3 |
| `triceps_lateral_head` | arms | 8 |
| `triceps_medial_head` | arms | 1 |
| `forearms` | arms | 5 |
| `quadriceps` | legs | 13 |
| `hamstrings` | legs | 7 |
| `glutes` | legs | 8 |
| `calves` | legs | 5 |
| `adductors` | legs | 1 |
| `abductors` | legs | 2 |
| `upper_abs` | core | 5 |
| `lower_abs` | core | 4 |
| `external_obliques` | core | 5 |
| `internal_obliques` | core | 0 |
| `transverse_abdominis` | core | 2 |

## 3. Existing equipment reference mapping (27, reused, none created)

| Equipment key | Exercises |
|---|---:|
| `barbell` | 22 |
| `dumbbell` | 34 |
| `ez_bar` | 4 |
| `kettlebell` | 3 |
| `flat_bench` | 1 |
| `adjustable_bench` | 0 |
| `squat_rack` | 0 |
| `smith_machine` | 4 |
| `cable_machine` | 24 |
| `lat_pulldown_machine` | 3 |
| `seated_row_machine` | 1 |
| `pec_deck_machine` | 2 |
| `chest_press_machine` | 1 |
| `shoulder_press_machine` | 1 |
| `leg_press_machine` | 2 |
| `leg_extension_machine` | 1 |
| `leg_curl_machine` | 2 |
| `calf_raise_machine` | 2 |
| `pull_up_bar` | 6 |
| `dip_station` | 2 |
| `assisted_pullup_machine` | 1 |
| `resistance_bands` | 8 |
| `treadmill` | 0 |
| `stationary_bike` | 0 |
| `stairmaster` | 0 |
| `elliptical` | 0 |
| `bodyweight` | 20 |

Not used (no strength exercise fits): `treadmill`, `stationary_bike`, `stairmaster`, `elliptical`, `adjustable_bench`, `squat_rack`. The first four are cardio. Benches and racks are used by exercises that need them but are recorded under the main implement (see limits above). Exercises are tagged `flat_bench` only for bench dips.

## 4. Dataset

- 144 exercises: 68 compound, 76 isolation.
- Counts by primary muscle group: legs 36, arms 28, back 26, chest 19, shoulders 19, core 16.
- Files: `exercise_catalogue.csv` / `.json` (one row per exercise) and `exercise_muscles.csv` (one row per link, 419 links).
- Names use sentence case ("Incline bench press"). The two existing exercises keep their exact names "Bench press" and "Lat pulldown".

## 5. Sources and how the data was compiled

**I did not browse or copy from ExRx, ACE or MuscleWiki in this session.** The catalogue was compiled from general exercise-science knowledge: standard exercise names, the usual compound/isolation split, and the muscles each movement is conventionally credited to by references like ExRx, ACE's exercise library and MuscleWiki. Descriptions are my own wording. Please treat it as a sensible starting catalogue, not a sourced reference database, and check any muscle assignment you care about against a source you trust.

Rules I applied: one primary muscle (the main mover); secondaries only for muscles that do real, direct work (not just stabilising); triceps heads are all listed since all three work in every triceps exercise, with the emphasised head as primary.

## 6. Entries where targeting or equipment is uncertain (25)

| Exercise | Note |
|---|---|
| Chest dips | Chest vs triceps emphasis depends on torso lean. |
| Pendlay row | Upper-back emphasis; lats vs mid-back as primary is a judgement call. |
| T-bar row | No T-bar/landmine item in the equipment list; mapped to barbell. Lats vs mid-back is approximate. |
| Wide-grip seated cable row | Primary muscle (mid traps vs lats) is approximate. |
| Chest-supported dumbbell row | Primary muscle (mid traps vs lats) depends on elbow angle. |
| Inverted row | Needs a low bar or rack; no matching equipment item, so mapped to bodyweight. |
| Dumbbell pullover | Lat vs chest emphasis is debated; categorised as isolation. |
| Face pull | Often called a compound pull; categorised as isolation for rear delts. |
| Rack pull | Primary muscle (erectors vs glutes vs traps) is approximate. |
| Back extension | Normally done on a back-extension bench, which is not in the equipment list; mapped to bodyweight. |
| Upright row | Some lifters find this uncomfortable for the shoulders; muscle split is approximate. |
| Hammer curl | Brachialis chosen as primary; biceps and brachioradialis share the work. |
| Reverse curl | Forearms (brachioradialis) chosen as primary. |
| Cable triceps pushdown | Head emphasis between the three triceps heads is approximate. |
| Reverse-grip triceps pushdown | Head emphasis is approximate. |
| Close-grip bench press | Triceps vs chest primary is a judgement call. |
| Farmer's carry | Whole-body carry; forearms chosen as primary for grip work. |
| Barbell squat | Squat rack not captured because an exercise has one equipment item. |
| Reverse lunge | Quads vs glutes primary is a judgement call. |
| Conventional deadlift | Prime mover is shared by glutes, hamstrings and erectors; glutes chosen as primary. |
| Sumo deadlift | Primary muscle is approximate. |
| Nordic hamstring curl | Needs a partner or anchor; no matching equipment item. |
| Seated calf raise | Seated variants bias the soleus; the muscle list has a single calves entry. |
| Plank | Isometric; primary muscle (deep core vs rectus) is a judgement call. |
| Barbell rollout | Usually done with an ab wheel, which is not in the equipment list. |

## 7. How the script stays safe

Runs in one transaction. Aborts before writing if any muscle, equipment item or required column is missing. Never deletes, truncates, resets ids or touches `is_custom = true` rows. Re-running adds nothing: ids are deterministic, names that already exist are skipped, existing links are not duplicated, a second primary is never added, and links you removed are not restored. For the two seed exercises only empty fields are filled.

If you already created an exercise with the same name as a catalogue one (for example "Pull-ups" from phone testing), that catalogue entry is skipped and listed in a NOTICE message. Your exercise stays as it is. You can rename yours and re-run to add the built-in one.

## 8. Run it in the Supabase SQL Editor

1. Open the Supabase dashboard > SQL Editor > New query.
2. Check the starting point: `select count(*) from exercises; select count(*) from muscles; select count(*) from equipment;` expect 2, 29, 27. (More exercises is fine.)
3. Paste the whole `seed_exercise_catalogue.sql` and click Run. It ends with a 10-row table. Expect all `OK`. Rows 1 and 3 read `CHECK` only if a same-named exercise was skipped or you edited some links; the NOTICE (Messages tab) names them.
4. Run the blocks of `seed_exercise_catalogue_validation.sql` one at a time (select a block, then Run selected) for the detailed checks and the alphabetical list.
5. Running it twice is fine; the second run adds nothing.
6. To undo (only if you want to): there is deliberately no delete in the script. Built-in catalogue rows can be soft-deleted by the app (Stop using this exercise), not removed.

## 9. What was tested

On a local PostgreSQL 16 with all 31 repository migrations applied (with stand-ins for Supabase's roles and `auth.uid()`), plus the seed exercises:
- First run: 144 exercises and 419 links created, both seed ids kept, all checks OK.
- Second run: no rows or revision numbers changed (idempotent).
- A custom exercise "PULL-UPS" already present: skipped with a NOTICE, no error, no duplicate.
- A seed exercise whose category was already edited, and a seed exercise whose primary was already set to another muscle: both kept; no second primary added.
- The detailed validation file ran without errors.

**Not tested:** the real Supabase project (as instructed), the `api_pull_changes` path with a real device, and the Flutter app receiving the rows. Those need your project and phone.

## 10. Trigger and verify sync in the app

The script bumps each row's `rev` (the sync cursor), so every device sees them on its next pull. The first pull after running may take a few pages (about 560 records).

1. Phone online, signed in. Open ShaktiKram and wait for sync (Settings > Sync status, or the sync indicator) to show nothing waiting.
2. If it does not pull by itself: use Sync now, or swipe the app away and reopen it.
3. Training > Exercises: the list should show about 144 built-in exercises plus any you made.
4. Filters: category Compound / Isolation; muscle group Chest, Back, Shoulders, Arms, Legs, Core; equipment Barbell, Dumbbell, Cable machine, Bodyweight and so on. Each should narrow the list and the counts should look right.
5. Open "Bench press": category Compound, equipment Barbell, primary Middle chest, secondaries Front delts and two triceps heads, with the description in the notes.
6. Open "Lat pulldown": Compound, Lat pulldown machine, primary Lats.
7. Go to airplane mode and reopen Training > Exercises: the full list should still show (it is stored on the phone).
8. Create a new exercise in the app to confirm custom exercises still work and appear marked as yours.
9. If the list stays at 2 exercises after a few minutes: check Sync status for an error, confirm the owner account is the one signed in, and tell me what the status line says.
