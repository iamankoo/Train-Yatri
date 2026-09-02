import test from 'node:test';
import assert from 'node:assert/strict';

import { TtlCache } from '../src/lib/cache.js';

test('a cache miss runs the loader and caches the result', async () => {
  let calls = 0;
  const cache = new TtlCache({ ttlMs: 25000 });
  const { value, cacheHit } = await cache.getOrLoad('12951:today', async () => {
    calls++;
    return { status: 'running' };
  });
  assert.equal(cacheHit, false);
  assert.deepEqual(value, { status: 'running' });
  assert.equal(calls, 1);
});

test('a subsequent call within the TTL is a cache hit and does not re-run the loader', async () => {
  let calls = 0;
  let now = 1_000_000;
  const cache = new TtlCache({ ttlMs: 25000, now: () => now });

  await cache.getOrLoad('12951:today', async () => {
    calls++;
    return calls;
  });
  now += 10_000; // still within the 25s TTL
  const second = await cache.getOrLoad('12951:today', async () => {
    calls++;
    return calls;
  });

  assert.equal(second.cacheHit, true);
  assert.equal(second.value, 1);
  assert.equal(calls, 1);
});

test('a call after the TTL expires re-runs the loader (cache expiration)', async () => {
  let calls = 0;
  let now = 1_000_000;
  const cache = new TtlCache({ ttlMs: 25000, now: () => now });

  await cache.getOrLoad('12951:today', async () => {
    calls++;
    return calls;
  });
  now += 25_001; // just past the TTL
  const second = await cache.getOrLoad('12951:today', async () => {
    calls++;
    return calls;
  });

  assert.equal(second.cacheHit, false);
  assert.equal(second.value, 2);
  assert.equal(calls, 2);
});

test('concurrent requests for the same key share one in-flight load '
  + '(duplicate request protection, Block 6 Part 4/16)', async () => {
  let calls = 0;
  const cache = new TtlCache({ ttlMs: 25000 });
  const loader = async () => {
    calls++;
    await new Promise((resolve) => setTimeout(resolve, 20));
    return calls;
  };

  const [a, b, c] = await Promise.all([
    cache.getOrLoad('12951:today', loader),
    cache.getOrLoad('12951:today', loader),
    cache.getOrLoad('12951:today', loader),
  ]);

  assert.equal(calls, 1, 'the loader should only actually run once');
  assert.equal(a.value, 1);
  assert.equal(b.value, 1);
  assert.equal(c.value, 1);
});

test('different keys never share a cache entry', async () => {
  const cache = new TtlCache({ ttlMs: 25000 });
  const a = await cache.getOrLoad('12951:2026-09-02', async () => 'A');
  const b = await cache.getOrLoad('12952:2026-09-02', async () => 'B');
  assert.equal(a.value, 'A');
  assert.equal(b.value, 'B');
});

test('a failed load is not cached - the next call retries', async () => {
  let calls = 0;
  const cache = new TtlCache({ ttlMs: 25000 });
  const loader = async () => {
    calls++;
    if (calls === 1) throw new Error('upstream down');
    return 'ok';
  };

  await assert.rejects(() => cache.getOrLoad('12951:today', loader));
  const second = await cache.getOrLoad('12951:today', loader);
  assert.equal(second.value, 'ok');
  assert.equal(calls, 2);
});
