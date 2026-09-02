#!/usr/bin/env python3
"""Parses TableNumberIndex.pdf (+ cross-checks Train_Name_Index.pdf) into
the ground-truth "which trains should exist" map everything else in this
pipeline is validated against (see docs/RAILWAY_DATABASE.md Block 6 /
the approved plan's parse_indexes.py description).

Output: build_data/tag2026/index_ground_truth.json
  { "<number>": {"number": "12301", "paired_number": "12302",
                 "from": "Howrah", "to": "New Delhi", "name": "...",
                 "table_refs": ["1A"], "sources": ["number_index"]} }

Each index page is a 2-up layout: two independent 5-column blocks
(Train No. | From station | To station | Train Name | Table No.),
each repeated left/right. Column boundaries are derived per-page from
the header words' own x-positions (see pdf_columns.py) rather than
hardcoded, since a hardcoded pixel position is exactly the kind of
assumption that silently breaks on a slightly different page/export.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import pdfplumber

from pdf_columns import Word, bin_column, cluster_1d, column_boundaries, get_words

TRAIN_NO_RE = re.compile(r"^\d{4,6}(/\d{4,6})?$")
# Both index PDFs use slightly different header wording/casing and column
# order (verified: TableNumberIndex.pdf has "No." with a period and
# lowercase "station", column order No/From/To/Name/TableNo;
# Train_Name_Index.pdf has "No" with no period and "Station" capitalized,
# column order Name/No/From/To/TableNo) - match loosely by lowercasing/
# stripping punctuation, and let each file's own COLUMN_SCHEMA say what
# each ascending-x column position actually means for that file.
HEADER_LABELS = {"train", "no", "no.", "from", "to", "station", "name", "table"}
NUMBER_INDEX_SCHEMA = ["number", "from", "to", "name", "table_refs"]
NAME_INDEX_SCHEMA = ["name", "number", "from", "to", "table_refs"]


def find_header(words: list[Word]) -> tuple[list[float], float]:
    """Returns (column anchor x0s, y below which real data rows start).

    The header band's absolute y position varies per page (verified:
    page 0 has it at top~73-83 with data starting ~93; page 2 has it at
    top~41-50 with data starting ~61) - so the data cutoff must be
    derived from where THIS page's header words actually are, never a
    fixed constant.
    """
    # Header is always the first ~20pt of words on the page; scan a
    # generous early band, then use the header words' own max y as the
    # data-start cutoff instead of a fixed threshold.
    candidates = [w for w in words if w.text.lower().rstrip(".") in HEADER_LABELS]
    candidates.sort(key=lambda w: w.top)
    if not candidates:
        return [], 0.0
    header_top = candidates[0].top
    header_words = [w for w in candidates if w.top <= header_top + 15]
    if not header_words:
        return [], 0.0
    clusters = cluster_1d([w.x0 for w in header_words], gap=15)
    anchors = [min(c) for c in clusters]
    data_start_y = max(w.top for w in header_words) + 3
    return anchors, data_start_y


def parse_page(page, column_schema: list[str]) -> list[dict]:
    words = get_words(page)
    anchors, data_start_y = find_header(words)
    if len(anchors) < 5:
        return []  # no data table on this page (e.g. a blank/title page)
    boundaries = column_boundaries(anchors, page.width)
    n_cols = len(anchors)
    n_blocks = n_cols // 5
    number_col = column_schema.index("number")

    data_words = [w for w in words if w.top > data_start_y]
    binned = [(bin_column(w.x0, boundaries), w) for w in data_words]

    entries: list[dict] = []
    # Track per-block current entry since blocks interleave in y but are
    # independent logical columns.
    current_by_block: dict[int, dict | None] = {b: None for b in range(n_blocks)}

    # Process in reading order (top to bottom, then left to right) so a
    # continuation line's words append to the right block's current entry.
    for col, w in sorted(binned, key=lambda cw: (cw[1].top, cw[1].x0)):
        block = col // 5
        col_in_block = col % 5
        if col_in_block == number_col and TRAIN_NO_RE.match(w.text):
            entry = {"train_no_raw": w.text, "cells": {i: [] for i in range(5)}}
            entries.append(entry)
            current_by_block[block] = entry
        else:
            cur = current_by_block[block]
            if cur is not None:
                cur["cells"][col_in_block].append(w.text)
            # else: stray word before any entry started in this block/page - drop

    results = []
    for e in entries:
        parts = e["train_no_raw"].split("/")
        number = parts[0].lstrip("0") or "0"
        paired = parts[1].lstrip("0") if len(parts) > 1 else None
        by_field = {}
        for col_in_block, field in enumerate(column_schema):
            if field == "number":
                continue
            text = " ".join(e["cells"][col_in_block]).strip()
            if field == "table_refs":
                by_field["table_refs"] = [
                    t.strip() for t in text.replace("\n", " ").split(",") if t.strip()
                ]
            else:
                by_field[field] = text
        results.append({"number": number, "paired_number": paired, **by_field})
    return results


def parse_pdf(path: Path, column_schema: list[str]) -> list[dict]:
    out = []
    with pdfplumber.open(path) as pdf:
        for page in pdf.pages:
            out.extend(parse_page(page, column_schema))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default="raw_data/tag2026")
    ap.add_argument("--output", default="build_data/tag2026")
    args = ap.parse_args()

    in_dir = Path(args.input)
    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    number_index = parse_pdf(in_dir / "TableNumberIndex.pdf", NUMBER_INDEX_SCHEMA)
    name_index = parse_pdf(in_dir / "Train_Name_Index.pdf", NAME_INDEX_SCHEMA)

    print(f"TableNumberIndex.pdf: {len(number_index)} entries parsed")
    print(f"Train_Name_Index.pdf: {len(name_index)} entries parsed")

    ground_truth: dict[str, dict] = {}
    conflicts = []

    # TableNumberIndex.pdf's own "Train Name" column is frequently a
    # shortened form (verified on real rows: "AC Double Decker" vs
    # Train_Name_Index.pdf's "AC Double Decker Exp.", "Exp" vs "Ajmer
    # Exp") - not a parsing defect, a real difference in each official
    # document's own convention (the name index needs the fuller,
    # destination-qualified name to sort/search by). Prefer whichever
    # name is the longer one when one is a prefix/substring of the
    # other (case/punctuation-insensitive); only names that are neither
    # count as a genuine cross-source conflict worth reporting.
    def _norm(s: str) -> str:
        return re.sub(r"[^a-z0-9]", "", s.lower())

    for source_name, entries in [("number_index", number_index), ("name_index", name_index)]:
        for e in entries:
            num = e["number"]
            if not num or not num.isdigit():
                continue
            if num not in ground_truth:
                ground_truth[num] = {**e, "sources": [source_name]}
            else:
                existing = ground_truth[num]
                existing["sources"].append(source_name)
                a, b = existing["name"], e["name"]
                if a and b and a != b:
                    na, nb = _norm(a), _norm(b)
                    if na in nb or nb in na:
                        if len(b) > len(a):
                            existing["name"] = b
                    else:
                        conflicts.append(
                            {"number": num, "name_a": a, "name_b": b,
                             "source_a": existing["sources"][0], "source_b": source_name}
                        )
                # Union table refs (index pages occasionally wrap differently)
                for ref in e["table_refs"]:
                    if ref not in existing["table_refs"]:
                        existing["table_refs"].append(ref)

    (out_dir / "index_ground_truth.json").write_text(
        json.dumps(ground_truth, indent=2, sort_keys=True), encoding="utf-8"
    )
    (out_dir / "index_name_conflicts.json").write_text(
        json.dumps(conflicts, indent=2), encoding="utf-8"
    )

    print(f"\nGround truth: {len(ground_truth)} unique train numbers")
    print(f"Name conflicts between the two indexes: {len(conflicts)}")
    only_number = sum(1 for e in ground_truth.values() if e["sources"] == ["number_index"])
    only_name = sum(1 for e in ground_truth.values() if e["sources"] == ["name_index"])
    both = sum(1 for e in ground_truth.values() if len(set(e["sources"])) == 2)
    print(f"  in both indexes: {both}, number-index only: {only_number}, name-index only: {only_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
