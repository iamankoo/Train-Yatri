import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';

import { config, isRailRadarConfigured } from './config.js';
import { TtlCache } from './lib/cache.js';
import { createRailRadarClient } from './lib/railradarClient.js';
import { createRailRadarScheduleClient } from './lib/railradarScheduleClient.js';
import { RailRadarQuotaTracker } from './lib/railradarQuota.js';
import { RunningDaysCache } from './lib/runningDaysCache.js';
import { HttpError } from './lib/httpError.js';
import { logger } from './lib/logger.js';
import { createLiveStatusHandler } from './routes/liveStatus.js';
import { createRunningDaysHandler } from './routes/runningDays.js';

const LIVE_STATUS_PATH = /^\/api\/trains\/([^/]+)\/live\/?$/;
const RUNNING_DAYS_PATH = /^\/api\/trains\/running-days\/?$/;

function sendJson(response, status, body) {
  const payload = JSON.stringify(body);
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    // The API itself is a thin, credential-free read proxy - safe for
    // the Flutter app (or a local web build) to call from any origin;
    // nothing here is session/cookie-authenticated.
    'Access-Control-Allow-Origin': '*',
  });
  response.end(payload);
}

async function respondWithHandler(response, run) {
  try {
    const data = await run();
    sendJson(response, 200, { success: true, data });
  } catch (error) {
    if (error instanceof HttpError) {
      sendJson(response, error.status, {
        success: false,
        error: { code: error.code, message: error.safeMessage },
      });
      return;
    }
    // An unexpected (programmer) error - still never leaks anything
    // provider-specific, and is logged with its real message
    // server-side only.
    logger.error('unhandled_error', { message: error?.message });
    sendJson(response, 500, {
      success: false,
      error: {
        code: 'internal_error',
        message: 'Something went wrong. Please try again.',
      },
    });
  }
}

async function route(request, response, handleLiveStatus, handleRunningDays) {
  const url = new URL(request.url, `http://${request.headers.host ?? 'localhost'}`);

  if (request.method === 'OPTIONS') {
    response.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    response.end();
    return;
  }

  if (request.method === 'GET' && url.pathname === '/healthz') {
    sendJson(response, 200, { status: 'ok' });
    return;
  }

  if (request.method === 'GET' && RUNNING_DAYS_PATH.test(url.pathname)) {
    await respondWithHandler(response, () =>
      handleRunningDays(request, {}, url.searchParams),
    );
    return;
  }

  const liveStatusMatch = LIVE_STATUS_PATH.exec(url.pathname);
  if (request.method === 'GET' && liveStatusMatch) {
    await respondWithHandler(response, () =>
      handleLiveStatus(
        request,
        { trainNumber: decodeURIComponent(liveStatusMatch[1]) },
        url.searchParams,
      ),
    );
    return;
  }

  sendJson(response, 404, {
    success: false,
    error: { code: 'not_found', message: 'Not found.' },
  });
}

/// Every dependency here is overridable purely for tests
/// (test/liveStatus.route.test.js and test/runningDays.route.test.js
/// exercise the real HTTP layer - status codes, headers, JSON envelope
/// - against fakes, never the real RailRadar API). The real process
/// below never overrides any of them. [quotaTracker] is shared between
/// the live-status and schedule clients deliberately - it is the one
/// piece of state that must see every real RailRadar call, live status
/// included, to keep its picture of the remaining budget accurate.
export function createApp({
  quotaTracker = new RailRadarQuotaTracker(),
  railradarClient = createRailRadarClient({
    baseUrl: config.railradar.baseUrl,
    apiKey: config.railradar.apiKey,
    timeoutMs: config.railradar.requestTimeoutMs,
    quotaTracker,
  }),
  cache = new TtlCache({ ttlMs: config.liveStatus.cacheTtlMs }),
  isConfigured = isRailRadarConfigured,
  scheduleClient = createRailRadarScheduleClient({
    baseUrl: config.railradar.baseUrl,
    apiKey: config.railradar.apiKey,
    timeoutMs: config.railradar.requestTimeoutMs,
    quotaTracker,
  }),
  runningDaysCache = new RunningDaysCache({
    filePath: config.runningDays.cacheFilePath,
  }),
} = {}) {
  const handleLiveStatus = createLiveStatusHandler({
    railradarClient,
    cache,
    isConfigured,
  });

  const handleRunningDays = createRunningDaysHandler({
    scheduleClient,
    cache: runningDaysCache,
    quotaTracker,
    isConfigured,
  });

  return createServer((request, response) => {
    route(request, response, handleLiveStatus, handleRunningDays).catch(
      (error) => {
        logger.error('route_crash', { message: error?.message });
        if (!response.headersSent) {
          sendJson(response, 500, {
            success: false,
            error: {
              code: 'internal_error',
              message: 'Something went wrong.',
            },
          });
        }
      },
    );
  });
}

// A plain `file://${process.argv[1]}` string concatenation breaks on
// Windows, where argv[1] is backslash-separated
// (C:\...\server.js) while import.meta.url is a real, forward-slash
// file:// URL - the two would never match and the server would never
// start when run directly (`node src/server.js`) on that platform.
// pathToFileURL produces a correctly-encoded URL on every OS.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const server = createApp();
  server.listen(config.port, () => {
    logger.info('server.listening', {
      port: config.port,
      nodeEnv: config.nodeEnv,
      railradarConfigured: isRailRadarConfigured(),
    });
  });
}
