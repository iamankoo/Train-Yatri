# Railway database (Block 2)

Offline SQLite foundation for Train Yatri's static railway knowledge:
stations, trains, routes and (where the source provides it) operating
calendars. This document explains where that data comes from, how the
database is built, and how the app consumes it.

## Status: real dataset acquired and packaged

`assets/database/railway.db` is built from two legitimate, licensed,
publicly-available sources (full detail below), reproducibly via
`scripts/acquire_railway_data.dart` + `scripts/transform_railway_data.dart`
+ `bin/import_railway_data.dart`. Nothing in it is invented.

### Sources

**1. Train timetable - primary source, for trains/stations/route stops**

- **Original publisher:** Ministry of Railways, Government of India, via
  [data.gov.in](https://www.data.gov.in/catalog/indian-railways-train-time-table)
  (the Open Government Data Platform India), under the
  [Government Open Data License - India (GODL)](https://www.data.gov.in/government-open-data-license-india),
  which permits reuse including commercial use with attribution.
- **Mirror actually used:** data.gov.in's own catalog page returns HTTP
  403 to automated fetches and requires interactive/registered browser
  access, so this project uses the well-known, widely-cited mirror at
  [github.com/itzmeanjan/indian-railway](https://github.com/itzmeanjan/indian-railway)
  (`data/Train_details_22122017.csv`, MIT-licensed repository, data
  explicitly attributed to data.gov.in in its README), retrieved
  2026-09-02.
- **Dataset date:** the filename and file content indicate this is a
  snapshot of the timetable as published **22 December 2017**.
- **Fields used:** train number, train name, stop sequence, station
  code, station name, arrival time, departure time, cumulative distance
  from origin.

**2. Station geography - supplementary source, for state/coordinates only**

- **Publisher:** [github.com/datameet/railways](https://github.com/datameet/railways),
  a community-maintained dataset by [Sanjay Bhangar](https://twitter.com/sanjaybhangar)
  and [Sajjad Anwar](https://twitter.com/geohacker).
- **License:** [CC0](https://wiki.creativecommons.org/wiki/CC0) (public
  domain dedication).
- **Retrieved:** 2026-09-02, from `stations.json` (commit `e0c538a`,
  2016-08-08).
- **Fields used:** state, latitude, longitude - added only to a station
  already present from source 1, matched by normalized station code.
  Never used to add a station, or to override a code/name from source 1.

### Known dataset limitations (read before trusting a number)

- **The data is a 2016-2017 snapshot, not current.** Indian Railways
  timetables, train numbers and routes change over time; this dataset
  does not reflect trains introduced, renumbered, or discontinued since
  then. The app must never present this as live or current information
  - it is exactly what Block 1's product rules call "static railway
  knowledge," now with a concrete date attached. Treat `dataset_version`
  (readable via `getDatasetMetadata()`) as that date, always.
- **No running-day/weekly-calendar data.** Neither source above
  provides it, and no other legitimate bulk-downloadable source could
  be found (the live National Train Enquiry System is a live/interactive
  lookup, not a bulk dataset, and scraping it per-train would both
  violate the "no live-status scraping in this block" rule and likely
  its terms of use). `running_days` is therefore empty for every train.
  `RailwayRepository.getRunningDays()` correctly returns `null` for all
  11,112 trains - this is honest absence, not a bug.
- **8,148 station codes from source 1; only 7,680 (94%) matched a
  station in source 2** and got state/coordinates. The remaining 468
  have `city`/`state`/`latitude`/`longitude` all `NULL` - they are still
  real, valid stations (present in the primary government-derived
  source), just without geo enrichment.
- **5 of 186,107 route-stop rows (0.003%) were rejected** - the source
  literally contains `NA` for arrival/departure/distance at station
  `KGIH` on 5 specific train entries. Rejected and reported, not
  silently coerced into a fake time.
- **1 train number's name conflicted** across rows in the source
  (`scripts/transform_railway_data.dart` logs every such conflict); the
  first-seen name was kept deterministically rather than guessed.
- **`is_active` is not provided by the source** and is left blank,
  which the import pipeline treats as "active" by convention (see
  `docs/RAILWAY_DATABASE.md#input-format` below) - this reflects "was an
  operating scheduled service in the Dec-2017 snapshot," not "is running
  today."
- Coverage is **not** "all Indian Railways trains" - it is exactly what
  the December 2017 government timetable export contained: 11,112
  unique train numbers, 8,148 station codes, 186,102 imported route
  stops. Do not represent it as more complete than that.

### Coverage report

| | Count |
|---|---|
| Stations imported | 8,148 |
| Stations enriched with state/coordinates | 7,680 (94.3%) |
| Trains/services imported | 11,112 |
| Route stops imported | 186,102 |
| Route stops rejected (source `NA` values) | 5 |
| Running-day records | 0 (no source found - see limitations) |
| Train name conflicts found (first-seen kept) | 1 |
| `railway.db` size on disk | 18,128,896 bytes (~17.3 MB) |
| `railway.db` size inside the release APK (compressed) | 7,634,259 bytes (~7.3 MB) |
| SQLite `integrity_check` | `ok` |

### Reproducing this database

```bash
dart run scripts/acquire_railway_data.dart --output raw_data
dart run scripts/transform_railway_data.dart --input raw_data --output build_data
dart run bin/import_railway_data.dart \
  --stations build_data/stations.csv \
  --trains build_data/trains.csv \
  --route-stops build_data/route_stops.csv \
  --running-days build_data/running_days.csv \
  --output assets/database/railway.db \
  --source "Train_details_22122017.csv (data.gov.in via github.com/itzmeanjan/indian-railway mirror) + stations.json (github.com/datameet/railways, CC0)" \
  --source-version "2017-12-22 timetable snapshot; datameet stations retrieved 2026-09-02"
```

`raw_data/` and `build_data/` are gitignored (reproducible, not
committed); `assets/database/railway.db` - the actual app asset - is
committed.

### If a newer/better source is found later

A future update replacing this dataset with a fresher or more complete
one should: re-run the three commands above against the new source,
update the "Sources" and "Coverage report" sections above, bump the
app's own version (see "Database versioning" below for why that's
required for existing installs to actually receive it), and note in the
release what changed.

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

See "Known dataset limitations" above for everything specific to the
data itself (its 2017 vintage, no running-days, the 468 stations without
geo enrichment, the 5 rejected rows). Architecturally, beyond that:

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
