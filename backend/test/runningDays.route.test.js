// End-to-end HTTP-layer tests for GET /api/trains/running-days, with a
// fake schedule client and a real-but-in-memory-only cache/tracker -
// never the real RailRadar API (mirrors liveStatus.route.test.js).

import test from 'node:test';
import assert from 'node:assert/strict';

import { createApp } from '../src/server.js';
import { RunningDaysCache } from '../src/lib/runningDaysCache.js';
import { RailRadarQuotaTracker } from '../src/lib/railradarQuota.js';

async function withServer(options, run) {
  const server = createApp(options);
  await new Promise((resolve) => server.listen(0, resolve));
  const { port } = server.address();
  try {
    await run(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function noopCache() {
  return { get: () => null, set: () => {} };
}

function affordableTracker() {
  const tracker = new RailRadarQuotaTracker();
  tracker.recordResponseHeaders(
    new Headers({
      'x-ratelimit-remaining-min': '9',
      'x-ratelimit-remaining-month': '900',
    }),
  );
  return tracker;
}

test('with quota available, a fresh number is fetched and returned confirmed', async () => {
  await withServer(
    {
      scheduleClient: { getRunDays: async () => ({ monday: true }) },
      runningDaysCache: noopCache(),
      quotaTracker: affordableTracker(),
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/running-days?numbers=12951`);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.data['12951'].status, 'confirmed');
      assert.deepEqual(body.data['12951'].days, { monday: true });
    },
  );
});

test('a cache hit never calls the schedule client at all', async () => {
  const cache = new RunningDaysCache({ filePath: `${process.env.TEMP ?? '/tmp'}/rd-cache-${Date.now()}.json` });
  cache.set('12951', { status: 'confirmed', days: { monday: true } });
  await withServer(
    {
      scheduleClient: { getRunDays: async () => assert.fail('should not be called') },
      runningDaysCache: cache,
      quotaTracker: affordableTracker(),
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/running-days?numbers=12951`);
      const body = await response.json();
      assert.equal(body.data['12951'].status, 'confirmed');
    },
  );
});

test('when quota cannot afford it, an uncached number comes back pending without calling RailRadar', async () => {
  await withServer(
    {
      scheduleClient: { getRunDays: async () => assert.fail('should not be called') },
      runningDaysCache: noopCache(),
      quotaTracker: new RailRadarQuotaTracker(), // nothing observed yet -> cannot afford
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/running-days?numbers=12951`);
      const body = await response.json();
      assert.equal(body.data['12951'].status, 'pending');
    },
  );
});

test('an unconfigured server reports every requested number as pending, never an error', async () => {
  await withServer(
    {
      scheduleClient: { getRunDays: async () => assert.fail('should not be called') },
      runningDaysCache: noopCache(),
      quotaTracker: affordableTracker(),
      isConfigured: () => false,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/running-days?numbers=12951`);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.data['12951'].status, 'pending');
    },
  );
});

test('a per-train schedule lookup failure degrades to pending, not a batch-wide error', async () => {
  await withServer(
    {
      scheduleClient: { getRunDays: async () => { throw new Error('boom'); } },
      runningDaysCache: noopCache(),
      quotaTracker: affordableTracker(),
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/running-days?numbers=12951`);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.data['12951'].status, 'pending');
    },
  );
});

test('never spends more than 3 fresh calls answering a single batch request', async () => {
  let calls = 0;
  await withServer(
    {
      scheduleClient: {
        getRunDays: async () => {
          calls++;
          return { monday: true };
        },
      },
      runningDaysCache: noopCache(),
      quotaTracker: affordableTracker(),
      isConfigured: () => true,
    },
    async (base) => {
      const numbers = ['11111', '22222', '33333', '44444', '55555'];
      const response = await fetch(`${base}/api/trains/running-days?numbers=${numbers.join(',')}`);
      const body = await response.json();
      assert.equal(calls, 3);
      const statuses = numbers.map((n) => body.data[n].status);
      assert.equal(statuses.filter((s) => s === 'confirmed').length, 3);
      assert.equal(statuses.filter((s) => s === 'pending').length, 2);
    },
  );
});

test('an invalid train number in the batch is rejected with 400', async () => {
  await withServer(
    {
      scheduleClient: { getRunDays: async () => assert.fail('should not be called') },
      runningDaysCache: noopCache(),
      quotaTracker: affordableTracker(),
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/running-days?numbers=not-a-number`);
      assert.equal(response.status, 400);
    },
  );
});

test('the response never includes any key/Authorization-shaped field', async () => {
  await withServer(
    {
      scheduleClient: { getRunDays: async () => ({ monday: true }) },
      runningDaysCache: noopCache(),
      quotaTracker: affordableTracker(),
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/running-days?numbers=12951`);
      const text = await response.text();
      assert.ok(!/authorization/i.test(text));
      assert.ok(!/rr_live_/i.test(text));
      assert.ok(!/api[_-]?key/i.test(text));
    },
  );
});
