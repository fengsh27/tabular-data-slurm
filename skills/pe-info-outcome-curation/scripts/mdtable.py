#!/usr/bin/env python3
"""Minimal Markdown pipe-table reader shared by this skill's scripts.

Only GitHub-style pipe tables are recognised: a header line, a separator line of
dashes, then body lines, each starting with "|". An escaped pipe ("\\|") inside a
cell is kept as a literal "|". Python 3 standard library only.
"""
import re

_SEP_CELL = re.compile(r"^:?-{2,}:?$")


def split_row(line):
    """Split one '| a | b |' line into stripped cells."""
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|") and not line.endswith("\\|"):
        line = line[:-1]
    cells = re.split(r"(?<!\\)\|", line)
    return [c.replace("\\|", "|").strip() for c in cells]


def _is_separator(cells):
    return bool(cells) and all(_SEP_CELL.match(c.replace(" ", "")) for c in cells if c) \
        and any(cells)


def read_tables(text):
    """Return every pipe table in `text` as (header, rows, first_line_no)."""
    lines = text.splitlines()
    tables = []
    i = 0
    while i < len(lines) - 1:
        if lines[i].lstrip().startswith("|") and lines[i + 1].lstrip().startswith("|") \
                and _is_separator(split_row(lines[i + 1])):
            header = split_row(lines[i])
            start = i + 1
            rows = []
            j = i + 2
            while j < len(lines) and lines[j].lstrip().startswith("|"):
                rows.append((j + 1, split_row(lines[j])))
                j += 1
            tables.append((header, rows, start))
            i = j
        else:
            i += 1
    return tables


def read_first_table(path):
    with open(path, encoding="utf-8") as fh:
        tables = read_tables(fh.read())
    if not tables:
        raise SystemExit(f"error: no Markdown table found in {path}")
    return tables[0]


def read_fields(path):
    """Read a two-column 'Field | Value' table into an ordered dict-like list."""
    header, rows, _ = read_first_table(path)
    out = {}
    for _, cells in rows:
        if len(cells) >= 2 and cells[0]:
            out[cells[0].strip().lower()] = " | ".join(cells[1:]).strip()
    return out
