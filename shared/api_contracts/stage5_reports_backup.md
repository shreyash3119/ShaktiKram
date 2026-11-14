# Stage 5: reporting service (FastAPI)

Base path `/api/v1`. Every route needs `Authorization: Bearer <the owner's Supabase access token>`. No token: 401. A valid token of another account: 403.
The service reads the database as the read-only role `pfs_reader`. Restoring a backup is not an API operation (see `backend/BACKUPS.md`).

## Period parameters (reports)

| Parameter | Used by | Notes |
| --- | --- | --- |
| `period` | all | `daily`, `weekly`, `monthly` (default), `quarterly`, `half_yearly`, `yearly`, `custom`, `complete` |
| `year` | monthly, quarterly, half_yearly, yearly | |
| `month` | monthly | 1 to 12 |
| `quarter` | quarterly | 1 to 4 |
| `half` | half_yearly | 1 or 2 |
| `day` | daily | `YYYY-MM-DD` |
| `week_start` | weekly | any date in the week; weeks start on Monday |
| `date_from`, `date_to` | custom | at most 3660 days |
| `compare` | summary, export | `true` adds the previous period of the same kind or length |

A missing or invalid value gives 422 with the reason.

## Routes

| Route | Returns |
| --- | --- |
| `GET /reports/periods` | the allowed period kinds |
| `GET /reports/summary` | JSON: `period`, `training` (with `attendance`), `strength`, `body`, `muscles`, `injuries`, `recovery`, `lifestyle`, `goals`, `context`, `observations`, and `comparison` when asked |
| `GET /reports/export?format=xlsx` | an Excel workbook: a `Summary` sheet and one sheet per kind of record, with units in the headings and filters |
| `GET /reports/export?format=pdf` | a PDF report with tables, charts and key observations |
| `GET /backup/export` | the full backup (zip). `include_media=true` adds the media files (needs `SUPABASE_URL`) |
| `GET /backup/export?format=csv` | a zip of CSV files, one per table. Not restorable |
| `POST /backup/validate` | upload a backup zip; returns `ok`, `errors`, `warnings`, row `counts`, `exported_at` |

## Labels

Estimated values (estimated 1RM, fat and lean mass, nutrition) and the user's own muscle ratings stay labelled as such in every export.
Observations are statements taken from the figures. They are not medical advice and not a diagnosis.
