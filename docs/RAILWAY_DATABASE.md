# Railway database (Block 2)

Offline SQLite foundation for Train Yatri's static railway knowledge:
stations, trains, routes and (where the source provides it) operating
calendars. This document explains where that data comes from, how the
database is built, and how the app consumes it.

## Status: infrastructure only, no data yet

**This repository does not currently contain a real railway dataset.**
Everything described below - the schema, the import pipeline, the
repository, the tests - is real and fully working, but it has never
been run against actual Indian Railways data, because none has been
supplied. `assets/database/railway.db` does not exist and is
deliberately **not** listed in `pubspec.yaml`'s `assets:` section yet -
adding a path there that doesn't exist would break the Flutter build.

To finish Block 2 for real:

1. Obtain a legitimate railway dataset (see "What's needed" below).
2. Convert/export it into the four CSV files described under "Input
   format".
3. Run `dart run bin/import_railway_data.dart` (see "Building the
   database") to produce `assets/database/railway.db`.
4. Add `- assets/database/railway.db` to `pubspec.yaml`'s `assets:`
   list.
5. Record the dataset's source/version in this document.

Until then, nothing in the running app calls into this code - Home
screen behavior is unchanged from Block 1 - so there is no broken or
fake-data user experience in the meantime.

### What's needed

A dataset that provides, at minimum:

- **Stations**: code, name, and ideally city/state/coordinates.
- **Trains/services**: number, name.
- **Route stops**: for each train, its ordered stops with arrival/
  departure times and (for overnight trains) which day of the journey
  each stop falls on.
- **Running days** (optional but valuable): which days of the week each
  train operates. Many open Indian Railways datasets do not source this
  authoritatively - the schema and domain model represent that
  explicitly via `DataConfidence` rather than assuming every train runs
  daily.

Whatever source is used, its licensing must permit bundling the derived
data inside the app.

## Architecture

```
data source (CSV)
      |
      v
lib/data/import/          <- parses, validates, normalizes, writes SQLite
      |
      v
assets/database/railway.db   <- built once, shipped as a Flutter asset
      |
      v
lib/data/database/        <- copies the asset to a writable file on first run
      |
      v
lib/data/repositories/    <- the ONLY place that runs SQL
      |
      v
lib/domain/repositories/RailwayRepository (abstract)
      |
      v
future features (Block 3+) depend on RailwayRepository only,
never on SQL or sqflite directly
```

## Schema

Defined in `lib/data/database/schema.dart`, applied as plain `CREATE
TABLE IF NOT EXISTS` statements (no external migration framework - see
"Versioning" below for why that's deliberate for now).

| Table | Purpose |
|---|---|
| `schema_meta` | Single row: schema version + dataset provenance/counts. |
| `stations` | One row per station. `normalized_code`/`normalized_name` are what queries actually match against (see Normalization). |
| `trains` | One row per train/service identity (not per journey date). |
| `route_stops` | One row per (train, stop). `day_offset` is days since the train's origin departure - see "Overnight trains" below. |
| `running_days` | One row per train with a weekly operating calendar, when the source provides it. `confidence` is `'confirmed'` only when the source explicitly backs it - otherwise `'unknown'`. |

Indexes (all in `schema.dart`):

- `idx_stations_normalized_code` (unique) - exact code lookup.
- `idx_stations_normalized_name` - name search (`LIKE 'prefix%'`).
- `idx_trains_normalized_number` (unique) - exact number lookup.
- `idx_trains_normalized_name` - name search.
- `idx_route_stops_train_sequence` - a train's ordered route.
- `idx_route_stops_station` - "which trains stop here" queries.
- `idx_route_stops_train_station` - train+station lookups.

`test/data/database/query_plan_test.dart` builds a ~300-station/
~150-train synthetic dataset and asserts via `EXPLAIN QUERY PLAN` that
the repository's actual query shapes use these indexes rather than
scanning the table.

### Overnight trains

A route stop's chronological position is `(day_offset, arrival_time)`,
not `arrival_time` alone. A train departing at 23:50 on day 0 and
arriving at 00:10 on day 1 has `day_offset: 1` on that later stop, even
though `00:10 < 23:50` as raw clock times - nothing about this is
inferred from a fabricated calendar date. See
`lib/domain/entities/railway_time.dart` and
`lib/domain/entities/route_stop.dart`.

### Normalization

`lib/domain/services/railway_normalization.dart` defines exactly two
deterministic rules, used identically by the import pipeline (writing
`normalized_*` columns) and the repository (normalizing a caller's
query):

- `normalizeName`: trim, lowercase, collapse whitespace runs.
- `normalizeCode`: trim, uppercase.

No fuzzy matching, no AI. SQLite's `LIKE` is ASCII case-insensitive by
default, so a lowercase `normalizeName`d query also matches the
uppercase `normalized_code` column without a second normalization pass.

## Input format

Four CSV files, first row = header. Extra columns are ignored; missing
optional columns are fine.

**stations.csv**
```
code,name,city,state,latitude,longitude
```
`code` and `name` are required. `city`/`state`/`latitude`/`longitude`
may be blank - they are stored as `NULL`, never a placeholder.

**trains.csv**
```
number,name,is_active
```
`number` and `name` are required. `is_active` is `1`/`0`/`true`/`false`/
blank (blank = active).

**route_stops.csv**
```
train_number,stop_sequence,station_code,arrival_time,departure_time,day_offset,distance_km
```
`train_number` must match a row in `trains.csv`; `station_code` must
match a row in `stations.csv`. `stop_sequence` is a 1-based integer,
unique per train. `arrival_time`/`departure_time` are `HH:MM` or
`HH:MM:SS` 24-hour (blank at the origin/terminus respectively).
`day_offset` defaults to `0`.

**running_days.csv**
```
train_number,monday,tuesday,wednesday,thursday,friday,saturday,sunday,confidence
```
Each day column is `1`/`0`/`true`/`false`. `confidence` must be exactly
`confirmed` to be trusted as such - anything else (including blank) is
stored as `unknown`.

## Building the database

```bash
dart run bin/import_railway_data.dart \
  --stations stations.csv \
  --trains trains.csv \
  --route-stops route_stops.csv \
  --running-days running_days.csv \
  --output assets/database/railway.db \
  --source "<dataset name and URL>" \
  --source-version "<dataset's own version/date, if any>"
```

The tool always rebuilds from a clean slate (deletes `--output` first
if present) so the result is deterministic given the same inputs. It
prints a full report: rows imported per table, every rejected row with
its file/line/reason, the SQLite `integrity_check` result, and the
resulting file size. It exits non-zero if `integrity_check` fails or if
zero stations/trains were imported.

Every rejected row is reported, never silently dropped - see
`lib/data/import/import_report.dart`.

## Database versioning

Two independent version concepts, both readable at runtime via
`RailwayRepository.getDatasetMetadata()`:

- **`schema_version`** (`lib/data/database/schema.dart`): the *table
  structure*. Currently `1`.
- **`dataset_version`**: the *railway data's own* version/date string,
  as passed to `--source-version` at import time. Independent of schema
  version - a new dataset import with the same table structure keeps
  `schema_version` unchanged.

`RailwayDatabase` (`lib/data/database/railway_database.dart`) compares
the on-disk copy's `schema_version` against the code's expected
`schema.schemaVersion` on every open; a mismatch causes the on-disk
copy to be deleted and re-copied fresh from the bundled asset. This is
intentionally a full replace, not an in-place migration - there is no
user data in this database to preserve, so a real migration framework
(`ALTER TABLE`-based upgrades) is not justified yet. If a future schema
change needs to preserve something, that's the point to add one.

## Asset packaging

`assets/database/railway.db` (once it exists) ships inside the app
bundle, which is read-only. `RailwayDatabase.open()`:

1. Checks whether the app's writable database directory already has
   `trainyatri_railway.db`.
2. If not, copies the bytes out of the asset bundle into that file
   (`assets/database/railway.db` -> `<app databases dir>/trainyatri_railway.db`).
3. Opens the writable copy, enables `PRAGMA foreign_keys = ON`, and
   compares its `schema_version` (see above).

The copy happens at most once per app install (or once per app update
that bumps `schema.schemaVersion`) - not on every launch. Covered by
`test/data/database/railway_database_test.dart`.

## Repository API

`lib/domain/repositories/railway_repository.dart` is the only surface
future features are allowed to depend on:

- `searchStations(query, {limit})`
- `getStationByCode(code)`
- `searchTrains(query, {limit})`
- `getTrainByNumber(number)`
- `getRoute(trainId)`
- `getTrainsAtStation(stationId, {limit})`
- `getRunningDays(trainId)`
- `getDatasetMetadata()`

`lib/data/repositories/sqlite_railway_repository.dart` is the only
implementation, and the only file in this codebase allowed to contain
SQL for railway data.

## Known limitations

- No dataset is bundled yet (see "Status" above) - this is the primary
  limitation and blocks the rest of Block 2's original scope.
- Running-day data honesty depends entirely on the source: if the
  eventual dataset doesn't distinguish "confirmed" from "unknown"
  itself, every row will import as `confidence: unknown` and the UI
  must respect that.
- Station search is prefix-based (`LIKE 'query%'`), not a general
  substring or fuzzy search - deliberately, per the "no AI/fuzzy
  matching in this block" requirement.
- No connecting-journey discovery - `getRoute`/`getTrainsAtStation`
  are the building blocks for that, not an implementation of it.

## Rebuilding after a dataset update

Re-run `dart run bin/import_railway_data.dart` with the new source
files and a new `--source-version`, then replace
`assets/database/railway.db`. Because `RailwayDatabase` compares
`schema_version` (not `dataset_version`) to decide whether to re-copy,
a dataset-only update (same schema) requires bumping the app's own
version so users actually receive the new asset - a same-schema,
new-dataset release does not automatically invalidate a device's
existing copy on its own. If in-place dataset refresh without a schema
bump becomes a real requirement, that's a deliberate follow-up, not
implicit behavior here.
