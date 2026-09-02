import { validateTrainNumber } from '../lib/validate.js';
import { logger } from '../lib/logger.js';

/// Never spend more than this many *fresh* RailRadar calls answering
/// one incoming batch request, even when quota allows it - a single
/// search-results screen must not be able to burn a large slice of
/// the shared per-minute budget by itself; the rest of the batch comes
/// back as "pending" and can be learned on a later search.
const MAX_FRESH_CALLS_PER_REQUEST = 3;

const MAX_NUMBERS_PER_REQUEST = 30;

/// `GET /api/trains/running-days?numbers=12951,12952,...` - progressive,
/// best-effort weekly running-days lookup. Never blocks or fails the
/// caller: a number this backend doesn't yet know is simply reported
/// as `"pending"`, not an error, and the Flutter side treats that
/// exactly like "unknown" for display purposes (Journey Search stays
/// fully usable, with or without this data).
///
/// This endpoint deliberately never competes with Live Status for
/// RailRadar quota: see lib/railradarQuota.js -
/// `quotaTracker.canAffordBackfillCall()` is checked before every
/// fresh call, and only [MAX_FRESH_CALLS_PER_REQUEST] fresh calls are
/// made per incoming request regardless.
export function createRunningDaysHandler({
  scheduleClient,
  cache,
  quotaTracker,
  isConfigured,
}) {
  return async function handleRunningDays(request, params, query) {
    const start = Date.now();
    const raw = query.get('numbers') ?? '';
    const requested = [
      ...new Set(
        raw
          .split(',')
          .map((value) => value.trim())
          .filter((value) => value.length > 0),
      ),
    ].slice(0, MAX_NUMBERS_PER_REQUEST);

    const trainNumbers = requested.map(validateTrainNumber);

    const result = {};
    let freshCallsMade = 0;
    let cacheHits = 0;
    let skippedForQuota = 0;

    for (const trainNumber of trainNumbers) {
      const cached = cache.get(trainNumber);
      if (cached) {
        cacheHits++;
        result[trainNumber] = _toResponseEntry(cached);
        continue;
      }

      const canFetch =
        isConfigured() &&
        freshCallsMade < MAX_FRESH_CALLS_PER_REQUEST &&
        quotaTracker.canAffordBackfillCall();

      if (!canFetch) {
        skippedForQuota++;
        result[trainNumber] = { status: 'pending' };
        continue;
      }

      freshCallsMade++;
      try {
        const days = await scheduleClient.getRunDays(trainNumber);
        const entry = days
          ? { status: 'confirmed', days, fetchedAt: new Date().toISOString() }
          : { status: 'no_data', fetchedAt: new Date().toISOString() };
        cache.set(trainNumber, entry);
        result[trainNumber] = _toResponseEntry(entry);
      } catch {
        // A single train's schedule lookup failing (timeout, RailRadar
        // 5xx, this train not found in schedule data, etc.) must never
        // fail the whole batch or the caller's search results -
        // simply left as "pending" for a future search to retry.
        result[trainNumber] = { status: 'pending' };
      }
    }

    logger.info('running_days.batch', {
      requested: trainNumbers.length,
      cacheHits,
      freshCallsMade,
      skippedForQuota,
      durationMs: Date.now() - start,
    });

    return result;
  };
}

function _toResponseEntry(cached) {
  return cached.status === 'confirmed'
    ? { status: 'confirmed', days: cached.days }
    : { status: 'no_data' };
}
