#!/usr/bin/env python3
"""Downloads the official IR "Trains at a Glance 2026" (TAG-2026) PDFs.

Dev-time only tool (see docs/RAILWAY_DATABASE.md "Block 6" section) -
never shipped with the app. Re-run any time to refresh the source PDFs;
output goes to raw_data/tag2026/ (gitignored, reproducible not committed).

Source page (confirmed live 2026-09-02):
https://indianrailways.gov.in/railwayboard/view_section.jsp?lang=0&id=0,1,304,366,537,3143

That page's HTML contains a "Select Table No" <select> whose <option>
values are the 97 detailed timetable table PDFs (1.pdf .. 97.pdf, plus a
few lettered/monsoon variants e.g. 26-1.pdf, 27A is embedded inside
27.pdf) - not visible from a naive <a href> link scrape, which only
surfaces the index/category PDFs below. This script re-derives the table
list from that same page live, so a future TAG edition's table count
doesn't need a code change here.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

import requests

BASE = "https://indianrailways.gov.in/railwayboard"
PAGE_URL = f"{BASE}/view_section.jsp?lang=0&id=0,1,304,366,537,3143"
PDF_BASE = f"{BASE}/uploads/directorate/coaching/TAG_2026"
HEADERS = {"User-Agent": "Mozilla/5.0 (TrainYatriDatasetTool/1.0)"}

INDEX_FILES = [
    "How_use.pdf",
    "How2Read.pdf",
    "TableNumberIndex.pdf",
    "Train_Name_Index.pdf",
    "Station_Code_Index.pdf",
    "RoutMap_Table_Index.pdf",
]

CATEGORY_FILES = [
    "Rajdhani_Exp.pdf",
    "Shatabdi_Exp.pdf",
    "Duronto_Exp.pdf",
    "Humsafar_Exp.pdf",
    "Janshatabdi_Exp.pdf",
    "Amrit_Bharat_Trains.pdf",
    "VandeBharatTrains.pdf",
    "TOD_Special_Trains.pdf",
    "Sampark_Kranti_Exp.pdf",
    "AntyodayTrains.pdf",
    "DD.pdf",
    "YuvaTejas_Uday_GatimanTrains.pdf",
    "NamoBharatRapidRail.pdf",
]

OPTION_RE = re.compile(
    r'<option\s+value="([^"]*TAG_2026/([^"/]+\.pdf))"[^>]*>([^<]*)</option>',
    re.IGNORECASE,
)


def discover_table_files(session: requests.Session) -> list[tuple[str, str]]:
    """Returns [(filename, label)] for every "Select Table No" option."""
    resp = session.get(PAGE_URL, headers=HEADERS, timeout=30)
    resp.raise_for_status()
    html = resp.text
    tables = []
    for _url, filename, label in OPTION_RE.findall(html):
        tables.append((filename, label.strip()))
    return tables


def download(session: requests.Session, filename: str, out_dir: Path, force: bool) -> dict:
    dest = out_dir / filename
    if dest.exists() and not force:
        return {"file": filename, "status": "cached", "bytes": dest.stat().st_size}
    url = f"{PDF_BASE}/{filename}"
    resp = session.get(url, headers=HEADERS, timeout=60)
    if resp.status_code != 200 or not resp.content:
        return {"file": filename, "status": f"HTTP {resp.status_code}", "bytes": 0}
    dest.write_bytes(resp.content)
    return {"file": filename, "status": "downloaded", "bytes": len(resp.content)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", default="raw_data/tag2026")
    ap.add_argument("--force", action="store_true", help="Re-download even if cached")
    args = ap.parse_args()

    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    session = requests.Session()
    manifest: dict = {
        "source_page": PAGE_URL,
        "retrieved_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "files": [],
    }

    print("Discovering numbered table PDFs from the live 'Select Table No' dropdown...")
    tables = discover_table_files(session)
    if not tables:
        print(
            "ERROR: found 0 table options in the page HTML - the page structure "
            "may have changed; inspect manually before proceeding.",
            file=sys.stderr,
        )
        return 1
    print(f"Found {len(tables)} numbered table PDFs.")

    all_files = list(INDEX_FILES) + list(CATEGORY_FILES) + [f for f, _ in tables]
    labels = {f: label for f, label in tables}

    for i, filename in enumerate(all_files, 1):
        result = download(session, filename, out_dir, args.force)
        result["label"] = labels.get(filename, "")
        manifest["files"].append(result)
        print(f"[{i}/{len(all_files)}] {filename}: {result['status']} ({result['bytes']} bytes)")
        time.sleep(0.2)  # be polite to a government server

    failed = [f for f in manifest["files"] if f["status"] not in ("downloaded", "cached")]
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"\n{len(manifest['files']) - len(failed)}/{len(all_files)} files OK.")
    if failed:
        print(f"{len(failed)} FAILED:", file=sys.stderr)
        for f in failed:
            print(f"  {f['file']}: {f['status']}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
