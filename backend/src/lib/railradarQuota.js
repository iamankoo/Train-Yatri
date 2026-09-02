// RailRadar's free-plan key this app runs on is capped at 10
// requests/minute and 1000/month, shared across every endpoint this
// backend calls (live status and train schedule alike) - RailRadar
// reports the real, authoritative remaining counts on every response
// via `x-ratelimit-remaining-min` / `x-ratelimit-remaining-month`
// headers. Live Status (the app's actual purpose for this key) must
// never be throttled by this module - it always calls RailRadar
// directly and lets a real 429 map to the existing safe "temporarily
// unavailable" message. This guard exists purely to protect that
// budget from a second, non-essential consumer: the progressive
// running-days backfill (see routes/runningDays.js), which must only
// spend quota when there is real headroom to spare.

export class RailRadarQuotaTracker {
  constructor({ reserveMinuteForLive = 3, reserveMonthFloor = 100 } = {}) {
    this.reserveMinuteForLive = reserveMinuteForLive;
    this.reserveMonthFloor = reserveMonthFloor;
    this.remainingMinute = null;
    this.remainingMonth = null;
  }

  /// Called after every real RailRadar response (live status or
  /// schedule) - keeps this tracker's view of the budget grounded in
  /// what RailRadar itself reports, rather than a locally-guessed
  /// count that could drift (e.g. after a backend restart).
  recordResponseHeaders(headers) {
    const minute = headers?.get?.('x-ratelimit-remaining-min');
    const month = headers?.get?.('x-ratelimit-remaining-month');
    if (minute !== null && minute !== undefined && minute !== '') {
      const parsed = Number(minute);
      if (Number.isFinite(parsed)) this.remainingMinute = parsed;
    }
    if (month !== null && month !== undefined && month !== '') {
      const parsed = Number(month);
      if (Number.isFinite(parsed)) this.remainingMonth = parsed;
    }
  }

  /// Whether a non-essential (running-days) RailRadar call may be made
  /// right now. Deliberately conservative: unknown budget (nothing
  /// observed yet this process lifetime) is treated as "cannot
  /// afford" - a running-days lookup can always retry on a later
  /// search, so there is no cost to waiting for a real, known-safe
  /// reading first, and it plainly can't ever undercut Live Status
  /// priority this way.
  canAffordBackfillCall() {
    if (this.remainingMinute === null || this.remainingMonth === null) {
      return false;
    }
    return (
      this.remainingMinute > this.reserveMinuteForLive &&
      this.remainingMonth > this.reserveMonthFloor
    );
  }
}
