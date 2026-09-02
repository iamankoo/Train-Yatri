import test from 'node:test';
import assert from 'node:assert/strict';

import { createRailRadarClient } from '../src/lib/railradarClient.js';
import { HttpError } from '../src/lib/httpError.js';

function fakeFetchImpl({ status, body, throwError }) {
  return async () => {
    if (throwError) throw throwError;
    return {
      status,
      ok: status >= 200 && status < 300,
      json: async () => body,
    };
  };
}

function client(fetchImpl) {
  return createRailRadarClient({
    baseUrl: 'https://api.railradar.in',
    apiKey: 'rr_live_test_key_never_asserted_against',
    timeoutMs: 8000,
    fetchImpl,
  });
}

test('a successful response returns the raw data payload', async () => {
  const data = { trainNumber: '12951', status: 'running' };
  const c = client(fakeFetchImpl({ status: 200, body: { success: true, data } }));
  const result = await c.getLiveStatus('12951', null);
  assert.deepEqual(result, data);
});

test('never sends the API key anywhere but the Authorization header', async () => {
  let capturedHeaders;
  const fetchImpl = async (_url, options) => {
    capturedHeaders = options.headers;
    return { status: 200, ok: true, json: async () => ({ success: true, data: {} }) };
  };
  await client(fetchImpl).getLiveStatus('12951', null);
  assert.equal(capturedHeaders.Authorization, 'Bearer rr_live_test_key_never_asserted_against');
});

test('passes the journey date as a query parameter when given', async () => {
  let capturedUrl;
  const fetchImpl = async (url) => {
    capturedUrl = url;
    return { status: 200, ok: true, json: async () => ({ success: true, data: {} }) };
  };
  await client(fetchImpl).getLiveStatus('12951', '2026-09-02');
  assert.equal(new URL(capturedUrl).searchParams.get('date'), '2026-09-02');
});

test('omits the date parameter entirely when none is given (RailRadar '
  + 'defaults to today itself)', async () => {
  let capturedUrl;
  const fetchImpl = async (url) => {
    capturedUrl = url;
    return { status: 200, ok: true, json: async () => ({ success: true, data: {} }) };
  };
  await client(fetchImpl).getLiveStatus('12951', null);
  assert.equal(new URL(capturedUrl).searchParams.has('date'), false);
});

const statusCases = [
  [400, 'upstream_error'],
  [401, 'provider_not_configured'],
  [404, 'not_found'],
  [429, 'rate_limited'],
  [503, 'provider_unavailable'],
];

for (const [status, expectedCode] of statusCases) {
  test(`HTTP ${status} maps to code "${expectedCode}"`, async () => {
    const c = client(
      fakeFetchImpl({ status, body: { success: false, error: { code: 'x', message: 'raw provider text' } } }),
    );
    await assert.rejects(
      () => c.getLiveStatus('12951', null),
      (error) => error instanceof HttpError && error.code === expectedCode,
    );
  });
}

test('never leaks the raw provider error message into the thrown error', async () => {
  const c = client(
    fakeFetchImpl({
      status: 404,
      body: { success: false, error: { code: 'TRAIN_NOT_FOUND', message: 'Train 12919 not found on journey date 2026-06-22' } },
    }),
  );
  try {
    await c.getLiveStatus('12919', '2026-06-22');
    assert.fail('expected a rejection');
  } catch (error) {
    assert.ok(!error.safeMessage.includes('12919'));
    assert.ok(!error.message.includes('RailRadar'));
  }
});

test('a malformed (non-JSON-parseable) response is treated as an upstream error', async () => {
  const c = client(async () => ({
    status: 200,
    ok: true,
    json: async () => {
      throw new SyntaxError('Unexpected token');
    },
  }));
  await assert.rejects(
    () => c.getLiveStatus('12951', null),
    (error) => error instanceof HttpError && error.code === 'upstream_error',
  );
});

test('a well-formed but success:false response is an upstream error too', async () => {
  const c = client(fakeFetchImpl({ status: 200, body: { success: false } }));
  await assert.rejects(
    () => c.getLiveStatus('12951', null),
    (error) => error instanceof HttpError && error.code === 'upstream_error',
  );
});

test('a network failure (fetch itself throws) maps to provider_unavailable', async () => {
  const c = client(
    fakeFetchImpl({ throwError: new TypeError('fetch failed: ECONNREFUSED') }),
  );
  await assert.rejects(
    () => c.getLiveStatus('12951', null),
    (error) => error instanceof HttpError && error.code === 'provider_unavailable',
  );
});

test('an aborted (timed-out) request maps to the timeout error code', async () => {
  const fetchImpl = async (_url, options) =>
    new Promise((_resolve, reject) => {
      options.signal.addEventListener('abort', () => {
        const abortError = new Error('The operation was aborted');
        abortError.name = 'AbortError';
        reject(abortError);
      });
    });
  const c = createRailRadarClient({
    baseUrl: 'https://api.railradar.in',
    apiKey: 'test',
    timeoutMs: 10,
    fetchImpl,
  });
  await assert.rejects(
    () => c.getLiveStatus('12951', null),
    (error) => error instanceof HttpError && error.code === 'timeout',
  );
});
