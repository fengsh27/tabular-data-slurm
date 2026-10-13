#!/usr/bin/env python3
"""Deterministic cleanup of one table's extracted PE outcome rows (Stage 7).

Input is Stage 6's Markdown table with the 14 working columns (the 13 outcome
columns + the `Source column` helper). The script:
  1. parses the table and reports rows with the wrong number of cells;
  2. normalizes empty / "-" / "none" / "nan" / "unknown" / "na" cells to "N/A";
  3. moves an interval written into Variation value ("1.1-15.8", "1.1 to 15.8")
     into Lower bound / Upper bound when the variation type names an interval
     (CI / IQR / range) and the bounds are empty — a split, never a calculation;
  4. drops exact duplicate rows;
  5. writes a 14-column CSV (every cell a string) and a report that FLAGS, without
     changing, rows needing judgment: Statistics type N/A, a statistic used as the
     unit, a bare number as Outcome, a table/figure name in Characteristic, an
     unknown Source column, an interval left in Variation value.

Usage:
    python clean_pe_outcome_rows.py 06_rows.md --table 00_markdown_table.md \\
        -o 07_clean.csv --report 07_cleanup_report.md

Exit code: 0 when the CSV was written (flags may still exist — read the report),
2 on malformed input (rows with the wrong cell count; nothing written).
Python 3 standard library only.
"""
import argparse
import csv
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdtable import read_first_table  # noqa: E402

COLUMNS = [
    "Source location", "Characteristic", "Exposure", "Outcome", "Main value",
    "Main value unit", "Statistics type", "Variation type", "Variation value",
    "Interval type", "Lower bound", "Upper bound", "P value", "Source column",
]
NA_TOKENS = {"", "-", "—", "–", "none", "nan", "null", "unknown", "na", "n/a", "n.a."}
STAT_UNITS = {"sd", "se", "sem", "s.d.", "iqr", "ci", "95% ci", "95%ci", "range",
              "standard deviation", "standard error", "mean", "median",
              "interquartile range", "confidence interval"}
INTERVAL_WORDS = re.compile(r"\bci\b|confidence|iqr|interquartile|range", re.I)
NUM = r"[-−]?\d[\d.,]*"
INTERVAL_RE = re.compile(rf"^\s*\(?\s*({NUM})\s*(?:–|—|-|to)\s*({NUM})\s*\)?\s*$")
BARE_NUMBER_RE = re.compile(r"^[\d\s.,%<>=±()+−-]+$")
TABLE_NAME_RE = re.compile(r"\b(table|figure|fig\.?)\s*\d", re.I)


def norm_header(h):
    return re.sub(r"\s+", " ", h).strip().lower()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("rows_md", help="Stage 6 output (14-column Markdown table)")
    ap.add_argument("--table", help="the source 00_markdown_table.md (to check Source column)")
    ap.add_argument("-o", "--output", required=True, help="output CSV")
    ap.add_argument("--report", required=True, help="output report (Markdown)")
    args = ap.parse_args(argv)

    header, rows, _ = read_first_table(args.rows_md)
    idx = {norm_header(h): i for i, h in enumerate(header)}
    missing = [c for c in COLUMNS if c.lower() not in idx]
    if missing:
        msg = f"error: {args.rows_md} is missing column(s): {', '.join(missing)}"
        print(msg, file=sys.stderr)
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write(f"# Cleanup report\n\n**{msg}**\n")
        return 2

    bad = [(ln, len(cells)) for ln, cells in rows if len(cells) != len(header)]
    if bad:
        with open(args.report, "w", encoding="utf-8") as fh:
            fh.write("# Cleanup report\n\n**Malformed rows — fix these in the input and re-run "
                     "(nothing was written):**\n\n")
            for ln, n in bad:
                fh.write(f"- line {ln}: {n} cells, expected {len(header)}\n")
        print(f"error: {len(bad)} malformed row(s); see {args.report}", file=sys.stderr)
        return 2

    table_cols = None
    if args.table:
        t_header, _, _ = read_first_table(args.table)
        table_cols = set(t_header)

    out, seen, flags, moved, dupes = [], set(), [], 0, 0
    for n, (ln, cells) in enumerate(rows, 1):
        r = {c: cells[idx[c.lower()]].strip() for c in COLUMNS}
        for c in COLUMNS:
            if r[c].lower() in NA_TOKENS:
                r[c] = "N/A"

        m = INTERVAL_RE.match(r["Variation value"]) if r["Variation value"] != "N/A" else None
        if m:
            vt, it = r["Variation type"], r["Interval type"]
            looks_interval = INTERVAL_WORDS.search(vt) or (it != "N/A" and vt == "N/A")
            if looks_interval and r["Lower bound"] == "N/A" and r["Upper bound"] == "N/A":
                if it == "N/A":
                    r["Interval type"] = vt
                r["Lower bound"], r["Upper bound"] = m.group(1), m.group(2)
                r["Variation type"] = r["Variation value"] = "N/A"
                moved += 1
            else:
                flags.append((ln, "interval-like value left in Variation value", r["Variation value"]))

        if r["Statistics type"] == "N/A":
            flags.append((ln, "Statistics type is N/A (required)", ""))
        if r["Main value unit"].lower() in STAT_UNITS:
            flags.append((ln, "Main value unit is a statistic, not a unit", r["Main value unit"]))
        if r["Outcome"] == "N/A" or BARE_NUMBER_RE.match(r["Outcome"]):
            flags.append((ln, "Outcome is empty or a bare number", r["Outcome"]))
        if TABLE_NAME_RE.search(r["Characteristic"]):
            flags.append((ln, "Characteristic names a table/figure", r["Characteristic"]))
        if table_cols is not None and r["Source column"] not in table_cols:
            flags.append((ln, "Source column is not a column of the table", r["Source column"]))

        key = tuple(r[c] for c in COLUMNS)
        if key in seen:
            dupes += 1
            continue
        seen.add(key)
        out.append(r)

    with open(args.output, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(COLUMNS)
        for r in out:
            w.writerow([r[c] for c in COLUMNS])

    with open(args.report, "w", encoding="utf-8") as fh:
        fh.write("# Cleanup report\n\n")
        fh.write(f"- input rows: {len(rows)}\n- output rows: {len(out)}\n"
                 f"- duplicate rows dropped: {dupes}\n"
                 f"- intervals moved from Variation value to bounds: {moved}\n"
                 f"- flags: {len(flags)}\n\n")
        if flags:
            fh.write("## Flags (fix in the input from the source table, then re-run once)\n\n")
            fh.write("| Input line | Issue | Cell |\n| --- | --- | --- |\n")
            for ln, issue, cell in flags:
                fh.write(f"| {ln} | {issue} | {cell.replace('|', '/')} |\n")
        else:
            fh.write("No flags.\n")
    print(f"wrote {args.output} ({len(out)} rows, {len(flags)} flag(s)); report: {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
