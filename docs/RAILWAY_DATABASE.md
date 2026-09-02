# Railway database (Block 2)

Offline SQLite foundation for Train Yatri's static railway knowledge:
stations, trains, routes and (where the source provides it) operating
calendars. This document explains where that data comes from, how the
database is built, and how the app consumes it.

## Status: real dataset acquired and packaged

`assets/database/railway.db` is built from three legitimate, licensed,
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
  **Its own `state` field is blank (`""`, not missing) on roughly half
  its 8,990 entries** - those don't count as a state for a station even
  when the code otherwise matches; see source 3.

**3. Wikipedia station list - fallback source, for `state` only, where sources 1-2 leave it blank**

- **Publisher:** Wikipedia, ["List of railway stations in India"](https://en.wikipedia.org/wiki/List_of_railway_stations_in_India).
- **License:** [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
  (attribution + share-alike required for reuse - both satisfied by this
  section).
- **Retrieved:** 2026-09-02, via `action=raw` wikitext export of the
  live article (no fixed revision/version - a Wikipedia article changes
  over time; this project's own `dataset_version` metadata records the
  retrieval date, not an article revision).
- **Fields used:** station code, state - parsed from the article's
  wikitables (`scripts/transform_railway_data.dart`'s
  `_parseWikipediaStationStates`). Applied **only** to a station that
  still has `state: null` after source 2 - never to add a station, and
  never to overwrite a state either earlier source already supplied.
- **Coverage:** the article itself only documents ~2,820 of the roughly
  8,000+ stations in the primary dataset (Wikipedia's coverage of minor
  halts is inherently incomplete) - of the 4,283 stations still missing
  a state after source 2, this resolves 1,275. The remaining 3,008 stay
  `state: null`, honestly, rather than guessed. Other Wikipedia-adjacent
  candidates were evaluated and not used: `arunasank/indian-railways`
  and `IamYVJ/Indian_Railway_Stations_JSON` (both no declared license);
  `vstflugel/indian-railway-dataset` (MIT-licensed, but its "regional
  codes" are Indian Railways *zones*, e.g. "NR"/Northern - a zone spans
  several states, so mapping it to a single state would misrepresent
  the data, not fix it).

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
- **8,148 station codes from source 1; 7,639 (94%) matched a station in
  source 2 and got coordinates.** State coverage is lower: 3,865 (47%)
  got a state from source 2, a further 1,275 (16%) from source 3
  (Wikipedia), leaving **3,008 (37%) with `state: null`** - real, valid
  stations (present in the primary government-derived source), just
  without a state in any legitimate source found. `city` is `NULL` for
  every station - datameet's `address` field mixes area and state in
  one free-text string (e.g. `"Kishangarh Renwal, Rajasthan"`), too
  messy to split into a clean city value without guessing, so it was
  left unused rather than misrepresented as `city`.
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
| Stations with coordinates (source 2) | 7,639 (93.8%) |
| Stations with a state - from source 2 | 3,865 (47.4%) |
| Stations with a state - additionally from source 3 (Wikipedia) | 1,275 (15.7%) |
| Stations with a state - total | 5,140 (63.1%) |
| Stations with no state in any source (`state: null`) | 3,008 (36.9%) |
| Trains/services imported | 11,112 |
| Route stops imported | 186,102 |
| Route stops rejected (source `NA` values) | 5 |
| Running-day records | 0 (no source found - see limitations) |
| Train name conflicts found (first-seen kept) | 1 |
| `railway.db` size on disk | 18,141,184 bytes (~17.3 MB) |
| SQLite `integrity_check` | `ok` |

(APK-compressed size is reported per-release in the project's release
notes, since it now varies by which Android ABI a given APK targets -
see "Database versioning" below and the release history for current
figures.)

## Block 2A: dataset expansion research (2026-09-02)

A dedicated pass to try to move past the December 2017 snapshot above
toward broader, more current coverage, before Block 3 builds search on
top of it. **Conclusion: no legitimate, currently-obtainable dataset
was found that improves on what's already packaged.** No data changed;
`assets/database/railway.db` from Block 2 is unmodified, and no new
release was created (see "Why no v0.2.1" below).

### What "~26,000 trains a day" actually means

The Indian Railways Year Book 2023-24 (Ministry of Railways) reports
**13,198 passenger trains and 11,724 freight trains run daily on
average** (≈24,922, the figure press coverage rounds to "~25,000" or
"~26,000"). This is a count of **daily train operations/departures**,
not unique train numbers:

- A single train number that runs daily contributes multiple
  *operations* over a year but is still just **one** train identity in
  a database like this one.
- The figure bundles passenger **and** freight operations together;
  freight movements don't have a public passenger timetable the way
  express/passenger/suburban services do, and are out of scope for a
  passenger-facing app regardless.
- Neither this project's dataset nor the sources investigated below
  provide enough information to compute a true "unique train numbers"
  figure that Indian Railways itself publishes as such - the Year Book
  reports *operations*, not a deduplicated identity count. This
  project's own **11,112 unique train numbers** (see Coverage report
  above) is the only figure this codebase can make a factual claim
  about, and it should not be equated with, or extrapolated from, the
  ~25,000 operations figure.
- Because `running_days` has zero records (see above and below), this
  project cannot currently compute derived "weekly operations" or
  "daily operations" statistics of its own - doing so would require
  operating-day data this dataset does not have. Reporting such numbers
  without that data would be fabrication, so none are reported.

Source: [Indian Railways Year Book 2023-24](https://www.scribd.com/document/900979178/IR-Year-Book-2023-24-English) figures as summarized in press coverage of the Ministry of Railways' own release; cross-referenced against the [PIB Year End Review 2024](https://www.pib.gov.in/PressReleasePage.aspx?PRID=2088668&reg=48&lang=2).

### Sources investigated and why each was not used

| Source | Vintage | License | Disposition |
|---|---|---|---|
| data.gov.in (official catalog, direct) | would be current | GODL-India | **Blocked** - the catalog page returns HTTP 403 to automated fetches and requires interactive/registered browser access. This is the same block hit in the original Block 2 research pass. |
| github.com/arunasank/indian-railways | Pushed 2016; no commits since | **None declared** (no LICENSE file - all-rights-reserved by GitHub default) | Rejected: no license means no legal basis to redistribute/bundle its data, regardless of content. Also not meaningfully more current than what's already used. |
| github.com/ankitaanand28/DA323_IndianRailwayTrainDelayDatasets | 2023-2024 | **None declared** | Rejected: no license; also narrow scope (only express trains between Guwahati and 4 metro cities - would not expand national coverage) and built by scraping live enquiry systems as a student project, inheriting that scrape's own terms-of-use uncertainty. |
| Kaggle ("Indian Express Train Dataset" and others) | Listed as updated 2025 | Varies, often unclear | Rejected: Kaggle dataset files require an authenticated session or Kaggle API token to download in bulk; this project has neither, and using someone's personal Kaggle credentials would violate the "no third-party credentials" rule. The page itself could not even be read without a login-gated SPA shell. |
| Indian Railways GTFS feed | N/A | N/A | **Does not exist.** Confirmed via the DataMeet/GTFS community itself: "there are no official GTFS feeds by any [Indian transit] agencies," Indian Railways included. |
| CRIS (Centre for Railway Information Systems) open API / Project Pravah | N/A | N/A | **Not public self-service data.** CRIS's API platform (NTES/PRS/FOIS/EPS, 140+ APIs) serves authorized B2B/B2C integration partners under commercial/legal agreements - this is the domain the product's own later "RailRadar" block is designed to integrate with through a proper backend and credentials, not something to access here without authorization. |
| National Train Enquiry System (enquiry.indianrail.gov.in) | live | N/A | **Out of scope by design** - this is a live/interactive lookup system, not a bulk dataset. Scraping it per-train (for ~11,000+ trains) to build a static database would both misuse a live system at scale and produce "live status," which is explicitly reserved for the RailRadar block, not this one. |
| web.archive.org snapshot of data.gov.in | historical | N/A | Inaccessible with the tools available in this environment. |

No dataset providing weekly/daily running-day calendars was found from
any source, bulk-downloadable or otherwise legitimate to use - this
remains the dataset's most significant known gap.

### Fresh validation pass against the existing production database

Re-ran full integrity/quality checks against the already-shipped
`assets/database/railway.db` (unchanged from v0.2.0) as part of this
research pass:

| Check | Result |
|---|---|
| Duplicate `stations.normalized_code` | 0 |
| Duplicate `trains.normalized_number` | 0 |
| Orphan `route_stops.train_id` | 0 |
| Orphan `route_stops.station_id` | 0 |
| Duplicate `(train_id, stop_sequence)` | 0 |
| Trains with zero route stops | 0 |
| `PRAGMA integrity_check` | `ok` |
| `PRAGMA foreign_key_check` violations | 0 |

Two newly-documented, pre-existing **source** data gaps (not import
bugs - confirmed by inspecting the source CSV directly):

- **Train 11111** ("GWL-BLP SUSH") has only one recorded stop in the
  source timetable (its origin, Gwalior) - the rest of its route was
  never present in the December 2017 export.
- **Train 11112** ("BLP-GWL", the return working) is missing its
  `stop_sequence = 1` row in the source - its recorded route starts at
  sequence 2.

Both are honestly represented as-is (a 1-stop route; a route starting
at sequence 2) rather than patched with an invented stop - 2 trains out
of 11,112 (0.02%).

### Why no v0.2.1

Per the definition of this task: "a smaller dataset with verified
provenance is better than a larger fabricated dataset," and a new
release should only ship "if this dataset expansion is a meaningful
production-data upgrade." No new stations, trains, routes, or
running-day data were legitimately obtainable in this pass - the
database is byte-for-byte identical to v0.2.0. Shipping v0.2.1 would
create a release with no actual content difference, which would itself
be misleading. This document is updated (this section, plus the
research citations above) but the app version, database, and release
remain v0.2.0 until a genuine new source is found.

**Update (Block 3):** this conclusion held for trains, routes and
running-days, but was revisited for `state` specifically - Wikipedia's
"List of railway stations in India" (source 3 above) was found and
integrated as a fallback for stations datameet leaves without a state,
resolving 1,275 of the 4,283 that had none. This is a real, if partial,
improvement over the original Block 2 release; it shipped as part of
the v0.3.0 release rather than a separate dataset-only release, since
it landed in the same working session as Block 3's features. See the
updated "Sources" and "Coverage report" above for current numbers.

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
  --source "Train_details_22122017.csv (data.gov.in via github.com/itzmeanjan/indian-railway mirror) + stations.json (github.com/datameet/railways, CC0) + Wikipedia List of railway stations in India (CC BY-SA 4.0, state fallback only)" \
  --source-version "2017-12-22 timetable snapshot; datameet + Wikipedia state data retrieved 2026-09-02"
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

## Block 4: station-state enrichment (2026-09-02)

Block 3 left **3,008 of 8,148 stations (36.9%)** with `state: null` -
real stations, just without a state in any of the three sources used so
far (datameet, Wikipedia). Block 4's mandate: systematically resolve as
many as can be *legitimately verified*, never guessed, and record the
baseline/result/provenance for every station touched.

### Baseline

Generated by querying the (pre-Block-4) production database for every
station with `state IS NULL OR state = ''`: **3,008 stations**, listed
by station ID, code, name and (absent) state/city. This exact figure
matches the Block 2/3 coverage report above.

### Source 4: geometric enrichment (point-in-polygon)

Manually researching ~3,000 individual stations one at a time - many of
them minor halts with no independent web presence at all - would either
take an infeasible number of individual lookups or (worse) tempt
inferring a state from a station's name/city the way A3 explicitly
forbids. Instead, Block 4 adds a fourth **bulk, source-backed, fully
deterministic** method, consistent with how sources 2-3 above were
already applied:

- **2,590 of the 3,008** missing-state stations already have a
  coordinate (latitude/longitude) from source 2 (datameet/railways,
  CC0) - the state was simply never populated in that source, only the
  location was.
- For each, this project determines which one of India's 36 official
  state/union-territory polygons contains that coordinate - a fixed
  geometric computation (ray-casting, holes subtracted), never a
  name/city guess.
- **Boundary polygons:** the
  [geoBoundaries "IND-ADM1"](https://www.geoboundaries.org/api/current/gbOpen/IND/ADM1/)
  release (William & Mary geoLab), **CC BY 2.5 India**. Its own
  metadata credits **DataMeet India community data + Election
  Commission of India** as the underlying source - the same DataMeet
  lineage this project's station coordinates already come from, plus
  India's election authority. `admUnitCount: 36` matches India's actual
  count of states + union territories.
- **Verification performed:** the identical computation was run against
  *both* the full-resolution and the simplified release of the same
  geoBoundaries dataset. All 2,590 resolvable stations got the
  identical state at both resolutions - a real corroboration step, not
  a single-pass trust of one file.
- The remaining **418 stations have no coordinate in any source this
  project has** and are therefore **left unresolved, honestly** -
  listed in `data/enrichment/unresolved_stations.csv` (station ID,
  code, name, city, state - all as currently stored, i.e. still blank).
  Accuracy over completeness, per A3.
- Reproduced by `scripts/enrich_station_states.dart`, which writes
  `data/enrichment/station_states.csv` - a station-code -> state table
  with **per-row provenance** (`source`, `source_url`, `retrieval_date`,
  `confidence`, `method` columns). `scripts/transform_railway_data.dart`
  reads this file as a fourth, strictly-fallback source: it only ever
  fills a station that still has no state after sources 1-3, and never
  overrides one. `data/enrichment/station_states.csv` and
  `data/enrichment/unresolved_stations.csv` are both committed - the
  actual enrichment deliverable and its honest complement.

### State-name canonicalization (data-quality fix, Block 4)

Auditing the state values already in the database (required by A6:
"verify all state values are legitimate state/UT names") surfaced
casing/naming drift in what sources 1-3 had already written: `"bihar"`,
`"Andhra pradesh"`, `"Orissa"` (the state's pre-2011 official name,
before it was renamed to Odisha by Act of Parliament), `"Delhi NCT"`,
`"Jammu & Kashmir"` vs `"Jammu and Kashmir"`, and one Wikipedia-parsing
artifact (`"| Tamil nadu"`, a stray leading table-cell pipe that had
slipped through `_parseWikipediaStationStates`). `scripts/state_names.dart`
defines the 36 canonical Indian state/UT names (matching geoBoundaries'
own `admUnitCount`) and a `canonicalizeStateName()` used uniformly by
every source in `transform_railway_data.dart`; an unrecognized value is
logged and dropped, never stored as-is and never guessed to the
nearest-looking name. No station's state was reassigned to a
*different* place - this only fixes spelling/casing/old-name drift on
values that already meant one specific, unambiguous state.

### CYI (Chhayapuri) - the explicitly-required verification

`CYI` / `CHHAYAPURI` had coordinates (22.388284, 73.179698 - near
Vadodara) from datameet but no state in any of sources 1-3. The
geometric method places that coordinate inside the **Gujarat** polygon,
confirmed identically at both geoBoundaries resolutions. Regression-
tested against the real bundled asset in
`test/data/database/station_state_enrichment_test.dart`, so a future
dataset rebuild that silently drops this cannot ship unnoticed.

### Result

| | Count |
|---|---|
| Missing states - BEFORE (Block 2/3 baseline) | 3,008 |
| Resolved by geometric enrichment (source 4) | 2,590 |
| Missing states - AFTER | 418 |
| Stations with a state - total (all 4 sources) | 7,730 / 8,148 (94.9%) |
| Distinct canonical state/UT values in the database | 30 |

Full validation performed after rebuilding `assets/database/railway.db`
with this enrichment (see `test/data/database/station_state_enrichment_test.dart`
and the release verification log for the exact commands run):

| Check | Result |
|---|---|
| Total stations (unchanged from Block 2/3) | 8,148 |
| Any station code reassigned/duplicated | 0 |
| Duplicate `stations.normalized_code` | 0 |
| Duplicate `trains.normalized_number` | 0 |
| Orphan `route_stops.train_id` / `.station_id` | 0 / 0 |
| Duplicate `(train_id, stop_sequence)` | 0 |
| `PRAGMA foreign_key_check` violations | 0 |
| `PRAGMA integrity_check` | `ok` |
| State values outside the 36 canonical names | 0 |

### Reproducing the enrichment

```bash
dart run scripts/acquire_railway_data.dart --output raw_data   # now also fetches geoBoundaries-IND-ADM1.geojson
dart run scripts/enrich_station_states.dart --input raw_data --output data/enrichment
dart run scripts/transform_railway_data.dart --input raw_data --output build_data
dart run bin/import_railway_data.dart \
  --stations build_data/stations.csv \
  --trains build_data/trains.csv \
  --route-stops build_data/route_stops.csv \
  --running-days build_data/running_days.csv \
  --output assets/database/railway.db \
  --source "Train_details_22122017.csv (data.gov.in via github.com/itzmeanjan/indian-railway mirror) + stations.json (github.com/datameet/railways, CC0) + Wikipedia List of railway stations in India (CC BY-SA 4.0, state fallback) + geoBoundaries IND-ADM1 point-in-polygon state enrichment (CC BY 2.5 India, Block 4)" \
  --source-version "2017-12-22 timetable snapshot; datameet + Wikipedia + geoBoundaries state data retrieved 2026-09-02"
```

`data/enrichment/*.csv` are committed (small, curated, with provenance)
even though `raw_data/`/`build_data/` are not - they are the actual
Block 4 enrichment deliverable, not a rebuildable-on-demand byproduct.

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
