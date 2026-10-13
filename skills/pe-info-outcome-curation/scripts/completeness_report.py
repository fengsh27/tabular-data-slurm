#!/usr/bin/env python3
"""Completeness report for one table (Stage 8): rows produced per source column.

Compares Stage 4's column inventory with the rows in Stage 7's CSV (via the
`Source column` helper) and prints, for every inventory column, its Row kind and
how many rows came from it. Flags columns expected to produce rows that produced
none, and rows whose Source column is not in the inventory. A report only.

Usage:
    python completeness_report.py 04_inventory.md 07_clean.csv

Exit code: 0 when nothing is flagged, 1 when something is, 2 on usage/IO error.
Python 3 standard library only.
"""
import csv
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdtable import read_first_table  # noqa: E402


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    inv_path, csv_path = argv
    header, rows, _ = read_first_table(inv_path)
    h = [c.strip().lower() for c in header]
    try:
        ci, ki = h.index("column"), h.index("row kind")
    except ValueError:
        print(f"error: {inv_path} needs 'Column' and 'Row kind' columns", file=sys.stderr)
        return 2
    inventory = [(cells[ci], cells[ki]) for _, cells in rows if len(cells) > max(ci, ki)]

    with open(csv_path, encoding="utf-8", newline="") as fh:
        data = list(csv.DictReader(fh))
    counts = Counter(r.get("Source column", "") for r in data)

    flagged = 0
    print("# Completeness report\n")
    print(f"Rows in {os.path.basename(csv_path)}: {len(data)}\n")
    print("| Column | Row kind | Rows produced | Flag |\n| --- | --- | --- | --- |")
    known = set()
    for col, kind in inventory:
        known.add(col)
        n = counts.get(col, 0)
        flag = ""
        if n == 0 and kind.strip().lower() not in ("not applicable", "n/a"):
            flag = "NO ROWS — explain why below"
            flagged += 1
        print(f"| {col} | {kind} | {n} | {flag} |")

    stray = {c: n for c, n in counts.items() if c not in known}
    if stray:
        flagged += 1
        print("\n**Rows whose Source column is not in the inventory:**\n")
        for c, n in stray.items():
            print(f"- `{c or '(empty)'}`: {n} row(s)")
    print(f"\n**Summary**: {len(inventory)} columns, {flagged} flag(s).")
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main())
