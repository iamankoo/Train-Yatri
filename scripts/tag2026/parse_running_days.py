#!/usr/bin/env python3
"""Parses the real "Days of departure at originating station" vocabulary
used throughout TAG-2026 (verified forms: "Daily", "Except <days>", a
comma-separated day list, a single day) into the 7 boolean columns
`running_days.csv` expects, per docs/RAILWAY_DATABASE.md's schema.
Never guesses: unparseable/absent text yields confidence='unknown' with
every day False, exactly like a train this project has no data for."""
from __future__ import annotations

import re

DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

_DAY_TOKEN = {
    "m": "monday", "mo": "monday", "mon": "monday",
    "tu": "tuesday", "tue": "tuesday", "tues": "tuesday",
    "w": "wednesday", "wed": "wednesday",
    "th": "thursday", "thu": "thursday", "thur": "thursday", "thurs": "thursday",
    "f": "friday", "fr": "friday", "fri": "friday",
    "sa": "saturday", "sat": "saturday",
    "su": "sunday", "sun": "sunday",
}


def _tokens_to_days(text: str) -> set[str] | None:
    days: set[str] = set()
    for raw in re.split(r"[,\s]+", text.strip()):
        tok = raw.strip(".").lower()
        if not tok:
            continue
        if tok not in _DAY_TOKEN:
            return None
        days.add(_DAY_TOKEN[tok])
    return days or None


def parse_running_days_text(text: str) -> dict:
    """Returns {day: bool, "confidence": "confirmed"|"unknown"}."""
    result = {d: False for d in DAYS}
    if not text:
        result["confidence"] = "unknown"
        return result

    cleaned = text.strip()
    normalized = re.sub(r"\s+", " ", cleaned)

    if re.fullmatch(r"(?i)daily", normalized):
        for d in DAYS:
            result[d] = True
        result["confidence"] = "confirmed"
        return result

    m = re.fullmatch(r"(?i)except\s+(.*)", normalized)
    if m:
        excluded = _tokens_to_days(m.group(1))
        if excluded is not None:
            for d in DAYS:
                result[d] = d not in excluded
            result["confidence"] = "confirmed"
            return result

    days = _tokens_to_days(normalized)
    if days is not None:
        for d in days:
            result[d] = True
        result["confidence"] = "confirmed"
        return result

    result["confidence"] = "unknown"
    return result
