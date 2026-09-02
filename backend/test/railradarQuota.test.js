import test from 'node:test';
import assert from 'node:assert/strict';

import { RailRadarQuotaTracker } from '../src/lib/railradarQuota.js';

function headers(map) {
  return new Headers(map);
}

test('cannot afford a backfill call before anything has been observed', () => {
  const tracker = new RailRadarQuotaTracker();
  assert.equal(tracker.canAffordBackfillCall(), false);
});

test('affords a backfill call once real headroom is known', () => {
  const tracker = new RailRadarQuotaTracker({
    reserveMinuteForLive: 3,
    reserveMonthFloor: 100,
  });
  tracker.recordResponseHeaders(
    headers({ 'x-ratelimit-remaining-min': '9', 'x-ratelimit-remaining-month': '900' }),
  );
  assert.equal(tracker.canAffordBackfillCall(), true);
});

test('refuses once the per-minute reserve for Live Status is eaten into', () => {
  const tracker = new RailRadarQuotaTracker({
    reserveMinuteForLive: 3,
    reserveMonthFloor: 100,
  });
  tracker.recordResponseHeaders(
    headers({ 'x-ratelimit-remaining-min': '2', 'x-ratelimit-remaining-month': '900' }),
  );
  assert.equal(tracker.canAffordBackfillCall(), false);
});

test('refuses once the monthly floor is reached, even with per-minute headroom', () => {
  const tracker = new RailRadarQuotaTracker({
    reserveMinuteForLive: 3,
    reserveMonthFloor: 100,
  });
  tracker.recordResponseHeaders(
    headers({ 'x-ratelimit-remaining-min': '9', 'x-ratelimit-remaining-month': '50' }),
  );
  assert.equal(tracker.canAffordBackfillCall(), false);
});

test('always reflects the most recently observed real headers', () => {
  const tracker = new RailRadarQuotaTracker();
  tracker.recordResponseHeaders(
    headers({ 'x-ratelimit-remaining-min': '9', 'x-ratelimit-remaining-month': '900' }),
  );
  assert.equal(tracker.canAffordBackfillCall(), true);
  tracker.recordResponseHeaders(
    headers({ 'x-ratelimit-remaining-min': '1', 'x-ratelimit-remaining-month': '900' }),
  );
  assert.equal(tracker.canAffordBackfillCall(), false);
});

test('ignores headers that are missing the rate-limit fields', () => {
  const tracker = new RailRadarQuotaTracker();
  tracker.recordResponseHeaders(headers({ 'content-type': 'application/json' }));
  assert.equal(tracker.canAffordBackfillCall(), false);
});
