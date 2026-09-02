// End-to-end HTTP-layer tests: a real node:http server (via createApp),
// a real fetch() against it, but a fake RailRadar client injected in -
// so this proves the actual response envelope/status codes/headers a
// Flutter client would see, without ever calling the real provider
// (Block 6 Part 37).

import test from 'node:test';
import assert from 'node:assert/strict';

import { createApp } from '../src/server.js';
import { TtlCache } from '../src/lib/cache.js';
import { Errors } from '../src/lib/httpError.js';

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

function fakeClient(behavior) {
  return { getLiveStatus: behavior };
}

test('GET /healthz responds ok without touching RailRadar at all', async () => {
  await withServer(
    { railradarClient: fakeClient(() => assert.fail('should not be called')) },
    async (base) => {
      const response = await fetch(`${base}/healthz`);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.status, 'ok');
    },
  );
});

test('a valid train number returns 200 with a normalized envelope', async () => {
  await withServer(
    {
      railradarClient: fakeClient(async (trainNumber) => ({
        trainNumber,
        trainName: 'MUMBAI RAJDHANI',
        startDate: '2026-09-02',
        status: 'running',
        delayMinutes: 5,
        lastUpdatedAt: '2026-09-02T10:00:00Z',
        isLive: true,
        route: [],
        exceptions: [],
      })),
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/12951/live`);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.success, true);
      assert.equal(body.data.trainNumber, '12951');
      assert.equal(body.data.status, 'running');
    },
  );
});

test('an invalid train number is rejected with 400 before ever reaching '
  + 'the RailRadar client', async () => {
  await withServer(
    {
      railradarClient: fakeClient(() => assert.fail('should not be called')),
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/not-a-number/live`);
      assert.equal(response.status, 400);
      const body = await response.json();
      assert.equal(body.success, false);
      assert.equal(body.error.code, 'invalid_train_number');
    },
  );
});

test('an unconfigured server (no API key) returns 503 without crashing', async () => {
  await withServer(
    {
      railradarClient: fakeClient(() => assert.fail('should not be called')),
      isConfigured: () => false,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/12951/live`);
      assert.equal(response.status, 503);
      const body = await response.json();
      assert.equal(body.error.code, 'provider_not_configured');
    },
  );
});

test('a provider 404 (no such train) surfaces as a safe 404 with no '
  + 'provider-specific text', async () => {
  await withServer(
    {
      railradarClient: fakeClient(async () => {
        throw Errors.notFound();
      }),
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/99999/live`);
      assert.equal(response.status, 404);
      const body = await response.json();
      assert.equal(body.error.message, "Live status isn't available for this train.");
      assert.ok(!JSON.stringify(body).toLowerCase().includes('railradar'));
    },
  );
});

test('a provider 429 surfaces as a safe 429', async () => {
  await withServer(
    {
      railradarClient: fakeClient(async () => {
        throw Errors.rateLimited();
      }),
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/12951/live`);
      assert.equal(response.status, 429);
    },
  );
});

test('the response never includes any key/Authorization-shaped field', async () => {
  await withServer(
    {
      railradarClient: fakeClient(async (trainNumber) => ({
        trainNumber,
        status: 'running',
      })),
      isConfigured: () => true,
    },
    async (base) => {
      const response = await fetch(`${base}/api/trains/12951/live`);
      const text = await response.text();
      assert.ok(!/authorization/i.test(text));
      assert.ok(!/rr_live_/i.test(text));
      assert.ok(!/api[_-]?key/i.test(text));
    },
  );
});

test('a second request for the same train within the cache TTL hits the '
  + 'cache - the fake client is only invoked once', async () => {
  let calls = 0;
  await withServer(
    {
      railradarClient: fakeClient(async (trainNumber) => {
        calls++;
        return { trainNumber, status: 'running' };
      }),
      cache: new TtlCache({ ttlMs: 25000 }),
      isConfigured: () => true,
    },
    async (base) => {
      await fetch(`${base}/api/trains/12951/live`);
      await fetch(`${base}/api/trains/12951/live`);
      assert.equal(calls, 1);
    },
  );
});
