import { Errors } from './httpError.js';

// RailRadar's documented `GET /v1/trains/{number}` ("Train Schedule &
// Timetable") - the source for real weekly running-days data
// (`data.train.runDays`, e.g. `["mon","tue",...]`; see
// docs/RUNNING_DAYS_BACKFILL.md for the citation and a real captured
// response). Mirrors railradarClient.js's request/error-mapping shape
// deliberately, since both are thin wrappers around the same
// documented RailRadar contract style.
const DAY_KEYS = {
  mon: 'monday',
  tue: 'tuesday',
  wed: 'wednesday',
  thu: 'thursday',
  fri: 'friday',
  sat: 'saturday',
  sun: 'sunday',
};

/// `quotaTracker`, when given, has its `recordResponseHeaders` called
/// with every real response's headers - this is how
/// `RailRadarQuotaTracker` learns RailRadar's authoritative remaining
/// quota (see lib/railradarQuota.js). Optional purely so tests can
/// omit it.
export function createRailRadarScheduleClient({
  baseUrl,
  apiKey,
  timeoutMs,
  fetchImpl = globalThis.fetch,
  quotaTracker = null,
}) {
  return {
    /// Resolves to a `{monday, ..., sunday}` boolean map when RailRadar
    /// reports at least one real running day, or `null` when the
    /// response was well-formed but simply had no running-days data
    /// for this train (not an error - callers store this as
    /// "no_data", never as "confirmed: false for every day").
    async getRunDays(trainNumber) {
      const url = new URL(`/v1/trains/${trainNumber}`, baseUrl);

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);

      let response;
      try {
        response = await fetchImpl(url, {
          method: 'GET',
          headers: {
            Authorization: `Bearer ${apiKey}`,
            Accept: 'application/json',
          },
          signal: controller.signal,
        });
      } catch (error) {
        if (error?.name === 'AbortError') throw Errors.timeout();
        throw Errors.providerUnavailable();
      } finally {
        clearTimeout(timer);
      }

      quotaTracker?.recordResponseHeaders(response.headers);

      if (response.status === 404) throw Errors.notFound();
      if (response.status === 429) throw Errors.rateLimited();
      if (response.status === 401) throw Errors.notConfigured();
      if (response.status >= 500) throw Errors.providerUnavailable();
      if (!response.ok) throw Errors.upstreamError();

      let body;
      try {
        body = await response.json();
      } catch {
        throw Errors.upstreamError();
      }

      if (!body || body.success !== true || !body.data) {
        throw Errors.upstreamError();
      }

      const runDays = body.data.train?.runDays;
      if (!Array.isArray(runDays)) return null;

      const days = {
        monday: false,
        tuesday: false,
        wednesday: false,
        thursday: false,
        friday: false,
        saturday: false,
        sunday: false,
      };
      let anyKnownDay = false;
      for (const raw of runDays) {
        const key = DAY_KEYS[String(raw).toLowerCase()];
        if (key) {
          days[key] = true;
          anyKnownDay = true;
        }
      }
      return anyKnownDay ? days : null;
    },
  };
}
