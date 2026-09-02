import { Errors } from './httpError.js';

/// The only file in this codebase allowed to hold the RailRadar API
/// key in memory, and the only file that ever sends it anywhere (in
/// the `Authorization` header of a request to RailRadar itself, never
/// logged - see lib/logger.js's own rule). Contract (endpoint, auth
/// scheme, query params, error codes) is RailRadar's own documented
/// `GET /v1/trains/{number}/live` - see docs/LIVE_STATUS.md for the
/// citation.
///
/// `fetchImpl` is injectable purely for tests (Block 6 Part 37: "DO
/// NOT call the real provider repeatedly in automated tests") - the
/// real server always uses the global `fetch` Node provides natively.
/// `quotaTracker`, when given, has its `recordResponseHeaders` called
/// with every real response's headers, so `RailRadarQuotaTracker`
/// stays grounded in RailRadar's own authoritative remaining-quota
/// counters regardless of which endpoint actually made the call (see
/// lib/railradarQuota.js). Optional purely so existing tests don't
/// need to supply one.
export function createRailRadarClient({
  baseUrl,
  apiKey,
  timeoutMs,
  fetchImpl = globalThis.fetch,
  quotaTracker = null,
}) {
  return {
    async getLiveStatus(trainNumber, journeyDate) {
      const url = new URL(`/v1/trains/${trainNumber}/live`, baseUrl);
      if (journeyDate) url.searchParams.set('date', journeyDate);

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
      if (response.status === 401) {
        // A misconfigured/expired server-side key - never the caller's
        // fault, and never a detail the caller should see the shape of.
        throw Errors.notConfigured();
      }
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

      return body.data;
    },
  };
}
