#!/usr/bin/env python3
"""Regenerate NAICS 2022 full JSON from the Census Bureau's official XLSX.

Usage: python3 script/regenerate_naics.py [output_path]

Downloads the Census Bureau's 2022 NAICS Structure XLSX, parses it, and
writes the full NAICS dictionary JSON to the given output path (defaults to
lib/contractkit/data/naics_2022_full.json relative to the repo root).
"""

import json
import sys
import urllib.request
from pathlib import Path

CENSUS_URL = "https://www.census.gov/naics/2022NAICS/2022_NAICS_Structure.xlsx"

# Sector groupings where the Census file omits 2-digit sector rows.
# Codes 31-33 are "Manufacturing", 44-45 are "Retail Trade",
# 48-49 are "Transportation and Warehousing".
GROUPED_SECTORS = {
    "31": "Manufacturing",
    "32": "Manufacturing",
    "33": "Manufacturing",
    "44": "Retail Trade",
    "45": "Retail Trade",
    "48": "Transportation and Warehousing",
    "49": "Transportation and Warehousing",
}

GROUPED_RANGES = [("31", "33"), ("44", "45"), ("48", "49")]


def in_grouped_range(prefix: str) -> bool:
    for lo, hi in GROUPED_RANGES:
        if lo <= prefix <= hi:
            return True
    return False


def regenerate(output_path: Path) -> None:
    import openpyxl

    # Download
    req = urllib.request.Request(CENSUS_URL, headers={
        "User-Agent": "Mozilla/5.0 (compatible; contractkit-naics-seed)"
    })
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read()

    # Parse
    wb = openpyxl.load_workbook(
        __import__("io").BytesIO(raw), data_only=True
    )
    ws = wb["2022 NAICS Structure"]

    sectors = {}
    subsectors = {}
    entries = []

    current_sector_code = None
    current_sector_title = None
    current_subsector_code = None
    current_subsector_title = None

    for row in ws.iter_rows(min_row=4, values_only=True):
        code = str(row[1]).strip() if row[1] else ""
        title = str(row[2]).strip() if row[2] else ""

        if not code:
            continue

        title = title.rstrip("T").strip()

        if len(code) == 2:
            current_sector_code = code
            current_sector_title = title
            sectors[code] = title
            current_subsector_code = None
            current_subsector_title = None
        elif len(code) == 3:
            current_subsector_code = code
            current_subsector_title = title
            subsectors[code] = title
        elif len(code) == 6:
            prefix = code[:2]
            if in_grouped_range(prefix):
                sc = prefix
            else:
                sc = current_sector_code

            entries.append({
                "code": code,
                "title": title,
                "sector_code": sc,
                "subsector_code": current_subsector_code,
            })

    # Backfill grouped sector titles
    for k, v in GROUPED_SECTORS.items():
        if k not in sectors:
            sectors[k] = v

    output = {
        "_meta": {
            "version": "NAICS 2022",
            "scope": (
                "Full NAICS 2022 coverage — all "
                f"{len(entries)} 6-digit codes with sector and subsector parents."
            ),
            "source": f"U.S. Census Bureau 2022 NAICS Structure file ({CENSUS_URL})",
            "regenerate_with": "rake naics:seed",
        },
        "sectors": {k: sectors[k] for k in sorted(sectors.keys())},
        "subsectors": {k: subsectors[k] for k in sorted(subsectors.keys())},
        "entries": entries,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(output, f, indent=2)

    print(f"Wrote {len(entries)} NAICS entries to {output_path}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        out = Path(sys.argv[1])
    else:
        # Assume we're run from the repo root
        out = Path("lib/contractkit/data/naics_2022_full.json")
    regenerate(out)
