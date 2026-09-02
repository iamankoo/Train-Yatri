"""Shared word-position column-binning helpers for TAG-2026 PDF parsing.

The TAG-2026 PDFs are real tables (station/train-number index lists, and
station-rows x train-columns timetable matrices) but pdfplumber's own
`extract_tables()` misdetects column boundaries on them (verified: it
merges/splits digits across columns on `TableNumberIndex.pdf`, since
these tables have no visible cell borders for it to key off). Plain
`extract_text()` loses column identity entirely whenever a row has a
skipped/blank cell (verified on `1.pdf`: consecutive blank cells drop
tokens rather than emitting a placeholder, so linear reading order no
longer lines up with the header's column order).

The reliable approach (verified against real pages of both file types):
use `page.extract_words()` for real (x, y) positions, derive column
boundaries from the header row's own word positions, then bin every
subsequent word by which column boundary range its x0 falls in. Row
identity is recovered by clustering word y-positions.
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Word:
    text: str
    x0: float
    x1: float
    top: float
    bottom: float


def get_words(page) -> list[Word]:
    return [
        Word(w["text"], w["x0"], w["x1"], w["top"], w["bottom"])
        for w in page.extract_words(use_text_flow=False, keep_blank_chars=False)
    ]


def get_words_from_chars(page, gap_threshold: float = 1.5) -> list[Word]:
    """A from-scratch word builder, used instead of `get_words` for the
    detailed timetable tables' matrix body.

    Verified necessary on real data: `page.extract_words()` corrupts
    text where two sub-rows sit very close together vertically (the
    "a"/"d" arrival/departure stacked pair, ~6pt apart) - it sometimes
    fails to merge a time value's own digits into one word (e.g. "06.00"
    coming back as five separate one-character "words": '0','6','.',
    '0','0'), apparently from inconsistent internal row-clustering
    across the two close sub-rows. Characters on the same source text
    line share the *exact* same `top` (confirmed: not fuzzy, identical
    to 2 decimal places), so grouping by exact `top` first - before
    doing any x-gap word-merging - sidesteps that entirely.
    """
    # Round to the nearest 0.5pt, not the nearest 0.1pt: verified on real
    # data that two words belonging to the *same* visual row can differ
    # in exact `top` by ~0.1-0.3pt (distinct text-flow columns rendered
    # with slightly different baselines), which used to split one row
    # into two spurious "lines" - while genuinely distinct stacked rows
    # (e.g. an 'a'/'d' arrival/departure pair) are always >=3pt apart, so
    # 0.5pt rounding cannot accidentally merge those.
    chars = [c for c in page.chars if c.get("text", "") != ""]
    lines: dict[float, list[dict]] = {}
    for c in chars:
        lines.setdefault(round(c["top"] * 2) / 2, []).append(c)

    words: list[Word] = []
    for top, line_chars in lines.items():
        line_chars.sort(key=lambda c: c["x0"])
        current: list[dict] = []
        prev_x1: float | None = None
        for c in line_chars:
            if c["text"].isspace():
                if current:
                    words.append(_word_from_chars(current, top))
                    current = []
                prev_x1 = None
                continue
            if prev_x1 is not None and c["x0"] - prev_x1 > gap_threshold:
                if current:
                    words.append(_word_from_chars(current, top))
                current = []
            current.append(c)
            prev_x1 = c["x1"]
        if current:
            words.append(_word_from_chars(current, top))
    return words


def _word_from_chars(chars: list[dict], line_top: float) -> Word:
    text = "".join(c["text"] for c in chars)
    return Word(
        text=text,
        x0=chars[0]["x0"],
        x1=chars[-1]["x1"],
        top=line_top,
        bottom=chars[0]["bottom"],
    )


def cluster_1d(values: list[float], gap: float) -> list[list[float]]:
    """Groups sorted values into clusters separated by > gap."""
    if not values:
        return []
    values = sorted(values)
    clusters = [[values[0]]]
    for v in values[1:]:
        if v - clusters[-1][-1] > gap:
            clusters.append([v])
        else:
            clusters[-1].append(v)
    return clusters


def column_boundaries(anchor_x0s: list[float], page_width: float) -> list[float]:
    """Given N sorted column-header x0 anchors, returns N+1 boundaries
    (midpoints between consecutive anchors, plus 0 and page_width) such
    that boundaries[i] <= x0 < boundaries[i+1] assigns a word to column i.
    """
    anchors = sorted(anchor_x0s)
    bounds = [0.0]
    for a, b in zip(anchors, anchors[1:]):
        bounds.append((a + b) / 2)
    bounds.append(page_width + 1)
    return bounds


def bin_column(x0: float, boundaries: list[float]) -> int:
    for i in range(len(boundaries) - 1):
        if boundaries[i] <= x0 < boundaries[i + 1]:
            return i
    return len(boundaries) - 2


@dataclass
class Row:
    """One reconstructed logical row: column index -> list of Words,
    in reading order, possibly spanning several source lines (a wrapped
    station/train name)."""

    cells: dict[int, list[Word]] = field(default_factory=dict)

    def text(self, col: int, sep: str = " ") -> str:
        words = self.cells.get(col, [])
        return sep.join(w.text for w in words).strip()

    def all_words(self) -> list[Word]:
        out: list[Word] = []
        for ws in self.cells.values():
            out.extend(ws)
        return out


def group_rows_by_y(words: list[Word], y_gap: float = 3.0) -> list[list[Word]]:
    """Groups words into visual lines by `top` proximity. Returns lines
    in top-to-bottom order, each a list of words in left-to-right order.
    """
    if not words:
        return []
    ws = sorted(words, key=lambda w: (w.top, w.x0))
    lines: list[list[Word]] = [[ws[0]]]
    for w in ws[1:]:
        if w.top - lines[-1][-1].top > y_gap:
            lines.append([w])
        else:
            lines[-1].append(w)
    for line in lines:
        line.sort(key=lambda w: w.x0)
    return lines
