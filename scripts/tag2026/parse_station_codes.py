#!/usr/bin/env python3
"""Parses Station_Code_Index.pdf (4 Name|Code blocks per page) into a
name -> code map, used by reconcile.py as a fallback source of station
codes for names the existing (2017-derived) stations.csv doesn't
recognize - never to replace an existing station's own code (see
docs/RAILWAY_DATABASE.md Block 6 / the approved plan)."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import pdfplumber

from pdf_columns import Word, bin_column, cluster_1d, column_boundaries, get_words

HEADER_LABELS = {"station", "name", "code"}
CODE_RE = re.compile(r"^[A-Z0-9]{2,6}$")


def find_header(words: list[Word]) -> tuple[list[float], float]:
    candidates = [w for w in words if w.text.lower().rstrip(".") in HEADER_LABELS]
    if not candidates:
        return [], 0.0
    # The page title ("Station Code Index") also matches these keywords
    # and can sit above the real repeated "Station Name Code x4" header
    # row - pick whichever distinct top-band has the most matches, not
    # simply the topmost one (verified: the title band has 2 words, the
    # real header band has 12).
    bands: dict[float, list[Word]] = {}
    for w in sorted(candidates, key=lambda w: w.top):
        placed = False
        for band_top in list(bands):
            if abs(w.top - band_top) <= 5:
                bands[band_top].append(w)
                placed = True
                break
        if not placed:
            bands[w.top] = [w]
    header_words = max(bands.values(), key=len)
    # Each block's header reads "Station Name" (a 2-word label for one
    # column) then "Code" (the second column) - use "Station" and
    # "Code" tokens only as anchors; a lone "Name" word is the second
    # half of the first column's own label, not a separate column.
    anchor_words = [w for w in header_words if w.text.lower().rstrip(".") in ("station", "code")]
    anchors = sorted(w.x0 for w in anchor_words)
    data_start_y = max(w.top for w in header_words) + 3
    return anchors, data_start_y


def parse_page(page) -> dict[str, str]:
    words = get_words(page)
    anchors, data_start_y = find_header(words)
    if len(anchors) < 2:
        return {}
    boundaries = column_boundaries(anchors, page.width)
    n_blocks = len(anchors) // 2

    data_words = [w for w in words if w.top > data_start_y]
    binned = [(bin_column(w.x0, boundaries), w) for w in data_words]

    result: dict[str, str] = {}
    current_by_block: dict[int, list[str]] = {b: [] for b in range(n_blocks)}
    for col, w in sorted(binned, key=lambda cw: (cw[1].top, cw[1].x0)):
        block = col // 2
        col_in_block = col % 2
        if col_in_block == 1 and CODE_RE.match(w.text):
            name = " ".join(current_by_block[block]).strip()
            if name:
                result[name] = w.text
            current_by_block[block] = []
        elif col_in_block == 0:
            current_by_block[block].append(w.text)
        # a code-column word that doesn't look like a code is dropped -
        # rare mis-bin, never guessed into a station.
    return result


def parse_station_codes(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    with pdfplumber.open(path) as pdf:
        for page in pdf.pages:
            out.update(parse_page(page))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default="raw_data/tag2026/Station_Code_Index.pdf")
    ap.add_argument("--output", default="build_data/tag2026/station_codes.json")
    args = ap.parse_args()

    result = parse_station_codes(Path(args.input))
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")
    print(f"Parsed {len(result)} station name -> code entries")
    for k in list(result)[:5]:
        print(f"  {k!r} -> {result[k]!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
