#!/usr/bin/env python3
"""Parses one TAG-2026 numbered detailed timetable table PDF (e.g. 1.pdf)
into per-train, per-stop rows - the real stop-by-stop data (see the
approved plan's "Tooling decision" section and docs/RAILWAY_DATABASE.md
Block 6).

Verified table structure (inspected 1.pdf pages 1-2, 19.pdf, 26.pdf,
94.pdf, 97.pdf by hand before writing this) - **repeated fresh on every
page**, each page covering a different subset of train columns:

  TRAIN NAME            <- wraps over several lines, one train per column
  Train Number          <- clean single-token anchor row, used to derive
                            column x-positions (the reliable anchor - the
                            wrapped name row above is not: adjacent
                            trains' name words interleave in x)
  Class of accommodation
  From Table No.
  Days of departure at originating station   <- real running-days text
  Km.  <station rows...>  a/d  <times per train column>
  Days of arrival at destination station
  To Table No.
  [optional footnote lines, e.g. "* T.No. 22198 will be fully
   cancelled due to foggy season from 01.01.2026 to 28.02.2026..." -
   real seasonal/TOD restriction text, captured verbatim per page]

Every header field's value wraps across a *variable* number of lines
per column (confirmed on real data: "Class" needs 1-3 lines depending
on the column), so the field label itself can end up on any one line of
that group with wrapped-continuation lines carrying no label text
before or after it - handled by `_segment_page` + the state-machine
line walk in `parse_header_block`, not a fixed line-count assumption.
A station row is similarly 1-3 physical lines: a single 'd' (origin) or
'a' (terminus) line, or a stacked 'a' then 'd' pair for a through stop,
each optionally preceded by label-only lines for a wrapped station name
(verified: "Pt. Deen Dayal" / "Upadhyaya Jn." + 'a' + times, table 1
page 1) - see `parse_body_rows`.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

import pdfplumber

from pdf_columns import Word, bin_column, column_boundaries, get_words_from_chars

TRAIN_NO_TOKEN_RE = re.compile(r"^(\d{4,6})[\*#†]{0,3}$")
TIME_RE = re.compile(r"^\d{1,2}\.\d{2}$")
FLAG_CHARS = {"a", "d"}


@dataclass
class StopRow:
    km: float | None
    station_name: str
    times_by_flag: dict[str, dict[int, str]] = field(default_factory=dict)
    notes: dict[int, list[str]] = field(default_factory=dict)


def find_train_columns(lines: list[list[Word]]) -> tuple[list[float], list[str], float, int] | None:
    """Finds the "Train Number" row. Returns (anchors, raw_numbers,
    label_boundary, line_index) or None if this page has no such row."""
    best = None
    best_idx = None
    for i, line in enumerate(lines):
        toks = [w for w in line if TRAIN_NO_TOKEN_RE.match(w.text)]
        if len(toks) >= 3 and (best is None or len(toks) > len(best)):
            best, best_idx = toks, i
    if not best:
        return None
    best.sort(key=lambda w: w.x0)
    anchors = [w.x0 for w in best]
    numbers = [w.text for w in best]

    # The label zone's right edge should sit just past the rightmost
    # 'a'/'d' arrival/departure flag - narrower than half the
    # inter-train-column gap in the simple single-flag-per-line layout
    # (verified: flags sit ~11pt left of the first train anchor while
    # half the anchor gap is ~15pt), but in the "twin block" paired
    # up/down layout (verified: 28.pdf, 45.pdf, 56.pdf, 67.pdf and ~30
    # others) a *second* flag sits embedded just after the station name,
    # closer to the first train anchor than a plain single flag would be
    # - so the search must not be restricted to `x0 < anchors[0]` only
    # (that missed the second flag entirely, leaving the boundary too
    # far left and misclassifying "Km."/station-name words as column-0
    # train data). Measuring every lone 'a'/'d' token on the whole page
    # is safe: a real station name is never a bare single character.
    flag_x0s = [w.x0 for line in lines for w in line if w.text in FLAG_CHARS and w.x0 < anchors[0] + 5]
    gap0 = anchors[1] - anchors[0] if len(anchors) > 1 else 40.0
    if flag_x0s:
        label_boundary = max(flag_x0s) + 2.0
    else:
        label_boundary = anchors[0] - gap0 / 2
    return anchors, numbers, label_boundary, best_idx


def _line_text(words: list[Word]) -> str:
    return " ".join(w.text for w in words)


def _label_words(line: list[Word], label_boundary: float) -> list[Word]:
    return [w for w in line if w.x0 < label_boundary]


def _is_flag_only(label_words_here: list[Word]) -> bool:
    return len(label_words_here) == 1 and label_words_here[0].text in FLAG_CHARS


def segment_page(
    lines: list[list[Word]], train_no_idx: int, label_boundary: float
) -> tuple[int, int]:
    """Returns (body_start_idx, body_end_idx): the line-index range of
    real station rows, excluding the Train Name/Number/Class/Table/Days
    header above and the Days-of-arrival/To-Table-No./footnote footer
    below - both of variable, per-column line length, so found by
    scanning for the actual trigger lines rather than assumed fixed
    offsets from train_no_idx."""
    body_start = len(lines)
    for i in range(train_no_idx + 1, len(lines)):
        lw = _label_words(lines[i], label_boundary)
        label = _line_text(lw)
        if "Km" in label or _is_flag_only(lw):
            body_start = i
            break

    body_end = len(lines)
    for i in range(body_start, len(lines)):
        lw = _label_words(lines[i], label_boundary)
        label = _line_text(lw)
        if "Days" in label and ("arrival" in label or "destination" in label):
            body_end = i
            break

    return body_start, body_end


def parse_header_block(
    lines: list[list[Word]],
    anchors: list[float],
    numbers: list[str],
    label_boundary: float,
    page_width: float,
    train_no_idx: int,
    body_start: int,
) -> dict:
    """Extracts, per train column: class, from-table-no, running-days text."""
    boundaries = column_boundaries(anchors, page_width)
    per_col: dict[int, dict] = {
        i: {"class": [], "from_table_no": [], "running_days_text": []} for i in range(len(anchors))
    }

    def bin_line(line: list[Word]) -> dict[int, list[Word]]:
        out: dict[int, list[Word]] = {}
        for w in line:
            if w.x0 < label_boundary:
                continue
            out.setdefault(bin_column(w.x0, boundaries), []).append(w)
        return out

    state: str | None = None
    for line in lines[train_no_idx + 1 : body_start]:
        label = _line_text(_label_words(line, label_boundary))
        if "Class" in label:
            state = "class"
        elif "From" in label and "Table" in label:
            state = "from_table_no"
        elif "Days" in label:
            state = "running_days_text"
        if state is None:
            continue
        for col, ws in bin_line(line).items():
            per_col[col][state].append(_line_text(ws))

    result = {}
    for col, numstr in enumerate(numbers):
        result[numstr] = {
            "class": "".join(per_col[col]["class"]).strip(),
            "from_table_no": "".join(per_col[col]["from_table_no"]).strip(),
            "running_days_text": "".join(per_col[col]["running_days_text"]).strip(),
        }
    return result


TABLE_REF_RE = re.compile(r"^\d{1,3}[A-Za-z]?(-\d{1,3}[A-Za-z]?)?$")


def parse_footer_block(
    lines: list[list[Word]], anchors: list[float], numbers: list[str], label_boundary: float, page_width: float,
    body_end: int,
) -> tuple[dict, list[str]]:
    """Extracts per-column "To Table No." plus any raw footnote lines
    (e.g. seasonal-cancellation notices) found after it, verbatim.

    Deliberately conservative: only the "To Table No." label line and an
    immediately-following pure-continuation line (label-empty, every
    train-zone token itself table-ref-shaped) are ever captured as data -
    anything else in the footer (footnote prose, stray decorative
    single-character lines from a rotated margin label) is either kept
    verbatim as a footnote or ignored, never miscategorized as a table
    number. This was tightened after a real bug: an unbounded "keep
    capturing until end of page" state machine pulled footnote *words*
    ("Tuesday", "Monday", ...) into to_table_no.
    """
    boundaries = column_boundaries(anchors, page_width)
    per_col: dict[int, list[str]] = {i: [] for i in range(len(anchors))}
    footnotes: list[str] = []

    footer_lines = lines[body_end:]
    to_table_line_idx = None
    for i, line in enumerate(footer_lines):
        label = _line_text(_label_words(line, label_boundary))
        if "To" in label and "Table" in label:
            to_table_line_idx = i
            break

    candidate_idxs = []
    if to_table_line_idx is not None:
        candidate_idxs.append(to_table_line_idx)
        nxt = to_table_line_idx + 1
        if nxt < len(footer_lines):
            lw = _label_words(footer_lines[nxt], label_boundary)
            train_toks = [w for w in footer_lines[nxt] if w.x0 >= label_boundary]
            if not lw and train_toks and all(TABLE_REF_RE.match(w.text) for w in train_toks):
                candidate_idxs.append(nxt)

    for i in candidate_idxs:
        for w in footer_lines[i]:
            if w.x0 < label_boundary:
                continue
            if not TABLE_REF_RE.match(w.text):
                continue
            per_col[bin_column(w.x0, boundaries)].append(w.text)

    for line in footer_lines:
        full_text = _line_text(sorted(line, key=lambda w: w.x0))
        if re.match(r"^\*{1,3}\s?[A-Za-z]", full_text):
            footnotes.append(full_text)

    result = {}
    for col, numstr in enumerate(numbers):
        result[numstr] = "".join(per_col[col]).strip()
    return result, footnotes


def _flag_for_column(flag_words: list[Word], col: int, n_cols: int) -> str:
    """Most tables show one flag ('a' or 'd') per physical line, applying
    to every column. Some tables (verified: 28.pdf Sri Ganganagar-Kota,
    45.pdf, 56.pdf, 67.pdf, and others - roughly 30 of the 97 tables) use
    a "twin block" layout instead: a paired up/down service shown side
    by side sharing one station-name column, with BOTH directions' flags
    on the same line (e.g. "d Delhi a" - 'd' for the left half of
    columns/one direction, 'a' for the right half/the other direction).
    Confirmed by checking real train-number ordering: in these tables
    the second half of the anchor columns is the *reverse* of the first
    half's own numbers (e.g. table 28: first-half number N pairs with
    second-half's N+/-1) - the same up/down pairing convention used
    elsewhere, just laid out horizontally instead of as separate tables.
    With exactly 2 flags on a line, the first governs the first half of
    columns and the second the rest; with 1 flag, it governs all of
    them.
    """
    if len(flag_words) <= 1:
        return flag_words[0].text if flag_words else ""
    mid = n_cols // 2
    return flag_words[0].text if col < mid else flag_words[-1].text


def _extract_times(
    line: list[Word], label_boundary: float, boundaries: list[float], flag_words: list[Word], n_cols: int
) -> tuple[dict[str, dict[int, str]], dict[int, list[str]]]:
    """Returns ({flag: {col: time}}, {col: [notes]}) - flag-aware so a
    twin-block line's two halves land in the correct arrival/departure
    bucket instead of both being mislabeled with a single flag."""
    time_by_flag: dict[str, dict[int, str]] = {}
    note_map: dict[int, list[str]] = {}
    binned: dict[int, list[Word]] = {}
    for w in line:
        if w.x0 < label_boundary:
            continue
        binned.setdefault(bin_column(w.x0, boundaries), []).append(w)
    for col, ws in binned.items():
        flag = _flag_for_column(flag_words, col, n_cols)
        time_toks = [w.text for w in ws if TIME_RE.match(w.text) or w.text == "..."]
        if time_toks and flag:
            time_by_flag.setdefault(flag, {})[col] = time_toks[0]
        else:
            note_toks = [w.text for w in ws if w.text != "..."]
            if note_toks:
                note_map.setdefault(col, []).append(" ".join(note_toks))
    return time_by_flag, note_map


def parse_body_rows(
    lines: list[list[Word]], anchors: list[float], label_boundary: float, page_width: float
) -> list[StopRow]:
    """Reconstructs station rows from the body's physical lines.

    Verified on real data (table 1, page 1: the Delhi and Kanpur rows)
    that a two-line "a" + "d" station has its *name* label printed at
    the exact vertical midpoint between the two data lines (e.g. 'a' at
    top=294.1, name at top=297.1, 'd' at top=300.1 - 297.1 is exactly
    the midpoint), not stacked directly above/below them in y-order.
    Grouping by simple top-to-bottom adjacency therefore attaches a
    station's arrival time to the *previous* station's row (a real bug,
    caught by manually checking Kanpur's arrival time ended up on
    Etawah's row before this fix). This instead finds each name line's
    two candidate flag lines by their *expected offset* from that
    midpoint, not by simple sequential adjacency.
    """
    boundaries = column_boundaries(anchors, page_width)
    n_cols = len(anchors)

    classified = []  # (index, kind, top, non_flag, flag_words, train_words)
    for i, line in enumerate(lines):
        label_words = _label_words(line, label_boundary)
        flag_words = [w for w in label_words if w.text in FLAG_CHARS]
        non_flag = [w for w in label_words if w.text not in FLAG_CHARS]
        train_words = [w for w in line if w.x0 >= label_boundary]
        if non_flag:
            kind = "name"
        elif flag_words and len(label_words) == len(flag_words):
            kind = "flag"  # 1 or 2 flags (twin-block layout), never text
        elif train_words:
            kind = "annotation"
        else:
            kind = "empty"
        classified.append((i, kind, line[0].top if line else 0.0, non_flag, flag_words, train_words))

    used_flag_idx: set[int] = set()
    rows: list[StopRow] = []

    name_indices = [c for c in classified if c[1] == "name"]
    invalid_flags: list[bool] = []
    for idx, (i, kind, top, non_flag, flag_words, train_words) in enumerate(name_indices):
        km = None
        words = list(non_flag)
        if words and re.match(r"^\d+$", words[0].text):
            km = float(words[0].text)
            words = words[1:]
        elif words:
            # Narrow-column tables sometimes render the Km figure with no
            # visible gap before the station name (verified: "1027Bareilly"
            # as one merged token) - the word-builder's gap threshold
            # can't separate them since there's no real gap to detect, so
            # split on the digit/letter boundary here instead.
            m = re.match(r"^(\d+)([A-Za-z].*)$", words[0].text)
            if m:
                km = float(m.group(1))
                words[0] = Word(m.group(2), words[0].x0, words[0].x1, words[0].top, words[0].bottom)
        if words and words[0].text.rstrip(".") == "Km":
            # The origin row has nothing to put in the Km column (there's
            # no distance from itself), so the literal "Km." label prints
            # in that cell instead of a number (verified: "Km. Howrah") -
            # strip it so the name matches the real station, not
            # "Km. Howrah".
            words = words[1:]
        name_text = _line_text(words).strip()
        invalid_flags.append(bool(TIME_RE.match(name_text) or re.match(r"^[\d.\s]*$", name_text) or not name_text))
        row = StopRow(km=km, station_name=name_text)
        rows.append(row)

        # Case 1: name line itself already carries a flag (or twin-block
        # flag pair) + real time data (e.g. "25 Ghaziabad d", or the
        # twin-block "d Delhi a").
        if flag_words and train_words:
            time_by_flag, note_map = _extract_times(lines[i], label_boundary, boundaries, flag_words, n_cols)
            if time_by_flag or note_map:
                for flag, tmap in time_by_flag.items():
                    row.times_by_flag.setdefault(flag, {}).update(tmap)
                for col, notes in note_map.items():
                    row.notes.setdefault(col, []).extend(notes)
                continue  # fully resolved from this one line

        # Case 2: look for nearby flag-only lines at the expected
        # +-3pt-ish offset from this name line's own top (the verified
        # midpoint relationship), within a tolerance generous enough for
        # per-column baseline jitter but tight enough not to reach into
        # the *next* station's sub-lines (station rows are >=6pt apart).
        for i2, kind2, top2, _, flag_words2, _ in classified:
            if kind2 != "flag" or i2 in used_flag_idx:
                continue
            if abs(top2 - top) > 4.5:
                continue
            time_by_flag, note_map = _extract_times(lines[i2], label_boundary, boundaries, flag_words2, n_cols)
            if not time_by_flag and not note_map:
                continue
            for flag, tmap in time_by_flag.items():
                row.times_by_flag.setdefault(flag, {}).update(tmap)
            for col, notes in note_map.items():
                row.notes.setdefault(col, []).extend(notes)
            used_flag_idx.add(i2)

    # Drop stray time/number-only "names" now (not later) - left in
    # place, an invalid row sitting between two real fragments of one
    # wrapped/hyphenated station name breaks the adjacency the merge
    # passes below depend on (verified: a blank-name row from a
    # discarded annotation line sat directly between "Pt. Deen Dayal"
    # and "Upadhyaya Jn.", preventing them from ever being seen as
    # neighbors).
    for idx in range(len(rows) - 1, -1, -1):
        if invalid_flags[idx]:
            del rows[idx]
            del invalid_flags[idx]
            del name_indices[idx]

    def _join_name(prefix: str, suffix: str) -> str:
        # A prefix fragment ending in a hyphen is a genuine mid-word line
        # break (verified: "Pt. Deen Dayal Upad-" + "hyaya Jn." is one
        # station, "Pt. Deen Dayal Upadhyaya Jn.") - join with no space
        # and drop the hyphen; otherwise it's a normal multi-word wrap
        # and needs the space back.
        if prefix.endswith("-"):
            return prefix[:-1] + suffix
        return f"{prefix} {suffix}".strip()

    def _should_merge_split_row(a: StopRow, b: StopRow) -> bool:
        # Two-line wrapped station names split the row's own flag(s)
        # across both lines too (each line is close enough to a real
        # flag line to independently claim it via Case 2 above) -
        # verified on both a hyphenated wrap ("Upad-"/"hyaya Jn.") and a
        # clean word-boundary wrap ("Pt. Deen Dayal"/"Upadhyaya Jn.",
        # same table, different page). The unmistakable signature: one
        # line has ONLY an arrival for a set of columns, the very next
        # has ONLY a departure for exactly that same set of columns, and
        # neither carries its own km (a real distinct station always
        # does, since Km is cumulative and virtually never repeats) -
        # two genuinely different consecutive stations essentially never
        # produce that exact complementary split by chance.
        if a.km is not None or b.km is not None:
            return False
        if a.station_name.endswith("-"):
            return True
        a_flags, b_flags = set(a.times_by_flag), set(b.times_by_flag)
        if a_flags != {"a"} or b_flags != {"d"}:
            return False
        return set(a.times_by_flag["a"]) == set(b.times_by_flag["d"])

    i = 0
    while i < len(rows) - 1:
        if _should_merge_split_row(rows[i], rows[i + 1]):
            nxt = rows[i + 1]
            nxt.station_name = _join_name(rows[i].station_name, nxt.station_name)
            if rows[i].km is not None and nxt.km is None:
                nxt.km = rows[i].km
            for flag, tmap in rows[i].times_by_flag.items():
                merged_map = nxt.times_by_flag.setdefault(flag, {})
                for col, t in tmap.items():
                    merged_map.setdefault(col, t)
            for col, notes in rows[i].notes.items():
                nxt.notes.setdefault(col, []).extend(notes)
            del rows[i]
            del invalid_flags[i]
            del name_indices[i]
            continue
        i += 1

    # Wrapped station names: a "name" line with no km, no flag and no
    # train data, immediately followed by another "name" line, is a
    # continuation of that *next* row's name (verified: "Pt. Deen Dayal"
    # then "Upadhyaya Jn." + 'a' + times) - merge forward.
    merged: list[StopRow] = []
    pending_prefix = ""
    for (i, kind, top, non_flag, flag_words, train_words), row, invalid in zip(name_indices, rows, invalid_flags):
        if invalid:
            continue  # a stray time/number that leaked into the label
            # zone, not a real station name or name fragment - drop it
            # outright rather than merge it into a neighbor's name or
            # report it as an "unmatched station".
        is_bare = not flag_words and not train_words and not row.times_by_flag and not row.notes
        if is_bare and row.station_name:
            pending_prefix = _join_name(pending_prefix, row.station_name) if pending_prefix else row.station_name
            continue
        if pending_prefix:
            row.station_name = _join_name(pending_prefix, row.station_name)
            pending_prefix = ""
        merged.append(row)

    return merged


def parse_table_pdf(path: Path) -> dict:
    """Returns {"trains": {number: {...meta, "stops": [...]}}, "warnings": [...]}"""
    trains: dict[str, dict] = {}
    warnings: list[str] = []
    footnotes_by_page: dict[int, list[str]] = {}

    with pdfplumber.open(path) as pdf:
        for page_idx, page in enumerate(pdf.pages):
            words = get_words_from_chars(page)
            if not words:
                continue
            line_map: dict[float, list[Word]] = {}
            for w in words:
                line_map.setdefault(w.top, []).append(w)
            lines = [sorted(v, key=lambda w: w.x0) for _, v in sorted(line_map.items())]

            found = find_train_columns(lines)
            if found is None:
                warnings.append(f"{path.name} page {page_idx}: no Train Number row found")
                continue
            anchors, numbers, label_boundary, train_no_idx = found
            body_start, body_end = segment_page(lines, train_no_idx, label_boundary)

            header = parse_header_block(
                lines, anchors, numbers, label_boundary, page.width, train_no_idx, body_start
            )
            to_table_no, page_footnotes = parse_footer_block(
                lines, anchors, numbers, label_boundary, page.width, body_end
            )
            if page_footnotes:
                footnotes_by_page[page_idx] = page_footnotes
            stops = parse_body_rows(lines[body_start:body_end], anchors, label_boundary, page.width)

            if not stops:
                warnings.append(f"{path.name} page {page_idx}: 0 station rows parsed")

            for col, numstr in enumerate(numbers):
                number = numstr.rstrip("*#†").lstrip("0") or "0"
                entry = trains.setdefault(
                    number,
                    {
                        "raw_column_token": numstr,
                        "source_pages": [],
                        "to_table_no": [],
                        **header.get(numstr, {}),
                        "stops": [],
                    },
                )
                entry["source_pages"].append(page_idx)
                if to_table_no.get(numstr):
                    entry["to_table_no"].append(to_table_no[numstr])
                for stop in stops:
                    arr = stop.times_by_flag.get("a", {}).get(col)
                    dep = stop.times_by_flag.get("d", {}).get(col)
                    notes = stop.notes.get(col)
                    if arr is None and dep is None and not notes:
                        continue
                    entry["stops"].append(
                        {
                            "km": stop.km,
                            "station_name": stop.station_name,
                            "arrival": None if arr == "..." else arr,
                            "departure": None if dep == "..." else dep,
                            "notes": notes,
                        }
                    )

    return {"trains": trains, "warnings": warnings, "footnotes_by_page": footnotes_by_page}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("table_pdf")
    ap.add_argument("--input-dir", default="raw_data/tag2026")
    ap.add_argument("--output-dir", default="build_data/tag2026/tables")
    args = ap.parse_args()

    path = Path(args.input_dir) / args.table_pdf
    result = parse_table_pdf(path)

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / (path.stem + ".json")
    out_path.write_text(json.dumps(result, indent=2), encoding="utf-8")

    n_stops = sum(len(t["stops"]) for t in result["trains"].values())
    print(
        f"{path.name}: {len(result['trains'])} train columns, "
        f"{n_stops} total stop-rows, {len(result['warnings'])} warnings, "
        f"{sum(len(v) for v in result['footnotes_by_page'].values())} footnotes"
    )
    for w in result["warnings"][:10]:
        print("  WARN:", w)
    for num, t in list(result["trains"].items())[:3]:
        print(
            f"  {num}: {len(t['stops'])} stops, class={t.get('class')!r}, "
            f"days={t.get('running_days_text')!r}, to_table_no={t.get('to_table_no')!r}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
