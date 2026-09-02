import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, existsSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { RunningDaysCache } from '../src/lib/runningDaysCache.js';

function tempCachePath() {
  const dir = mkdtempSync(join(tmpdir(), 'running-days-cache-test-'));
  return join(dir, 'nested', 'cache.json');
}

test('a fresh cache (no file yet) returns null for anything', () => {
  const cache = new RunningDaysCache({ filePath: tempCachePath() });
  assert.equal(cache.get('12951'), null);
});

test('set then get round-trips within the same process', () => {
  const cache = new RunningDaysCache({ filePath: tempCachePath() });
  const entry = { status: 'confirmed', days: { monday: true }, fetchedAt: '2026-09-02T00:00:00Z' };
  cache.set('12951', entry);
  assert.deepEqual(cache.get('12951'), entry);
});

test('persists to disk (creating intermediate directories) and reloads in a new instance', () => {
  const filePath = tempCachePath();
  const first = new RunningDaysCache({ filePath });
  first.set('12951', { status: 'confirmed', days: { monday: true } });

  assert.ok(existsSync(filePath));
  const second = new RunningDaysCache({ filePath });
  assert.deepEqual(second.get('12951'), { status: 'confirmed', days: { monday: true } });
});

test('a corrupt cache file is treated as empty rather than crashing', () => {
  const filePath = tempCachePath();
  const cache = new RunningDaysCache({ filePath });
  cache.set('seed', { status: 'no_data' });
  // Corrupt the file directly.
  writeFileSync(filePath, 'not valid json{{{');
  const reloaded = new RunningDaysCache({ filePath });
  assert.equal(reloaded.get('seed'), null);
});
