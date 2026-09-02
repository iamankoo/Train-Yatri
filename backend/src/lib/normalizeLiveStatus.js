// RailRadar response -> Train Yatri's own LiveTrainStatus shape (Block
// 6 Part 6/7) - the one place this codebase is coupled to RailRadar's
// raw schema, so the provider can change without touching Flutter.
// Only fields RailRadar's own documented response actually contains
// are read here - nothing is invented, and a missing/malformed field
// becomes `null`, never a guessed value.

const KNOWN_STATUSES = new Set([
  'not_started',
  'running',
  'departed',
  'upcoming',
  'arrived',
  'completed',
  'cancelled',
]);

function normalizeStatus(raw) {
  if (typeof raw !== 'string' || raw.length === 0) return 'unknown';
  const normalized = raw.toLowerCase().replaceAll('-', '_').trim();
  return KNOWN_STATUSES.has(normalized) ? normalized : 'unknown';
}

function numberOrNull(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function stringOrNull(value) {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function boolOrNull(value) {
  return typeof value === 'boolean' ? value : null;
}

function normalizeHalt(raw) {
  if (!raw || typeof raw !== 'object') return null;
  return {
    stationCode: stringOrNull(raw.stationCode),
    stationName: stringOrNull(raw.stationName),
    sequence: numberOrNull(raw.sequence),
    distanceKm: numberOrNull(raw.distance),
  };
}

function normalizeCurrentLocation(raw) {
  if (!raw || typeof raw !== 'object') return null;
  return {
    stationCode: stringOrNull(raw.stationCode),
    sequence: numberOrNull(raw.sequence),
    status: stringOrNull(raw.status),
    isHalt: boolOrNull(raw.isHalt),
    isActualPosition: boolOrNull(raw.isActualPosition),
    segmentProgress: numberOrNull(raw.segmentProgress),
    speedKmh: numberOrNull(raw.speedKmh),
    bearingDegrees: numberOrNull(raw.bearingDegrees),
  };
}

function normalizeRouteStop(raw) {
  return {
    sequence: numberOrNull(raw.sequence),
    stationCode: stringOrNull(raw.stationCode),
    stationName: stringOrNull(raw.stationName),
    // Whether this route entry is a real, scheduled stoppage (the
    // train actually halts here) as opposed to a pass-through point
    // the route just travels via - a real field RailRadar's live
    // route array reports per stop (verified directly against the
    // live API), distinct from `currentLocation.isHalt` (which
    // describes the train's own moment-to-moment position, not this
    // stop's static role in the route).
    isHalt: boolOrNull(raw.isHalt),
    scheduledArrival: stringOrNull(raw.scheduledArrival),
    scheduledDeparture: stringOrNull(raw.scheduledDeparture),
    actualArrival: stringOrNull(raw.actualArrival),
    actualDeparture: stringOrNull(raw.actualDeparture),
    arrivalDelayMinutes: numberOrNull(raw.delayArrival),
    departureDelayMinutes: numberOrNull(raw.delayDeparture),
    status: stringOrNull(raw.status),
    distanceKm: numberOrNull(raw.distance),
    platform: stringOrNull(raw.platform),
  };
}

const KNOWN_EXCEPTION_TYPES = new Set(['diverted', 'cancelled', 'rescheduled']);

function normalizeException(raw) {
  const rawType =
    typeof raw?.type === 'string' ? raw.type.toLowerCase() : null;
  return {
    type: KNOWN_EXCEPTION_TYPES.has(rawType) ? rawType : 'unknown',
    // RailRadar's own `message` is already a short human-readable
    // operational notice (e.g. "Train diverted via X"), not internal
    // JSON - safe to surface, unlike the deep diverted-station/
    // skipped-station internals this deliberately drops (Block 6 Part
    // 27: "Do not expose raw provider exception JSON").
    message: stringOrNull(raw?.message),
  };
}

export function normalizeLiveStatus(raw) {
  if (!raw || typeof raw !== 'object') return null;

  const route = Array.isArray(raw.route) ? raw.route.map(normalizeRouteStop) : [];
  const exceptions = Array.isArray(raw.exceptions)
    ? raw.exceptions.map(normalizeException)
    : [];

  return {
    trainNumber: stringOrNull(raw.trainNumber),
    trainName: stringOrNull(raw.trainName),
    journeyDate: stringOrNull(raw.startDate),
    status: normalizeStatus(raw.status),
    delayMinutes: numberOrNull(raw.delayMinutes),
    lastUpdatedAt: stringOrNull(raw.lastUpdatedAt),
    isLive: boolOrNull(raw.isLive) ?? false,
    currentLocation: normalizeCurrentLocation(raw.currentLocation),
    previousHalt: normalizeHalt(raw.previousHalt),
    nextHalt: normalizeHalt(raw.nextHalt),
    route,
    exceptions,
  };
}
