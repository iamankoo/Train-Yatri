import { validateTrainNumber, validateJourneyDate } from '../lib/validate.js';
import { normalizeLiveStatus } from '../lib/normalizeLiveStatus.js';
import { Errors, HttpError } from '../lib/httpError.js';
import { logger } from '../lib/logger.js';

/// `GET /api/trains/:trainNumber/live?date=YYYY-MM-DD` - the one
/// endpoint the Flutter app is allowed to know about for live status
/// (Block 6 Part 3). Everything RailRadar-specific (the key, the raw
/// response shape, RailRadar's own error text) stops here.
export function createLiveStatusHandler({ railradarClient, cache, isConfigured }) {
  return async function handleLiveStatus(request, params, query) {
    const start = Date.now();
    const trainNumber = validateTrainNumber(params.trainNumber);
    const journeyDate = validateJourneyDate(query.get('date'));

    if (!isConfigured()) {
      logger.warn('live_status.not_configured', { trainNumber });
      throw Errors.notConfigured();
    }

    const cacheKey = `${trainNumber}:${journeyDate ?? 'today'}`;

    try {
      const { value: raw, cacheHit } = await cache.getOrLoad(cacheKey, () =>
        railradarClient.getLiveStatus(trainNumber, journeyDate),
      );
      const normalized = normalizeLiveStatus(raw);

      logger.info('live_status.ok', {
        trainNumber,
        journeyDate,
        cacheHit,
        status: normalized?.status,
        durationMs: Date.now() - start,
      });

      return normalized;
    } catch (error) {
      const httpError =
        error instanceof HttpError ? error : Errors.upstreamError();
      logger.warn('live_status.error', {
        trainNumber,
        journeyDate,
        code: httpError.code,
        httpStatus: httpError.status,
        durationMs: Date.now() - start,
      });
      throw httpError;
    }
  };
}
