import test from 'node:test';
import assert from 'node:assert/strict';

import { validateTrainNumber, validateJourneyDate } from '../src/lib/validate.js';
import { HttpError } from '../src/lib/httpError.js';

test('validateTrainNumber accepts a real 5-digit train number', () => {
  assert.equal(validateTrainNumber('12951'), '12951');
});

test('validateTrainNumber accepts a shorter numeric train number', () => {
  assert.equal(validateTrainNumber('101'), '101');
});

for (const bad of ['', 'abc', '12951; DROP TABLE', '12951/../../etc', '1234567', '12 951', null, undefined, 42]) {
  test(`validateTrainNumber rejects ${JSON.stringify(bad)}`, () => {
    assert.throws(() => validateTrainNumber(bad), HttpError);
  });
}

test('validateJourneyDate returns null for an absent date (RailRadar defaults to today)', () => {
  assert.equal(validateJourneyDate(undefined), null);
  assert.equal(validateJourneyDate(null), null);
  assert.equal(validateJourneyDate(''), null);
});

test('validateJourneyDate accepts a real calendar date', () => {
  assert.equal(validateJourneyDate('2026-09-02'), '2026-09-02');
});

test('validateJourneyDate rejects a syntactically-plausible but nonexistent date '
  + '(Date() would silently roll this over to March 2nd - must not)', () => {
  assert.throws(() => validateJourneyDate('2026-02-30'), HttpError);
});

for (const bad of ['not-a-date', '2026/09/02', '09-02-2026', '2026-9-2', "2026-09-02'; DROP TABLE"]) {
  test(`validateJourneyDate rejects ${JSON.stringify(bad)}`, () => {
    assert.throws(() => validateJourneyDate(bad), HttpError);
  });
}
