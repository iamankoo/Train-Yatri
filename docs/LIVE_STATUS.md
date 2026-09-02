# Live Status (Block 6)

Real-time train running status, sourced from [RailRadar](https://railradar.in)'s
Indian Railways API. Shipped in `train-yatri-v0.6.0.apk`.

## Architecture

```
Flutter app  --(HTTPS, no credential)-->  Train Yatri backend  --(HTTPS, Bearer key)-->  RailRadar API
```

The Flutter app never talks to RailRadar directly and never holds the
RailRadar API key. The key exists only in the backend's environment
(`backend/.env` locally, an environment variable on the deployed host)
and is read once, server-side, by `backend/src/config.js`. It is never
logged (`backend/src/lib/logger.js` explicitly documents this), never
returned in any response body, and never committed to git
(`backend/.gitignore`).

This is the same non-negotiable boundary that shaped every file in
`backend/` and every Flutter file under `lib/features/live_tracking/`,
`lib/data/repositories/backend_live_status_repository.dart`, and
`lib/domain/repositories/live_status_repository.dart`.

## Backend

Plain Node.js (`>=20.6.0`), zero npm dependencies - native `fetch`,
`AbortController`, `node:http`, `node:test`. See `backend/package.json`.

### Endpoint

```
GET /api/trains/:trainNumber/live?date=YYYY-MM-DD
```

- `trainNumber`: required, `^\d{1,6}$`.
- `date`: optional `YYYY-MM-DD`; omitted means "RailRadar's own default
  (today's journey)".

Response envelope:

```json
{ "success": true, "data": { "trainNumber": "12951", "status": "running", ... } }
{ "success": false, "error": { "code": "not_found", "message": "Live status isn't available for this train." } }
```

`data`'s shape is `normalizeLiveStatus.js`'s output (see below) - never
RailRadar's raw response shape.

### RailRadar contract this backend depends on

`GET https://api.railradar.in/v1/trains/{number}/live` (optional
`?date=YYYY-MM-DD`), `Authorization: Bearer rr_live_...`. Documented at
<https://railradar.in/docs/live-train-status>; captured, real response
shape verified directly against the live API during this block's
development (train 12951, 2026-09-02) - see "Real API verification"
below.

Fields this backend reads and normalizes
(`backend/src/lib/normalizeLiveStatus.js`): `trainNumber`, `trainName`,
`startDate` (-> `journeyDate`), `status`, `delayMinutes`,
`lastUpdatedAt`, `isLive`, `currentLocation`
(`stationCode`/`sequence`/`status`/`isHalt`/`isActualPosition`/`segmentProgress`/`speedKmh`/`bearingDegrees`),
`previousHalt`/`nextHalt` (`stationCode`/`stationName`/`sequence`/`distance`),
`route[]` (`sequence`/`station`/`arrival`/`departure`/`delayArrival`/`delayDeparture`/`status`/`distance`/`platform`),
`exceptions[]` (`type`/`message`). Nothing else is read; nothing not
present in this list is invented.

A missing/malformed field becomes `null` in the normalized output,
never a guessed value - `delayMinutes: null` means "RailRadar did not
report a delay", never "0 minutes late".

### Error mapping

| RailRadar/network condition | HTTP status | `error.code` | Message shown to the user |
|---|---|---|---|
| Train not found | 404 | `not_found` | "Live status isn't available for this train." |
| Rate limited | 429 | `rate_limited` | "Live status is temporarily unavailable. Please try again later." |
| RailRadar 5xx / unreachable | 503 | `provider_unavailable` | "Live status is temporarily unavailable." |
| Request timeout (8s) | 504 | `timeout` | "Live status is temporarily unavailable." |
| Malformed/unexpected response | 502 | `upstream_error` | "Live status is temporarily unavailable." |
| Server key missing/invalid | 503 | `provider_not_configured` | "Live status is temporarily unavailable." |
| Invalid train number/date | 400 | `invalid_train_number` / `invalid_date` | "Enter a valid train number." / "Enter a valid journey date." |

RailRadar's own raw error text is never forwarded - see
`backend/src/lib/httpError.js`.

### Caching and rate protection

- An in-memory `TtlCache` (`backend/src/lib/cache.js`) with ~25s TTL
  and in-flight request de-duplication - two requests for the same
  train/date arriving within the TTL, including simultaneously, share
  one RailRadar call.
- An 8s request timeout via `AbortController`.
- CORS `*` (the API is credential-free and safe for any origin).

## Environment configuration

`backend/.env` (gitignored; `backend/.env.example` documents the
shape):

```
RAILRADAR_API_KEY=rr_live_...
RAILRADAR_BASE_URL=https://api.railradar.in   # optional, this is the default
PORT=4000                                      # optional
NODE_ENV=development
RAILRADAR_REQUEST_TIMEOUT_MS=8000              # optional
LIVE_STATUS_CACHE_TTL_MS=25000                 # optional
```

Run locally: `node --env-file=.env src/server.js` from `backend/`.

Flutter reads only a safe base URL, never a credential -
`lib/core/config/env.dart`'s `Env.apiBaseUrl`, selected by
`--dart-define=ENVIRONMENT=development|staging|production` and
overridable with `--dart-define=API_BASE_URL=...`. Production must be
HTTPS; `Env.isProduction` gates this at the app level, and the release
Android manifest carries no cleartext-traffic override (only
`android/app/src/debug/AndroidManifest.xml` does, scoped to debug
builds only, for local emulator testing against `http://10.0.2.2:PORT`).

## Deployment (Render)

`render.yaml` (repository root - Render's Blueprint auto-detection
requires it there, even though the service itself lives in `backend/`
via `rootDir`) is a Render Blueprint: a public Web Service,
`rootDir: backend`, `healthCheckPath: /healthz`, and
`RAILRADAR_API_KEY` declared with `sync: false` (Render prompts for the
real value in its dashboard - the key is never in this repository).

**Deployed** at <https://train-yatri-backend.onrender.com> (Render
free tier, connected to this repository's `main` branch - a push to
`main` triggers a new build automatically). The real key was entered
once, directly into the Render dashboard's Environment tab, by the
account owner - it was never typed by Claude and never passed through
chat. `lib/core/config/env.dart`'s `Env.apiBaseUrl` defaults to this
URL for all three environments, since only one backend is actually
provisioned right now; separate staging/production Render services
would be a later infrastructure decision, not something to fake with
placeholder domains that don't resolve.

Free-tier caveat: the instance spins down after a period of
inactivity, which can delay the *first* request after a gap by 50+
seconds while it restarts - subsequent requests are normal speed. This
is a Render free-tier characteristic, not a bug in this backend.

## Flutter

- `lib/domain/entities/live_train_status.dart` - `LiveTrainStatus` and
  its nested entities, mirroring the backend's normalized JSON
  field-for-field. Every optional field is nullable; `null` is never
  upgraded to a default.
- `lib/domain/repositories/live_status_repository.dart` -
  `LiveStatusRepository` interface, `LiveStatusException` with a
  `LiveStatusFailureCategory` and a pre-written safe `message`.
- `lib/data/repositories/backend_live_status_repository.dart` - the
  only implementation; calls exclusively the Train Yatri backend via
  `dart:io HttpClient`.
- `lib/domain/services/live_status_presentation.dart` - the sealed
  `LiveStatusState` (`Loading` / `Available` / `Unavailable`) the UI
  switches over.
- `lib/features/live_tracking/live_status_controller.dart` -
  `LiveStatusController`, a `StateNotifier` that polls roughly every 30
  seconds (Block 6 Part 24) while it has at least one listener
  (`StateNotifierProvider.autoDispose` tears it down, cancelling the
  timer, the moment the Live Status screen is left) and while the app
  is foregrounded (`WidgetsBindingObserver`; polling pauses on
  background/inactive and an immediate refresh fires on resume). A
  poll failure with existing data on screen keeps showing that real
  data, marked stale, rather than blanking to an error.
- `lib/features/live_tracking/live_tab_screen.dart` - the Live tab's
  entry point: search a train number (client-side shape validation
  only, `^\d{1,6}$`) or reopen a recently-viewed one.
- `lib/features/live_tracking/live_status_screen.dart` - the display
  screen: status, delay (omitted when unknown, never defaulted to
  "on time"), current location, next halt, route with
  past/current/upcoming progress (`widgets/live_route_list.dart`,
  derived from RailRadar's own `sequence` numbers only), exception
  banners (`widgets/live_exception_banner.dart`), pull-to-refresh, and
  a stale-data notice.
- `lib/data/repositories/shared_prefs_recent_live_trains_repository.dart` -
  lightweight local storage (train number, name, viewed-at) for
  recently-viewed lookups, mirroring `RecentSearchesRepository`. No
  live status data, credentials, or PII is ever stored.
- Wired in from: the "Live" bottom-nav tab (`home_bottom_nav_bar.dart`),
  the "Live Status" Quick Action (`quick_actions_section.dart`), and a
  "Live Status" action on Train Details (`train_details_screen.dart`).

### What is deliberately never shown

Per Block 6's data-presentation rules (also see the "IMPORTANT
UI/DATA-DISCLOSURE CHANGE" standing rule from Block 5): the RailRadar
name, any RailRadar endpoint URL, the backend's own architecture, cache
behavior, or provenance details, and raw provider error text. Numeric
fields the provider did not report are omitted, never defaulted (no
"0 km/h" for unknown speed, no "on time" for an unknown delay, no
computed ETA from speed).

## Data boundary

SQLite (`assets/database/railway.db`) is the static schedule/structure
source (Blocks 2-5) - stations, trains, scheduled route stops. RailRadar
via this backend is the only source of live status. The two are never
merged into one record; Train Details (static) and Live Status (live)
remain two separate screens reached by an explicit action, exactly as
Block 6 requires.

## Real API verification

Performed during this block's development against the real RailRadar
API using a real credential (never committed, only ever in a local,
gitignored `backend/.env`):

- `GET /v1/trains/12951/live` - real response for the Mumbai Central -
  New Delhi Tejas Rajdhani Express confirmed the normalized shape above
  end-to-end through the local backend.
- `GET /v1/trains/00001/live` (a well-formed but non-existent number) -
  confirmed the real 404 -> `not_found` -> safe-message mapping.
- Confirmed real rate-limit headers (`x-ratelimit-remaining-min`,
  `x-ratelimit-remaining-month`) are present on every response - see
  "Running-days backfill" below for why this matters beyond Live
  Status itself.
- Confirmed the ~25s cache measurably shortens a repeat request
  (~500ms -> ~3ms in a local trial).

## Testing

- `backend/test/*.test.js` (`node --test` from `backend/`) - HTTP-layer
  tests via a real `node:http` server and a fake RailRadar client
  (never the real provider in automated tests), covering the full
  status-code/error-code matrix, caching, and "no secret in any
  response" assertions.
- `test/data/repositories/backend_live_status_repository_test.dart` -
  a real local `HttpServer` standing in for the backend, proving the
  Flutter-side JSON parsing against real request/response shapes.
- `test/features/live_tracking/live_status_controller_test.dart` -
  the polling state machine (loading -> available, first-load failure,
  poll failure keeps stale data, periodic polling, `refreshNow`, never
  fabricating a null delay).
- `test/features/live_tracking/live_status_screen_test.dart` and
  `live_tab_screen_test.dart` - UI rendering for every state, the exact
  safe error messages, omission of null fields, and navigation.

## Known limitations

- Live Status requires network connectivity to the Train Yatri backend
  - it is not, and cannot be, an offline feature (unlike static
    schedule search).
- RailRadar's free-tier key this app runs on is rate-limited (10
  requests/minute, 1000/month) - see `docs/RUNNING_DAYS_BACKFILL.md`
  for how a second, unrelated feature was deliberately designed to
  never compete with Live Status for that budget.
- The backend runs on Render's free tier, which spins the instance
  down after inactivity - the first request after a gap can take 50+
  seconds while it restarts. The `LiveStatusUnavailable`/timeout UI
  states handle this gracefully (a clear message, not a crash or a
  hang), but there is currently no "warming" mechanism to avoid it.
