# Running-Days Backfill

Search Results (`SearchResultsScreen`) shows a "Running on `<date>`"
section above the full "All Direct Trains" list, for direct trains
RailRadar has confirmed actually operate on the searched date's weekday.
This document explains where that data comes from and why it works the
way it does - it is a mid-session addition, not part of the original
Block 5 or Block 6 specifications, requested directly during Block 6
development.

## Why this needed a real data source

`assets/database/railway.db`'s `running_days` table (schema present
since Block 2) is **empty** - the December 2017 timetable source this
project uses never included weekly operating-calendar data, and
`docs/RAILWAY_DATABASE.md`'s "Sources investigated and why each was not
used" section documents an exhaustive, unsuccessful search for a
legitimate bulk source of one. Splitting search results by "runs on
this day" without real data would mean either fabricating it or the
"running" group always being empty - both violate this project's
standing "never fabricate/never claim a train is running" rule
(established in Block 5, reaffirmed for Block 6).

RailRadar's own `GET /v1/trains/{number}` ("Train Schedule &
Timetable") endpoint - the same provider Block 6 uses for live status -
documents a real `runDays` field
(`https://railradar.in/docs/get-train-details`; verified directly
against the live API: `train.runDays` is an array of lowercase
3-letter day abbreviations, e.g. `["mon","tue","wed","thu","fri","sat","sun"]`).
This is the source used here.

## Why this is progressive, not a bulk backfill

The RailRadar key this app runs on is rate-limited: **10 requests/minute,
1000/month** (both discovered from the real
`x-ratelimit-remaining-min`/`x-ratelimit-remaining-month` response
headers, not assumed). Backfilling all 11,112 trains in the database
would need 11,112 calls - over 11x the entire monthly quota, and it
would leave nothing for Live Status (this key's actual purpose) for the
rest of the month. A full bulk backfill was deliberately rejected for
this reason.

Instead, a train's running days are looked up **only when it actually
appears in a real search result**, and the answer is cached forever
once known (a real answer doesn't go stale in a way that's worth
re-spending quota to refresh). Coverage grows organically with real
usage instead of one large up-front spend.

## Architecture

```
SearchResultsScreen --(batch: GET /api/trains/running-days?numbers=...)--> Train Yatri backend --(GET /v1/trains/{number})--> RailRadar
```

### Backend

- `backend/src/lib/railradarScheduleClient.js` - calls RailRadar's
  schedule endpoint, extracts and maps `runDays` to a
  `{monday, ..., sunday}` boolean map. Returns `null` (not an error)
  when RailRadar has no running-days data for a train.
- `backend/src/lib/runningDaysCache.js` - a plain JSON file
  (`backend/data/running_days_cache.json`, gitignored - runtime data,
  not source), keyed by train number, storing `confirmed` (with the
  day map) or `no_data` answers. Loaded on startup, written on every
  new answer. Best-effort: a write failure degrades to "re-learned
  after the next restart", never a crash.
- `backend/src/lib/railradarQuota.js` - `RailRadarQuotaTracker`, shared
  between the live-status and schedule clients. Grounded entirely in
  RailRadar's own real, authoritative `x-ratelimit-remaining-*`
  response headers - never a locally-guessed counter that could drift
  after a restart. `canAffordBackfillCall()` returns `true` only when
  there is real headroom to spare *above* a reserved buffer for Live
  Status (default: >3 requests/minute and >100 requests/month of
  margin). Before anything has been observed this process lifetime, it
  conservatively refuses - a running-days lookup can always retry on a
  later search, so waiting for a known-safe reading first costs
  nothing.
- `backend/src/routes/runningDays.js` -
  `GET /api/trains/running-days?numbers=12951,12952,...`. For each
  requested number: a cache hit returns instantly (no RailRadar call);
  otherwise, if quota allows and this batch hasn't already spent its
  cap (3 fresh calls per incoming request, regardless of quota - a
  single search screen must never itself consume a large slice of the
  shared per-minute budget), a real call is made and cached; otherwise
  the number comes back `"pending"` - never an error, and functionally
  identical to "unknown" for display purposes.

**Live Status priority**: the live-status route never consults the
quota tracker at all - it always attempts its call and lets a real 429
map to the existing safe "temporarily unavailable" message. Only the
running-days route checks `canAffordBackfillCall()` before spending
quota. This is what "Live Status always has priority" means concretely.

### Flutter

- `lib/domain/repositories/running_days_lookup_repository.dart` -
  `RunningDaysLookupRepository`, `RunningDaysAnswer` with a
  `RunningDaysLookupStatus` (`confirmed` / `noData` / `pending`) and
  `operatesOnWeekday(int weekday)`.
- `lib/data/repositories/backend_running_days_lookup_repository.dart` -
  calls the backend batch endpoint. Deliberately never throws: any
  failure (offline, timeout, malformed response) resolves to an empty
  map, meaning "nothing learned this time" - this is a purely additive
  enrichment to Journey Search and must never break, slow, or error
  the underlying offline search.
- `lib/features/search/search_results_screen.dart` - after the
  (synchronous, offline, unchanged) direct-service search completes, a
  background call asks the backend about the shown trains' numbers. If
  and when it resolves with at least one confirmed, running-that-weekday
  answer, the UI adds a "Running on `<date>`" section above the
  existing, complete "All Direct Trains" list - the confirmed trains
  appear in both; nothing is ever removed from the full list.

## What this does not change

- Journey Search remains fully usable offline - this enrichment is
  strictly additive and best-effort.
- The static `running_days` SQLite table and its `RunningDays` /
  `DataConfidence` domain entities (Block 2) are untouched; this is a
  separate, backend-mediated data path with its own types.
- 1-Change (connecting) results are not affected - splitting a
  two-leg connection by "running that day" would require both legs
  independently confirmed, which was out of scope for this addition.

## Testing

- `backend/test/railradarQuota.test.js`,
  `backend/test/railradarScheduleClient.test.js`,
  `backend/test/runningDaysCache.test.js`,
  `backend/test/runningDays.route.test.js` - quota-affordability logic,
  real-shaped RailRadar parsing (never the real provider), disk
  persistence, the batch endpoint's cache-hit/quota-skip/per-request-cap
  behavior, and "never leaks a key/Authorization header" checks.
- `test/data/repositories/backend_running_days_lookup_repository_test.dart` -
  a real local `HttpServer`, proving the Flutter-side parsing and its
  never-throws contract (non-200, malformed JSON, unreachable host all
  resolve to an empty map).
- `test/features/search/search_results_running_days_test.dart` - the
  section only appears once something is confirmed, a train confirmed
  *not* running that weekday stays in the full list without a section,
  and the full list is always shown regardless.

## Real API verification

`GET /v1/trains/12951` and `/v1/trains/22691` were called for real
during this feature's development (after seeding the quota tracker with
a real live-status call's headers) and returned real `runDays` data,
which was then served from `backend/data/running_days_cache.json` on
a repeat request - confirming the cache-hit path never re-spends quota.
