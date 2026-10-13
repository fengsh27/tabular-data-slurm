#!/usr/bin/env python3
"""Finalize a PE curation run (Stage 10): combine, relevance, write out.

Given the run's scratch directory (.pe_info_outcome_scratch/<pmid>/) it:
  1. stacks every table_<n>/07_clean.csv (in table order) into outcomes.csv,
     dropping the `Source column` helper (13 columns; exact duplicates once);
  2. builds study_info.csv (one row, 13 columns) from 01_study_design.md and
     02_study_refine.md;
  3. computes "MA relevant" (1 only if all four criteria hold):
       1. Study type includes Pharmacoepidemiology,
       2. Drug name matches a MA_DRUG term,
       3. the study Outcomes or any outcome row's Outcome matches a MA_OUTCOMES term,
       4. some outcome row's Statistics type is an odds / risk / hazard ratio;
     and writes the per-criterion result to 10_ma_relevance.md;
  4. copies the two deliverables to <output>/<pmid>/:
       pe-info-outcome-curation.csv             (outcome values)
       pe-info-outcome-curation.study_info.csv  (study info)
     where <output> is --out-dir, else $SKILL_OUTPUT_FOLDER, else ".".

Terms are `;`-separated and matched case-insensitively as whole words. Defaults:
  MA_DRUG     = oxycodone
  MA_OUTCOMES = neonatal opioid withdrawal syndrome;neonatal abstinence syndrome;NOWS;NAS

Usage:
    python finalize_pe.py .pe_info_outcome_scratch/<pmid> [--out-dir DIR]
        [--ma-drug "a;b"] [--ma-outcomes "x;y"]

Python 3 standard library only.
"""
import argparse
import csv
import glob
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdtable import read_fields  # noqa: E402

SKILL = "pe-info-outcome-curation"
OUTCOME_COLUMNS = [
    "Source location", "Characteristic", "Exposure", "Outcome", "Main value",
    "Main value unit", "Statistics type", "Variation type", "Variation value",
    "Interval type", "Lower bound", "Upper bound", "P value",
]
DESIGN_FIELDS = ["PMID", "Year", "Study type", "Study design", "Data source"]
REFINE_FIELDS = ["Population", "Inclusion criteria", "Exclusion criteria",
                 "Pregnancy stage", "Subject N", "Drug name", "Outcomes"]
STUDY_COLUMNS = DESIGN_FIELDS + REFINE_FIELDS + ["MA relevant"]
DEFAULT_DRUG = "oxycodone"
DEFAULT_OUTCOMES = ("neonatal opioid withdrawal syndrome;neonatal abstinence syndrome;"
                    "NOWS;NAS")
PE_RE = re.compile(r"(?i:pharmaco-?epidemiolog)|\bPE\b")
EFFECT_RE = re.compile(r"odds ratio|risk ratio|relative risk|hazard ratio", re.I)
EFFECT_ABBR_RE = re.compile(r"\b(a|adj\.?\s*)?(OR|RR|HR|IRR|ROR)\b")


def terms(spec):
    return [t.strip() for t in (spec or "").split(";") if t.strip()]


def matches(text, term_list):
    hits = []
    for t in term_list:
        flags = 0 if (t.isupper() and len(t) <= 5) else re.I   # keep NAS ≠ "nasal"
        if re.search(r"(?<!\w)" + re.escape(t) + r"(?!\w)", text or "", flags):
            hits.append(t)
    return hits


def read_field_file(path, wanted):
    if not os.path.exists(path):
        raise SystemExit(f"error: missing {path}")
    got = read_fields(path)
    return {f: (got.get(f.lower()) or "N/A").strip() or "N/A" for f in wanted}


def table_num(path):
    m = re.search(r"table_(\d+)", path)
    return int(m.group(1)) if m else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("scratch", help="the run's .pe_info_outcome_scratch/<pmid> directory")
    ap.add_argument("--out-dir", default=None,
                    help="output root (default: $SKILL_OUTPUT_FOLDER, else '.')")
    ap.add_argument("--ma-drug", default=None, help="override MA_DRUG")
    ap.add_argument("--ma-outcomes", default=None, help="override MA_OUTCOMES")
    args = ap.parse_args(argv)

    scratch = os.path.normpath(args.scratch)
    pmid = os.path.basename(scratch)
    design = read_field_file(os.path.join(scratch, "01_study_design.md"), DESIGN_FIELDS)
    refine = read_field_file(os.path.join(scratch, "02_study_refine.md"), REFINE_FIELDS)

    # 1. outcome rows
    parts = sorted(glob.glob(os.path.join(scratch, "table_*", "07_clean.csv")), key=table_num)
    rows, seen = [], set()
    for p in parts:
        with open(p, encoding="utf-8", newline="") as fh:
            for r in csv.DictReader(fh):
                row = [(r.get(c) or "N/A").strip() or "N/A" for c in OUTCOME_COLUMNS]
                key = tuple(row)
                if key not in seen:
                    seen.add(key)
                    rows.append(row)
    outcomes_csv = os.path.join(scratch, "outcomes.csv")
    with open(outcomes_csv, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(OUTCOME_COLUMNS)
        w.writerows(rows)

    # 3. MA relevance
    drug_terms = terms(args.ma_drug or os.environ.get("MA_DRUG") or DEFAULT_DRUG)
    outcome_terms = terms(args.ma_outcomes or os.environ.get("MA_OUTCOMES") or DEFAULT_OUTCOMES)
    oi, si = OUTCOME_COLUMNS.index("Outcome"), OUTCOME_COLUMNS.index("Statistics type")
    c1 = bool(PE_RE.search(design["Study type"]))
    drug_hits = matches(refine["Drug name"], drug_terms)
    out_hits = matches(refine["Outcomes"], outcome_terms)
    for r in rows:
        out_hits += [h for h in matches(r[oi], outcome_terms) if h not in out_hits]
    stats = sorted({r[si] for r in rows if EFFECT_RE.search(r[si]) or EFFECT_ABBR_RE.search(r[si])})
    checks = [
        ("Study type is Pharmacoepidemiology", c1, design["Study type"]),
        (f"Drug name matches MA_DRUG ({'; '.join(drug_terms)})", bool(drug_hits),
         refine["Drug name"] + (f" — matched: {', '.join(drug_hits)}" if drug_hits else "")),
        (f"Outcome matches MA_OUTCOMES ({'; '.join(outcome_terms)})", bool(out_hits),
         ("matched: " + ", ".join(out_hits)) if out_hits else "no match in study Outcomes or outcome rows"),
        ("Effect estimate is an odds/risk/hazard ratio", bool(stats),
         ", ".join(stats) if stats else "none among the outcome rows"),
    ]
    ma = "1" if all(ok for _, ok, _ in checks) else "0"
    with open(os.path.join(scratch, "10_ma_relevance.md"), "w", encoding="utf-8") as fh:
        fh.write(f"# MA relevance — PMID {pmid}\n\n**MA relevant = {ma}**\n\n")
        fh.write("| # | Criterion | Met | Evidence |\n| --- | --- | --- | --- |\n")
        for i, (name, ok, ev) in enumerate(checks, 1):
            fh.write(f"| {i} | {name} | {'yes' if ok else 'no'} | {ev.replace('|', '/')} |\n")

    # 2. study info
    study = dict(design)
    study.update(refine)
    if study["PMID"] in ("N/A", ""):
        study["PMID"] = pmid
    study["MA relevant"] = ma
    study_csv = os.path.join(scratch, "study_info.csv")
    with open(study_csv, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(STUDY_COLUMNS)
        w.writerow([study[c] for c in STUDY_COLUMNS])

    # 4. write out
    out_root = args.out_dir or os.environ.get("SKILL_OUTPUT_FOLDER") or "."
    dest = os.path.join(out_root, pmid)
    os.makedirs(dest, exist_ok=True)
    d_out = os.path.join(dest, f"{SKILL}.csv")
    d_study = os.path.join(dest, f"{SKILL}.study_info.csv")
    shutil.copyfile(outcomes_csv, d_out)
    shutil.copyfile(study_csv, d_study)

    print(f"tables combined: {len(parts)}  outcome rows: {len(rows)}  MA relevant: {ma}")
    print(f"wrote {os.path.abspath(d_out)}")
    print(f"wrote {os.path.abspath(d_study)}")
    print(f"relevance details: {os.path.join(scratch, '10_ma_relevance.md')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
