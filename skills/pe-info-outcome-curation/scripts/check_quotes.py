#!/usr/bin/env python3
"""Check that the verbatim study-info fields really are verbatim.

Reads Stage 2's 'Field | Value' table and, for each verbatim field (Inclusion
criteria, Exclusion criteria, Outcomes), splits the value on ';' and looks for
every passage in the paper's full text. Matching ignores case, whitespace,
Markdown emphasis, curly vs straight quotes, dash variants and trailing
punctuation — but not wording. For a passage that is not found it prints the
closest stretch of the full text, to help fix it.

Usage:
    python check_quotes.py 02_study_refine.md full_text.md [--fields "A,B"]

Exit code: 0 if every passage is found, 1 if any is not, 2 on usage/IO error.
Python 3 standard library only.
"""
import argparse
import difflib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdtable import read_fields  # noqa: E402

DEFAULT_FIELDS = "Inclusion criteria,Exclusion criteria,Outcomes"

_TRANS = str.maketrans({
    "‘": "'", "’": "'", "“": '"', "”": '"',
    "–": "-", "—": "-", "−": "-", "‐": "-", "‑": "-",
    " ": " ", " ": " ", " ": " ",
})


def norm(text):
    text = text.translate(_TRANS).lower()
    text = re.sub(r"[*_`]+", "", text)           # markdown emphasis
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def closest(passage, haystack):
    """The sentence (or pair of sentences) of the paper sharing the most words."""
    want = re.findall(r"\w+", passage)
    if not want:
        return "(nothing to compare)"
    sents = [x for x in re.split(r"(?<=[.;:!?])\s+", haystack) if x.strip()]
    windows = sents + [a + " " + b for a, b in zip(sents, sents[1:])]
    best, best_score = "", 0.0
    for w in windows:
        words = re.findall(r"\w+", w)
        if not words:
            continue
        score = difflib.SequenceMatcher(None, want, words, autojunk=False).ratio()
        if score > best_score:
            best, best_score = w, score
    if best_score < 0.2:
        return "(no similar sentence found — the article may not say this)"
    return best if len(best) <= 400 else best[:400] + "…"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("fields_md", help="Stage 2 output (Field | Value table)")
    ap.add_argument("full_text", help="the paper's full text (full_text.md)")
    ap.add_argument("--fields", default=DEFAULT_FIELDS,
                    help=f"comma-separated verbatim fields (default: {DEFAULT_FIELDS})")
    args = ap.parse_args(argv)

    try:
        fields = read_fields(args.fields_md)
        with open(args.full_text, encoding="utf-8") as fh:
            hay = norm(fh.read())
    except (OSError, SystemExit) as e:
        print(f"error: {e}", file=sys.stderr)
        return 2

    print("# Verbatim check of study-info fields\n")
    n_total = n_missing = n_found = 0
    for name in [f.strip() for f in args.fields.split(",") if f.strip()]:
        value = fields.get(name.lower())
        print(f"## {name}\n")
        if value is None:
            print("- **FIELD MISSING** from the Stage 2 table\n")
            n_missing += 1
            continue
        if norm(value) in ("n/a", "na", ""):
            print("- N/A (not checked)\n")
            continue
        for passage in [p.strip() for p in value.split(";") if p.strip()]:
            n_total += 1
            key = norm(passage).rstrip(" .,:;")
            if key and key in hay:
                n_found += 1
                print(f"- found: \"{passage}\"")
            else:
                n_missing += 1
                print(f"- **NOT FOUND**: \"{passage}\"")
                print(f"  - closest text in the paper: \"{closest(key, hay)}\"")
        print()

    print(f"**Summary**: {n_found}/{n_total} passages found; "
          f"{n_missing} problem(s) (passages not found or fields missing).")
    return 1 if n_missing else 0


if __name__ == "__main__":
    sys.exit(main())
