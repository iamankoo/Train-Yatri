import test from 'node:test';
import assert from 'node:assert/strict';

import { normalizeLiveStatus } from '../src/lib/normalizeLiveStatus.js';

// Shaped to match RailRadar's own documented `data` object exactly
// (see docs/LIVE_STATUS.md's citation) - a fabricated example built
// from the real schema, not a guess at field names.
function fullRawResponse(overrides = {}) {
  return {
    trainNumber: '12951',
    trainName: 'MUMBAI RAJDHANI',
    startDate: '2026-09-02',
    lastUpdatedAt: '2026-09-02T10:15:00Z',
    status: 'running',
    delayMinutes: 12,
    isLive: true,
    currentLocation: {
      stationCode: 'BRC',
      sequence: 4,
      status: 'departed',
      isHalt: false,
      isActualPosition: true,
      segmentProgress: 0.35,
      speedKmh: 84,
      bearingDegrees: 271,
    },
    previousHalt: {
      stationCode: 'BRC',
      stationName: 'VADODARA JN',
      sequence: 4,
      distance: 391,
    },
    nextHalt: {
      stationCode: 'RTM',
      stationName: 'RATLAM JN',
      sequence: 5,
      distance: 652,
    },
    route: [
      {
        sequence: 1,
        stationCode: 'BCT',
        stationName: 'MUMBAI CENTRAL',
        isHalt: true,
        scheduledArrival: null,
        scheduledDeparture: '2026-09-02T17:00:00Z',
        actualArrival: null,
        actualDeparture: '2026-09-02T17:03:00Z',
        delayArrival: null,
        delayDeparture: 3,
        status: 'departed',
        distance: 0,
        platform: '1',
      },
      {
        sequence: 2,
        stationCode: 'MX',
        stationName: 'MUMBAI MAHALAKSHMI',
        isHalt: false,
        scheduledArrival: '2026-09-02T17:01:00Z',
        scheduledDeparture: '2026-09-02T17:01:00Z',
        actualArrival: null,
        actualDeparture: null,
        delayArrival: null,
        delayDeparture: null,
        status: 'upcoming',
        distance: 1.5,
        platform: null,
      },
    ],
    exceptions: [],
    ...overrides,
  };
}

test('normalizes a full, realistic response end to end', () => {
  const result = normalizeLiveStatus(fullRawResponse());

  assert.equal(result.trainNumber, '12951');
  assert.equal(result.trainName, 'MUMBAI RAJDHANI');
  assert.equal(result.journeyDate, '2026-09-02');
  assert.equal(result.status, 'running');
  assert.equal(result.delayMinutes, 12);
  assert.equal(result.isLive, true);
  assert.equal(result.currentLocation.stationCode, 'BRC');
  assert.equal(result.currentLocation.speedKmh, 84);
  assert.equal(result.currentLocation.segmentProgress, 0.35);
  assert.equal(result.nextHalt.stationName, 'RATLAM JN');
  assert.equal(result.route[0].platform, '1');
});

test('each route stop reports its real isHalt flag - a genuine stoppage is '
  + 'distinguishable from a pass-through point in the same route', () => {
  const result = normalizeLiveStatus(fullRawResponse());

  assert.equal(result.route[0].stationCode, 'BCT');
  assert.equal(result.route[0].isHalt, true);

  assert.equal(result.route[1].stationCode, 'MX');
  assert.equal(result.route[1].isHalt, false);
});

test('a route stop with isHalt missing/malformed normalizes to null, never '
  + 'guessed as true or false', () => {
  const result = normalizeLiveStatus(
    fullRawResponse({
      route: [
        {
          sequence: 1,
          stationCode: 'BCT',
          stationName: 'MUMBAI CENTRAL',
          isHalt: undefined,
          status: 'departed',
        },
      ],
    }),
  );
  assert.equal(result.route[0].isHalt, null);
});

test('returns null for a completely missing/malformed response, never throws', () => {
  assert.equal(normalizeLiveStatus(null), null);
  assert.equal(normalizeLiveStatus(undefined), null);
  assert.equal(normalizeLiveStatus('not an object'), null);
});

test('missing optional sections become null/empty, never fabricated', () => {
  const result = normalizeLiveStatus(
    fullRawResponse({
      currentLocation: undefined,
      previousHalt: undefined,
      nextHalt: undefined,
      route: undefined,
      exceptions: undefined,
    }),
  );
  assert.equal(result.currentLocation, null);
  assert.equal(result.previousHalt, null);
  assert.equal(result.nextHalt, null);
  assert.deepEqual(result.route, []);
  assert.deepEqual(result.exceptions, []);
});

test('an on-time train keeps delayMinutes: 0, distinct from unknown (null) - '
  + 'never collapses "no delay data" into a fabricated 0', () => {
  const onTime = normalizeLiveStatus(fullRawResponse({ delayMinutes: 0 }));
  assert.equal(onTime.delayMinutes, 0);

  const unknown = normalizeLiveStatus(fullRawResponse({ delayMinutes: undefined }));
  assert.equal(unknown.delayMinutes, null);
  assert.notEqual(unknown.delayMinutes, 0);
});

test('a halted-at-station currentLocation is distinguishable from a '
  + 'between-stations one via isHalt/segmentProgress', () => {
  const atStation = normalizeLiveStatus(
    fullRawResponse({
      currentLocation: {
        stationCode: 'RTM',
        sequence: 5,
        status: 'halted',
        isHalt: true,
        isActualPosition: true,
        segmentProgress: null,
        speedKmh: 0,
        bearingDegrees: null,
      },
    }),
  );
  assert.equal(atStation.currentLocation.isHalt, true);
  assert.equal(atStation.currentLocation.segmentProgress, null);

  const betweenStations = normalizeLiveStatus(fullRawResponse());
  assert.equal(betweenStations.currentLocation.isHalt, false);
  assert.equal(betweenStations.currentLocation.segmentProgress, 0.35);
});

test('speedKmh missing (not zero) stays null - "unknown is not zero" (Block 6 Part 20)', () => {
  const result = normalizeLiveStatus(
    fullRawResponse({
      currentLocation: {
        stationCode: 'RTM',
        sequence: 5,
        status: 'halted',
        isHalt: true,
        isActualPosition: true,
        segmentProgress: null,
        speedKmh: undefined,
        bearingDegrees: null,
      },
    }),
  );
  assert.equal(result.currentLocation.speedKmh, null);
});

test('a diverted train\'s exception simplifies to {type, message}, dropping '
  + 'the deep diverted-station internals', () => {
  const result = normalizeLiveStatus(
    fullRawResponse({
      exceptions: [
        {
          type: 'DIVERTED',
          message: 'Train diverted via Nagda Jn due to engineering works.',
          diverted: {
            from: { code: 'RTM', name: 'RATLAM JN', sequence: 5 },
            to: { code: 'NAD', name: 'NAGDA JN', sequence: 6 },
            divertedStations: [{ order: 1, sequence: 6, stationCode: 'NAD' }],
            skippedStations: [],
            hasReversal: false,
            geometry: 'huge-polyline-string',
            distanceKm: 40,
          },
        },
      ],
    }),
  );
  assert.equal(result.exceptions.length, 1);
  assert.equal(result.exceptions[0].type, 'diverted');
  assert.equal(
    result.exceptions[0].message,
    'Train diverted via Nagda Jn due to engineering works.',
  );
  assert.equal(result.exceptions[0].diverted, undefined);
});

test('cancelled and rescheduled exception types normalize correctly', () => {
  const cancelled = normalizeLiveStatus(
    fullRawResponse({
      status: 'cancelled',
      exceptions: [{ type: 'CANCELLED', message: 'Train cancelled today.' }],
    }),
  );
  assert.equal(cancelled.status, 'cancelled');
  assert.equal(cancelled.exceptions[0].type, 'cancelled');

  const rescheduled = normalizeLiveStatus(
    fullRawResponse({
      exceptions: [{ type: 'RESCHEDULED', message: 'Departure rescheduled by 2 hours.' }],
    }),
  );
  assert.equal(rescheduled.exceptions[0].type, 'rescheduled');
});

test('an unrecognized status string normalizes to "unknown" rather than '
  + 'being guessed into an existing category', () => {
  const result = normalizeLiveStatus(fullRawResponse({ status: 'some-new-provider-status' }));
  assert.equal(result.status, 'unknown');
});

test('isLive defaults to false (never assumed true) when absent', () => {
  const result = normalizeLiveStatus(fullRawResponse({ isLive: undefined }));
  assert.equal(result.isLive, false);
});
