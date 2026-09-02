import { Errors } from './httpError.js';

const trainNumberPattern = /^\d{1,6}$/;
const datePattern = /^(\d{4})-(\d{2})-(\d{2})$/;

/// Real Indian Railways train numbers are purely numeric (currently
/// 5 digits) - rejecting anything else here is what keeps "Do not send
/// arbitrary unvalidated strings to the backend" (Block 6 Part 11)
/// true at the one place that actually enforces it, regardless of what
/// a client sends.
export function validateTrainNumber(raw) {
  if (typeof raw !== 'string' || !trainNumberPattern.test(raw)) {
    throw Errors.invalidTrainNumber();
  }
  return raw;
}

/// `null` is a valid result (no date given - RailRadar itself defaults
/// to "today's journey date" in that case, per its own docs). Anything
/// present must be a real, syntactically exact YYYY-MM-DD calendar
/// date - not just "parseable by Date()", which silently rolls over an
/// invalid day/month (e.g. 2026-02-30) instead of rejecting it.
export function validateJourneyDate(raw) {
  if (raw === undefined || raw === null || raw === '') return null;
  if (typeof raw !== 'string') throw Errors.invalidDate();

  const match = datePattern.exec(raw);
  if (!match) throw Errors.invalidDate();

  const [, yearStr, monthStr, dayStr] = match;
  const year = Number(yearStr);
  const month = Number(monthStr);
  const day = Number(dayStr);
  const date = new Date(Date.UTC(year, month - 1, day));
  const roundTrips =
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day;
  if (!roundTrips) throw Errors.invalidDate();

  return raw;
}
