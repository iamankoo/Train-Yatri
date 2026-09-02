import test from 'node:test';
import assert from 'node:assert/strict';

import { createRailRadarScheduleClient } from '../src/lib/railradarScheduleClient.js';
import { HttpError } from '../src/lib/httpError.js';

function fakeFetchImpl({ status, body, headers = {} }) {
  return async () => ({
    status,
    ok: status >= 200 && status < 300,
    headers: new Headers(headers),
    json: async () => body,
  });
}

function client(fetchImpl, extra = {}) {
  return createRailRadarScheduleClient({
    baseUrl: 'https://api.railradar.in',
    apiKey: 'rr_live_test_key',
    timeoutMs: 8000,
    fetchImpl,
    ...extra,
  });
}

test('extracts and maps a real runDays array to a day-boolean map', async () => {
  const c = client(
    fakeFetchImpl({
      status: 200,
      body: { success: true, data: { train: { runDays: ['mon', 'wed', 'fri'] } } },
    }),
  );
  const days = await c.getRunDays('12951');
  assert.deepEqual(days, {
    monday: true,
    tuesday: false,
    wednesday: true,
    thursday: false,
    friday: true,
    saturday: false,
    sunday: false,
  });
});

test('returns null (not an error) when the response has no runDays field', async () => {
  const c = client(
    fakeFetchImpl({ status: 200, body: { success: true, data: { train: {} } } }),
  );
  const days = await c.getRunDays('12951');
  assert.equal(days, null);
});

test('returns null when runDays is present but empty', async () => {
  const c = client(
    fakeFetchImpl({
      status: 200,
      body: { success: true, data: { train: { runDays: [] } } },
    }),
  );
  const days = await c.getRunDays('12951');
  assert.equal(days, null);
});

test('a 404 (train not found in schedule data) throws HttpError not_found', async () => {
  const c = client(fakeFetchImpl({ status: 404, body: { success: false } }));
  await assert.rejects(
    () => c.getRunDays('99999'),
    (error) => error instanceof HttpError && error.code === 'not_found',
  );
});

test('a 429 throws HttpError rate_limited', async () => {
  const c = client(fakeFetchImpl({ status: 429, body: { success: false } }));
  await assert.rejects(
    () => c.getRunDays('12951'),
    (error) => error instanceof HttpError && error.code === 'rate_limited',
  );
});

test('forwards every response\'s headers to the quota tracker', async () => {
  const observed = [];
  const fakeTracker = { recordResponseHeaders: (headers) => observed.push(headers) };
  const c = client(
    fakeFetchImpl({
      status: 200,
      body: { success: true, data: { train: { runDays: ['mon'] } } },
      headers: { 'x-ratelimit-remaining-min': '7' },
    }),
    { quotaTracker: fakeTracker },
  );
  await c.getRunDays('12951');
  assert.equal(observed.length, 1);
  assert.equal(observed[0].get('x-ratelimit-remaining-min'), '7');
});

test('never sends the API key anywhere but the Authorization header', async () => {
  let capturedHeaders;
  const fetchImpl = async (_url, options) => {
    capturedHeaders = options.headers;
    return {
      status: 200,
      ok: true,
      headers: new Headers(),
      json: async () => ({ success: true, data: { train: { runDays: ['mon'] } } }),
    };
  };
  await client(fetchImpl).getRunDays('12951');
  assert.equal(capturedHeaders.Authorization, 'Bearer rr_live_test_key');
});
