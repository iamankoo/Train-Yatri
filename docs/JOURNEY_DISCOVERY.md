# Journey discovery (Block 5)

Block 3 shipped direct-train search only. Block 5 adds bounded,
deterministic one-change connecting-journey discovery on top of it -
"these services/routes exist in the static timetable dataset," never a
claim that any specific train is running on a given date. See
`docs/RAILWAY_DATABASE.md` for the dataset itself; this document covers
the discovery algorithm.

## Architecture

```
SearchResultsScreen
      |
      v
JourneyDiscoveryService.discover(repository, fromStationId, toStationId)
      |
      +--> repository.findDirectServices(...)         (Block 3, unchanged)
      |
      +--> connecting-journey search (below)
      |
      v
JourneyDiscoveryResult { direct: [...], connecting: [...] }
```

`JourneyDiscoveryService` is pure Dart, depending only on
`RailwayRepository`'s abstract interface - directly unit-testable with
synthetic fixtures, and reused identically whether the repository is
backed by the real bundled database or an in-memory test one.

## Connecting-journey search, precisely

A bounded, three-step candidate search - never an unbounded graph
search over the ~186,000-row `route_stops` table:

1. **Candidate first legs**: `repository.findDepartures(fromStationId,
   limit: maxFirstLegCandidates)` - trains departing FROM, earliest
   first (one indexed query on `idx_route_stops_station`).
2. For each, `repository.getRouteWithStations(trainId)` (the same call
   Block 4's Train Details screen uses) gives that train's full route;
   every stop after FROM - excluding FROM and TO themselves - is a
   candidate interchange station. A shared budget
   (`maxInterchangeCandidates`, spent across *all* first-leg candidates
   combined, not per-train) caps how many interchanges are actually
   examined, so one first-leg train with an unusually long route can't
   dominate the search.
3. **Candidate second legs**: for each candidate interchange,
   `repository.findDirectServices(fromStationId: interchange, toStationId,
   limit: maxSecondLegCandidatesPerInterchange)` - reusing the exact
   query direct search already relies on.

With the defaults (see `JourneyDiscoveryConfig`), this is at most on
the order of 40 total indexed SQL queries per search - a real,
measured bound, not an estimate (see `test/data/database/query_plan_test.dart`'s
performance test and the real-database timing test in
`test/domain/services/journey_discovery_service_real_data_test.dart`).

## Validation (a candidate failing any of these is silently dropped)

- **Same-train rejection**: a candidate second leg on the same train as
  the first leg is discarded - that would just be a direct service,
  already covered above.
- **Chronological validity + the minimum connection buffer**: leg A and
  leg B are two *different* trains, each with its own `day_offset`
  numbering relative to its own origin - there is no shared calendar to
  compare them on directly. `JourneyDiscoveryService._buildConnection`
  computes leg A's arrival at the interchange in minutes *midnight-anchored
  to leg A's own origin's day_offset 0*, then treats leg B as departing
  at its recorded clock time on that same reference day; the connection
  is accepted only if that is at or after the arrival plus
  `minimumConnectionBufferMinutes` (default 30) - otherwise rejected
  outright, never silently pushed to "the next day", which would invent
  a day-of-week/operating-calendar fact this dataset does not have.
  (An earlier version of this calculation anchored to "minutes since
  boarding" instead of "midnight" - caught as a real bug, by hand,
  against a constructed overnight example, before it shipped; see the
  method's own comment for the worked-through arithmetic.)
- **Missing/invalid duration**: either leg's own duration missing or
  computing negative is rejected the same way `DirectService.journeyDuration`
  already rejects a bad single-train duration - never papered over with
  a guess.
- **Same-station search**: `discover()` short-circuits to an empty
  result when `fromStationId == toStationId`, matching the UI's own
  "From and To must be different" validation (`JourneySearchState`) -
  otherwise a "go out on one train, come back on a different one"
  combination could surface as a nonsensical self-connection.
- Exact duplicate `(trainA, interchange, trainB)` candidates are
  deduplicated.

`minimumConnectionBufferMinutes` (and every other bound above) is a
**journey-planning heuristic**, not a railway guarantee - the dataset
has no platform, walking-distance, or delay information, and Indian
Railways makes no such guarantee either. The UI presents a connection
as simply "a calculated connection," never as confirmed.

## Ranking

Deterministic, using only fields the dataset actually has - never a
subjective or AI-generated score:

1. Earliest arrival at TO.
2. Shortest total duration.
3. Shortest waiting time.
4. Fewest total stops.

"Arrival at TO" is measured relative to each candidate's own first-leg
departure from FROM (that stop's own `day_offset`/time, as recorded) -
the same "different trains' day_offsets are directly comparable for
*ordering* purposes" convention `findDirectServices`'s own `ORDER BY`
already uses for direct results (day_offset, departure_time), applied
consistently here.

Results are truncated to `maxConnectingResults` (default 10) after
ranking.

## UI

`SearchResultsScreen` renders two clearly distinct sections - never an
ambiguous mixed list:

- **Direct** - existing `TrainResultCard`s, unchanged from Block 3/4.
- **1 Change** - `ConnectingJourneyCard`: leg A, a "Change at
  &lt;station&gt;" row with the calculated wait, leg B, then the total
  duration. Each leg is independently tappable straight into the
  existing Block 4 Train Details screen for that leg's own train - this
  screen is reused, never duplicated.

State messaging (never claims more than what was actually found):

| Direct | Connecting | Shown |
|---|---|---|
| some | some | "Direct" section, then "1 Change" section |
| some | none | "Direct" section only |
| none | some | "No direct trains found", then "Connections available", then "1 Change" section |
| none | none | "No journey found" (whole-screen empty state) |

## Configuration

`lib/core/journey/journey_discovery_config.dart`'s `JourneyDiscoveryConfig`:

| Field | Default | Purpose |
|---|---|---|
| `maxFirstLegCandidates` | 8 | Departures from FROM considered |
| `maxInterchangeCandidates` | 25 | Interchange stations examined, total |
| `maxSecondLegCandidatesPerInterchange` | 5 | Second-leg trains considered per interchange |
| `maxConnectingResults` | 10 | Connecting journeys returned after ranking |
| `minimumConnectionBufferMinutes` | 30 | Minimum leg-A-arrival-to-leg-B-departure gap |

## Testing

- `test/domain/services/journey_discovery_service_test.dart`: synthetic
  fixtures, one isolated station set per scenario - valid connection,
  insufficient buffer, already-departed, a genuine overnight connection
  (the case that caught the anchoring bug above), same-train rejection,
  a second leg that doesn't reach TO, no-journey-found, ranking with
  two competing connections, and each configurable bound.
- `test/domain/services/journey_discovery_service_real_data_test.dart`:
  a real connection found by actually running the algorithm against
  the production database (never manufactured to fit it), multiple
  real direct services, the known real overnight route, invalid/same
  station IDs, and a timing bound.
- `test/data/database/query_plan_test.dart`: `findDepartures`'s index
  usage and a full connecting-search performance bound at a
  production-representative synthetic scale.
- `test/features/search/search_results_connecting_journeys_test.dart`:
  Direct/1 Change section separation, the "No direct trains found" ->
  "Connections available" messaging, leg-tap navigation into Train
  Details, semantic labels, and 320/360/390/412dp overflow.
- Every pre-existing Block 1-4 test (recent searches, station search,
  Train Details, the update system, station-state enrichment, offline
  database init) still passes unchanged - Block 5 only adds to the
  search results pipeline, it doesn't alter anything upstream of it.

## Known limitations

- Only one interchange (one change of train) is supported, by design
  (Block 5's explicit scope) - a journey genuinely requiring two
  changes is not discovered.
- The bounded candidate search is not exhaustive: a real connecting
  journey that exists in the dataset but falls outside
  `maxFirstLegCandidates`/`maxInterchangeCandidates` at the production
  defaults will not surface. The defaults are tuned for interactive
  search latency; `journey_discovery_service_real_data_test.dart`'s own
  real example needed a wider-than-default config to be found
  reliably, and documents why.
- As with direct search, no running-day/operating-calendar data exists
  for the vast majority of trains - a connecting journey found here is
  never a claim that either train operates on the searched date.
