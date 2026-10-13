#!/usr/bin/env python3
"""List a prepared paper's tables to help choose the outcome tables (Stage 3).

For each table_<n>.md in a pk-pe-prepare output folder it prints the caption,
size, column headers and the first row labels, and flags:
  - DUPLICATE of table_k : the same table (caption + Markdown table) printed again;
  - baseline?            : the caption or labels look like baseline/demographics
                           (a hint only — read the table to decide).

Usage:
    python list_tables.py .paper_assets/<pmid>

Python 3 standard library only.
"""
import glob
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdtable import read_tables  # noqa: E402

BASELINE_RE = re.compile(
    r"baseline|demograph|characteristics of (the )?(study )?(participants|patients|"
    r"subjects|women|mothers|cohort)|patient characteristics|maternal characteristics|"
    r"standardi[sz]ed (mean )?difference|covariate balance", re.I)


def parse_table_md(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    head, _, rest = text.partition("**Table:**")
    head_lines = [l for l in head.splitlines() if l.strip() and not l.startswith("# Table")]
    caption_lines, footnotes, in_fn = [], [], False
    for l in head_lines:
        if l.strip() == "**Footnotes:**":
            in_fn = True
        elif in_fn:
            footnotes.append(l.lstrip("- ").strip())
        else:
            caption_lines.append(l.strip())
    tables = read_tables(rest)
    return " ".join(caption_lines), footnotes, (tables[0] if tables else None), rest.strip()


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    assets = argv[0]
    paths = sorted(glob.glob(os.path.join(assets, "table_*.md")),
                   key=lambda p: int(re.search(r"table_(\d+)\.md$", p).group(1)))
    title = ""
    man = os.path.join(assets, "manifest.json")
    if os.path.exists(man):
        with open(man, encoding="utf-8") as fh:
            title = json.load(fh).get("title") or ""

    print(f"# Tables in {os.path.basename(os.path.normpath(assets))}\n")
    if title:
        print(f"Paper title: {title}\n")
    if not paths:
        print("No tables found.")
        return 0

    seen = {}
    for p in paths:
        label = os.path.splitext(os.path.basename(p))[0]
        caption, footnotes, table, raw = parse_table_md(p)
        digest = hashlib.sha1((caption + "\n" + raw).encode("utf-8")).hexdigest()
        flags = []
        if digest in seen:
            flags.append(f"DUPLICATE of {seen[digest]}")
        else:
            seen[digest] = label
        labels = []
        if table:
            header, rows, _ = table
            labels = [cells[0] for _, cells in rows if cells and cells[0]][:8]
        if BASELINE_RE.search(caption) or any(BASELINE_RE.search(x) for x in labels):
            flags.append("baseline?")

        print(f"## {label}" + (f"  [{'; '.join(flags)}]" if flags else ""))
        print(f"- Caption: {caption or '(none)'}")
        if table:
            header, rows, _ = table
            print(f"- Size: {len(rows)} rows x {len(header)} columns")
            print(f"- Columns: {' | '.join(header)}")
            if labels:
                print(f"- First row labels: {'; '.join(labels)}")
        else:
            print("- (no Markdown table body)")
        if footnotes:
            fn = " ".join(footnotes)
            print(f"- Footnotes: {fn[:300]}{'…' if len(fn) > 300 else ''}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
