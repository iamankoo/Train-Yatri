import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';

// The progressively-learned running-days answers this backend has
// spent real (scarce) RailRadar quota to obtain - shared across every
// user of the app, and kept forever once known (a real answer, once
// learned, never needs re-spending quota to re-confirm - see
// docs/RUNNING_DAYS_BACKFILL.md). Persisted to a plain JSON file
// rather than a database, matching this backend's zero-dependency
// design; the file lives outside version control (see .gitignore) and
// is best-effort only - a write failure (e.g. an ephemeral/read-only
// deploy filesystem) degrades to "answers are simply re-learned after
// the next restart", never a crash or a fabricated result.
export class RunningDaysCache {
  constructor({ filePath }) {
    this.filePath = filePath;
    this.entries = this._load();
  }

  _load() {
    try {
      if (!existsSync(this.filePath)) return {};
      const parsed = JSON.parse(readFileSync(this.filePath, 'utf8'));
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch {
      return {};
    }
  }

  get(trainNumber) {
    return this.entries[trainNumber] ?? null;
  }

  /// [entry] is `{ status: 'confirmed', days: {...} }` or
  /// `{ status: 'no_data' }`, plus `fetchedAt`.
  set(trainNumber, entry) {
    this.entries[trainNumber] = entry;
    this._persist();
  }

  _persist() {
    try {
      mkdirSync(dirname(this.filePath), { recursive: true });
      writeFileSync(this.filePath, JSON.stringify(this.entries), 'utf8');
    } catch {
      // Best-effort - see class doc comment.
    }
  }
}
