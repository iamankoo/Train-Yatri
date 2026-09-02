#!/usr/bin/env python3
"""Runs parse_table.py over every numbered TAG-2026 table PDF and prints
an aggregate summary (see the approved plan's sequencing step 3: run
across all tables, surface parser failures early)."""
from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from parse_table import parse_table_pdf


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-dir", default="../../raw_data/tag2026")
    ap.add_argument("--output-dir", default="../../build_data/tag2026/tables")
    ap.add_argument("--file-list", default="table_files.txt")
    args = ap.parse_args()

    in_dir = Path(args.input_dir)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    files = [line.strip() for line in Path(args.file_list).read_text().splitlines() if line.strip()]

    total_trains = 0
    total_stops = 0
    total_warnings = 0
    zero_train_tables = []
    zero_stop_trains_all = 0
    t0 = time.time()

    for i, fname in enumerate(files, 1):
        path = in_dir / fname
        if not path.exists():
            print(f"[{i}/{len(files)}] {fname}: MISSING FILE")
            continue
        try:
            result = parse_table_pdf(path)
        except Exception as e:  # noqa: BLE001 - surface, never silently skip a table
            print(f"[{i}/{len(files)}] {fname}: EXCEPTION {e!r}")
            continue
        n_trains = len(result["trains"])
        n_stops = sum(len(t["stops"]) for t in result["trains"].values())
        n_zero_stop = sum(1 for t in result["trains"].values() if not t["stops"])
        total_trains += n_trains
        total_stops += n_stops
        total_warnings += len(result["warnings"])
        zero_stop_trains_all += n_zero_stop
        if n_trains == 0:
            zero_train_tables.append(fname)

        out_path = out_dir / (path.stem + ".json")
        out_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(
            f"[{i}/{len(files)}] {fname}: {n_trains} trains, {n_stops} stops, "
            f"{n_zero_stop} zero-stop, {len(result['warnings'])} warnings"
        )

    elapsed = time.time() - t0
    print("\n=== SUMMARY ===")
    print(f"Tables processed: {len(files)} in {elapsed:.1f}s")
    print(f"Total train-column entries (not yet deduped across tables): {total_trains}")
    print(f"Total stop-rows: {total_stops}")
    print(f"Total warnings: {total_warnings}")
    print(f"Trains with zero parsed stops: {zero_stop_trains_all}")
    if zero_train_tables:
        print(f"Tables with ZERO trains parsed (needs investigation): {zero_train_tables}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
