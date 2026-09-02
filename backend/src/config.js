// All server configuration in one place - nothing here is a secret
// except RAILRADAR_API_KEY, which is never logged, never defaulted,
// and never read anywhere else in this codebase. See
// docs/LIVE_STATUS.md "Security" for the full audit checklist this
// file exists to satisfy.

const nodeEnv = process.env.NODE_ENV ?? 'development';

function intFromEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export const config = {
  nodeEnv,
  isProduction: nodeEnv === 'production',
  port: intFromEnv('PORT', 4000),

  railradar: {
    baseUrl: process.env.RAILRADAR_BASE_URL ?? 'https://api.railradar.in',
    // Intentionally NOT defaulted - a missing key must be an explicit,
    // detectable "not configured" state (handled in routes/liveStatus.js),
    // never silently falling back to some placeholder value.
    apiKey: process.env.RAILRADAR_API_KEY ?? null,
    requestTimeoutMs: intFromEnv('RAILRADAR_REQUEST_TIMEOUT_MS', 8000),
  },

  liveStatus: {
    // Block 6, Part 14: "approximately 25 seconds TTL".
    cacheTtlMs: intFromEnv('LIVE_STATUS_CACHE_TTL_MS', 25000),
  },

  runningDays: {
    // Where the progressively-learned running-days cache is persisted
    // (see lib/runningDaysCache.js). Deliberately outside `src/` and
    // gitignored - it is runtime-accumulated data, not source.
    cacheFilePath:
      process.env.RUNNING_DAYS_CACHE_FILE ?? 'data/running_days_cache.json',
  },
};

export function isRailRadarConfigured() {
  return typeof config.railradar.apiKey === 'string' && config.railradar.apiKey.length > 0;
}
