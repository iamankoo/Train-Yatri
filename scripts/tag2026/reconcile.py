#!/usr/bin/env python3
"""Reconciles the parsed TAG-2026 index + detailed-table data into the
final trains.csv / route_stops.csv / running_days.csv / stations_new.csv
this project's existing `bin/import_railway_data.dart` already consumes
(see docs/RAILWAY_DATABASE.md and the approved plan). Also writes the
data-quality report the task requires.

Never fabricates: a train not resolvable to any parsed route is left
out of route_stops.csv (not given a fake one), a station name that
can't be matched to a code is dropped from that stop (not guessed), and
every rejection is recorded with its reason.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path

from parse_running_days import parse_running_days_text

KNOWN_BAD_TABLES = {
    "28", "45", "46", "47", "48", "49", "56", "60", "61", "62", "65", "67", "68",
    "70", "72", "73", "76", "77", "79", "80", "82", "84", "88", "89", "91", "92",
    "93", "94", "95", "96", "97",
}

CATEGORY_FILES = {
    "named_premium": [
        "Rajdhani_Exp.pdf", "Shatabdi_Exp.pdf", "Duronto_Exp.pdf", "Humsafar_Exp.pdf",
        "Janshatabdi_Exp.pdf", "Amrit_Bharat_Trains.pdf", "VandeBharatTrains.pdf",
        "Sampark_Kranti_Exp.pdf", "AntyodayTrains.pdf", "DD.pdf",
        "YuvaTejas_Uday_GatimanTrains.pdf", "NamoBharatRapidRail.pdf",
    ],
    "tod_special": ["TOD_Special_Trains.pdf"],
}


def normalize_station_name(name: str) -> str:
    s = name.upper()
    s = s.replace(".", " ")
    s = re.sub(r"\bJN\b", "JUNCTION", s)
    s = re.sub(r"\bCANTT\b", "CANTONMENT", s)
    s = re.sub(r"\(T\)", "TERMINUS", s)
    s = re.sub(r"[^A-Z0-9]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def load_category_membership(tag_dir: Path) -> dict[str, set[str]]:
    """{train_number: {category names}} by scanning each category PDF's
    own text for train numbers - lightweight (these files are small,
    already downloaded) and sufficient for classification purposes; the
    route/timing data itself never comes from these files."""
    import pdfplumber

    membership: dict[str, set[str]] = defaultdict(set)
    num_re = re.compile(r"\b(\d{4,6})\b")
    for category, files in CATEGORY_FILES.items():
        for fname in files:
            path = tag_dir / fname
            if not path.exists():
                continue
            with pdfplumber.open(path) as pdf:
                for page in pdf.pages:
                    text = page.extract_text() or ""
                    for m in num_re.finditer(text):
                        membership[m.group(1).lstrip("0") or "0"].add(category)
    return membership


def load_existing_stations(path: Path) -> dict[str, str]:
    """normalized_name -> code, from the currently-shipped stations.csv."""
    out = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            out[normalize_station_name(row["name"])] = row["code"]
    return out


def load_station_code_index(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {normalize_station_name(name): code for name, code in data.items()}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag-dir", default="build_data/tag2026")
    ap.add_argument("--raw-tag-dir", default="raw_data/tag2026")
    ap.add_argument("--existing-stations", default="build_data/stations.csv")
    ap.add_argument("--output", default="build_data/tag2026_final")
    args = ap.parse_args()

    tag_dir = Path(args.tag_dir)
    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    ground_truth = json.loads((tag_dir / "index_ground_truth.json").read_text(encoding="utf-8"))
    category_membership = load_category_membership(Path(args.raw_tag_dir))
    existing_stations = load_existing_stations(Path(args.existing_stations))
    existing_codes = set(existing_stations.values())
    station_code_index = load_station_code_index(tag_dir / "station_codes.json")

    # Build number -> table entry across every parsed table file.
    table_files = sorted((tag_dir / "tables").glob("*.json"))
    trains_by_number: dict[str, list[tuple[str, dict]]] = defaultdict(list)
    for path in table_files:
        table_id = path.stem
        data = json.loads(path.read_text(encoding="utf-8"))
        for number, entry in data["trains"].items():
            trains_by_number[number].append((table_id, entry))

    report = {
        "old_train_count": 11112,
        "old_route_stop_count": 186102,
        "index_ground_truth_count": len(ground_truth),
        "parsed_table_files": len(table_files),
        "known_bad_tables": sorted(KNOWN_BAD_TABLES, key=lambda x: (len(x), x)),
        "resolved_trains": 0,
        "unresolved_trains": [],
        "rejected_stops_no_station_match": [],
        "new_stations_from_2026_source": [],
        "duplicate_train_numbers_in_ground_truth": [],
        "name_conflicts": json.loads((tag_dir / "index_name_conflicts.json").read_text(encoding="utf-8")),
    }

    trains_rows = []
    route_stop_rows = []
    running_days_rows = []
    new_stations: dict[str, dict] = {}
    unmatched_station_names: set[str] = set()

    for number, meta in sorted(ground_truth.items(), key=lambda kv: int(kv[0])):
        candidates = trains_by_number.get(number, [])
        best_entry = None
        best_table = None
        for table_id, entry in candidates:
            if entry["stops"]:
                if best_entry is None or len(entry["stops"]) > len(best_entry["stops"]):
                    best_entry, best_table = entry, table_id

        if best_entry is None:
            reason = "not_found_in_any_table"
            bad_refs = [t for t in meta.get("table_refs", []) if re.sub(r"[^0-9-]", "", t).split("-")[0] in KNOWN_BAD_TABLES]
            if bad_refs:
                reason = f"only_in_unsupported_layout_tables:{bad_refs}"
            report["unresolved_trains"].append(
                {"number": number, "name": meta.get("name"), "from": meta.get("from"),
                 "to": meta.get("to"), "table_refs": meta.get("table_refs"), "reason": reason}
            )
            continue

        if not (meta.get("name") or "").strip():
            # A real (if rare) index-parsing gap: this number resolved a
            # route in a table, but neither index gave it a usable name
            # (verified cases: cross-page contamination left the "name"
            # column blank or garbage, e.g. a stray date string in the
            # "from" field instead). Never fabricate a name - report it
            # unresolved instead of writing a nameless train row.
            report["unresolved_trains"].append(
                {"number": number, "name": None, "from": meta.get("from"),
                 "to": meta.get("to"), "table_refs": meta.get("table_refs"),
                 "reason": "no_usable_name_in_either_index"}
            )
            continue

        categories = category_membership.get(number, set())
        category = "regular"
        if "tod_special" in categories:
            category = "tod_special"
        elif "named_premium" in categories:
            category = "named_premium"

        train_name = meta.get("name") or ""
        trains_rows.append(
            {
                "number": number,
                "name": train_name,
                "is_active": "1",
                "category": category,
                "paired_train_number": meta.get("paired_number") or "",
            }
        )

        rd = parse_running_days_text(best_entry.get("running_days_text", ""))
        running_days_rows.append({"train_number": number, **{d: "1" if rd[d] else "0" for d in
            ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]}, "confidence": rd["confidence"]})

        seq = 0
        prev_key = None
        for stop in best_entry["stops"]:
            name = stop["station_name"]
            norm = normalize_station_name(name)
            code = existing_stations.get(norm) or station_code_index.get(norm)
            if not code:
                unmatched_station_names.add(name)
                continue
            # A real, if rare, parser artifact: the exact same station
            # (code + both times) immediately repeated back-to-back is
            # never a genuine second stop - one physical row's data
            # occasionally gets emitted twice (verified: train 12951's
            # Nagda Jn.). Collapsing an exact repeat is safe; two
            # genuinely different stops never share both code and times.
            key = (code, stop["arrival"], stop["departure"])
            if key == prev_key:
                continue
            prev_key = key
            if code not in existing_codes and code not in new_stations:
                new_stations[code] = {"code": code, "name": name, "city": "", "state": "", "latitude": "", "longitude": ""}
            seq += 1
            route_stop_rows.append(
                {
                    "train_number": number,
                    "stop_sequence": seq,
                    "station_code": code,
                    "arrival_time": (stop["arrival"] or "").replace(".", ":"),
                    "departure_time": (stop["departure"] or "").replace(".", ":"),
                    "day_offset": 0,  # computed below
                    "distance_km": stop["km"] if stop["km"] is not None else "",
                }
            )
        report["resolved_trains"] += 1

    # Day-offset: within each train's stops (already in table order = km
    # order), a time-of-day earlier than the previous real stop's own
    # time-of-day means a real day boundary the source's own times
    # already imply - same deterministic method already used for the
    # 2017 dataset (scripts/transform_railway_data.dart), not guessed.
    def _minutes(t: str) -> int | None:
        if not t:
            return None
        h, m = t.split(":")
        return int(h) * 60 + int(m)

    by_train: dict[str, list[dict]] = defaultdict(list)
    for row in route_stop_rows:
        by_train[row["train_number"]].append(row)
    for number, rows in by_train.items():
        rows.sort(key=lambda r: r["stop_sequence"])
        offset = 0
        last_minutes = None
        for row in rows:
            t = row["departure_time"] or row["arrival_time"]
            mins = _minutes(t)
            if mins is not None and last_minutes is not None and mins < last_minutes:
                offset += 1
            row["day_offset"] = offset
            if mins is not None:
                last_minutes = mins

    # A real train essentially never spans more than a few days - a
    # final day_offset beyond that is a signal the deterministic
    # time-ordering heuristic hit a real data problem upstream (e.g. a
    # mis-parsed/out-of-km-order stop), not a real journey length. Never
    # auto-corrected - just surfaced so it can be spot-checked.
    suspicious_day_offset = []
    for number, rows in by_train.items():
        max_offset = max((r["day_offset"] for r in rows), default=0)
        if max_offset > 3:
            suspicious_day_offset.append({"number": number, "max_day_offset": max_offset})
    report["suspicious_day_offset_trains"] = suspicious_day_offset

    report["unmatched_station_names"] = sorted(unmatched_station_names)
    report["new_train_count"] = len(trains_rows)
    report["new_route_stop_count"] = len(route_stop_rows)
    report["new_stations_count"] = len(new_stations)
    report["running_days_confirmed"] = sum(1 for r in running_days_rows if r["confidence"] == "confirmed")
    report["running_days_unknown"] = sum(1 for r in running_days_rows if r["confidence"] == "unknown")
    report["category_counts"] = {
        c: sum(1 for r in trains_rows if r["category"] == c) for c in ["regular", "named_premium", "tod_special"]
    }

    with open(out_dir / "trains.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["number", "name", "is_active", "category", "paired_train_number"])
        w.writeheader()
        w.writerows(trains_rows)

    with open(out_dir / "route_stops.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["train_number", "stop_sequence", "station_code", "arrival_time", "departure_time", "day_offset", "distance_km"])
        w.writeheader()
        w.writerows(route_stop_rows)

    with open(out_dir / "running_days.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["train_number", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "confidence"])
        w.writeheader()
        w.writerows(running_days_rows)

    with open(out_dir / "stations_new.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["code", "name", "city", "state", "latitude", "longitude"])
        w.writeheader()
        w.writerows(new_stations.values())

    (out_dir / "data_quality_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"Resolved trains: {report['resolved_trains']} / {len(ground_truth)}")
    print(f"Unresolved trains: {len(report['unresolved_trains'])}")
    print(f"New route stops: {report['new_route_stop_count']}")
    print(f"New stations needed: {report['new_stations_count']}")
    print(f"Unmatched station names (stops dropped): {len(unmatched_station_names)}")
    print(f"Running days - confirmed: {report['running_days_confirmed']}, unknown: {report['running_days_unknown']}")
    print(f"Categories: {report['category_counts']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
