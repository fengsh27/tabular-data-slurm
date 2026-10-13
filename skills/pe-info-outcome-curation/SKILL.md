---
name: pe-info-outcome-curation
description: Curate a pharmacoepidemiology (PE) paper (prepared from HTML or JATS XML) into two datasets — a one-row study-info sheet (PMID, year, study type/design, data source, population, verbatim inclusion/exclusion criteria, pregnancy stage, subject N, drug, outcomes, meta-analysis relevance) and a 13-column outcome-values table (one row per reported outcome value from the outcome tables, with effect estimates, counts, intervals and p-values). Use for PE / observational / clinical-outcome studies; for pharmacokinetic tables use pk-summary-curation or pk-individual-curation.
---

> **Self-contained skill.** Every `scripts/…`, `prompts/…` and `verify_and_correct.md` path named below lives in **this skill's own directory**. This skill shares nothing with other skills — when run as an installed skill, resolve these paths under this skill's folder.

> **Working-directory base (read this first).** Every `./.…` path this skill uses below — the prepared inputs in `./.paper_assets/<pmid>/` and the `./.pe_info_outcome_scratch/<pmid>/` intermediates this skill writes — is relative to one base directory. Resolve it **once, before any file operation**: if the environment variable `SKILL_SCRATCH_FOLDER` is set (run `echo "$SKILL_SCRATCH_FOLDER"` to check), that is the base — write to `"$SKILL_SCRATCH_FOLDER"/.pe_info_outcome_scratch/<pmid>/` and read from `"$SKILL_SCRATCH_FOLDER"/.paper_assets/<pmid>/`. Otherwise the base is the user's current working directory (use the paths exactly as written below). Create directories with `mkdir -p` and keep the same base for every read and write.

# PE Info + Outcome Curation

Implements the PE extraction protocol (parts A, B, "A and B" relevance, and C&D)
for papers in **HTML or JATS XML**, prepared by the `pk-pe-prepare` skill. It
produces two deliverables for one paper:

1. **Study info** — one row describing the study (parts A, B, relevance).
2. **Outcome values** — one row per reported outcome value from the paper's
   outcome tables (part C&D).

## Inputs you need
The paper must already be prepared by `pk-pe-prepare`, giving
`./.paper_assets/<pmid>/` (rooted at `$SKILL_SCRATCH_FOLDER` when set):
- `paper_text.md` — full text (title + body, references stripped, tables
  replaced by `[Table N]` markers),
- `abstract.md` — the abstract (may be missing),
- `table_<n>.md` — each table's caption, footnotes and the table as Markdown,
- `manifest.json` — table list, title, and `year` (publication year, or `null`).

If the paper is not prepared, prepare it first with `pk-pe-prepare`. If the user
names specific tables to extract (e.g. "tables 2 and 4"), use exactly those in
Stage 3. This skill does not fetch papers.

**Settings (environment variables, optional)** — read them once with `echo`:
- `MA_DRUG` — drug term(s) for the meta-analysis relevance check, `;`-separated.
  Default: `oxycodone`.
- `MA_OUTCOMES` — outcome term(s) for the relevance check, `;`-separated.
  Default: `neonatal opioid withdrawal syndrome;neonatal abstinence syndrome;NOWS;NAS`.
The finalize script (Stage 10) reads these itself; you do not need to pass them.

## Output schemas

**Study info** — one row, 13 columns, in this order:
`PMID, Year, Study type, Study design, Data source, Population, Inclusion criteria,
Exclusion criteria, Pregnancy stage, Subject N, Drug name, Outcomes, MA relevant`

**Outcome values** — one row per reported value, 13 columns, in this order:

| # | Column | Meaning |
|---|---|---|
| 1 | Source location | where the value appears: `Table 2`, `Table 4` (provenance only) |
| 2 | Characteristic | the overall study population; for a subgroup `[Overall population]; [Subgroup]` — never a table name |
| 3 | Exposure | the exposure the value belongs to (drug, condition, comparison group) |
| 4 | Outcome | what the value measures — never the number itself |
| 5 | Main value | the reported value, copied exactly (not a range) |
| 6 | Main value unit | unit (`kg`, `mmHg`, `Count`, …) — never a statistic such as SD |
| 7 | Statistics type | what Main value is, incl. crude/adjusted: `Adjusted odds ratio`, `Sum`, `Median`, … — required |
| 8 | Variation type | `SD`, `%`, … |
| 9 | Variation value | its single value |
| 10 | Interval type | `95% CI`, `IQR`, `Range`, … |
| 11 | Lower bound | lower end of the interval |
| 12 | Upper bound | upper end of the interval |
| 13 | P value | the p-value that applies to this row, copied exactly |

Every cell is a string; use `"N/A"` when a cell cannot be filled.

## Scope (outcome values)
Extract only values that bear on an **outcome**: (a) effect estimates for an
outcome, crude or adjusted; (b) event counts, percentages or summary statistics of
an outcome in a group; (c) group sizes/denominators needed to interpret them,
wherever they appear (column header, row header, caption).
**Out of scope**: baseline demographic and clinical characteristics (age, BMI,
parity, smoking, comorbidities, baseline medication), covariate-balance statistics
(standardised mean differences, matching diagnostics), and anything describing
the study population rather than an outcome — unless the article also analyses
that characteristic as an outcome.
**Tables only**: values reported only in the running text or only inside a figure
image are not extracted (figures in HTML/XML are images; only their captions are
text). Mention any outcome you noticed in the text but could not extract.

## Scratch directory (state between stages)
Persist each stage's output to a file and read it back when the next stage needs
it — never rely on the conversation alone (a long run can be summarized, which
corrupts the exact text later stages depend on). Create the scratch directory in
the working base — **never inside this skill's folder**:

```
.pe_info_outcome_scratch/<pmid>/
├── full_text.md               # copy of paper_text.md (abstract appended if present)
├── 01_study_design.md         # Stage 1  Field | Value  (5 fields)
├── 02_study_refine.md         # Stage 2  Field | Value  (7 fields)
├── 02_quote_check.md          # Stage 2  script report on verbatim criteria
├── 03_tables.md               # Stage 3  script listing of all tables
├── 03_selection.md            # Stage 3  selected outcome tables + reasoning
├── table_<n>/                 # one sub-directory PER SELECTED table
│   ├── 00_markdown_table.md   # the table as Markdown
│   ├── inputs.md              # caption + footnotes + paper title, verbatim
│   ├── 04_inventory.md        # Stage 4  column inventory
│   ├── 05_rows.md             # Stage 5  extracted rows (14 cols incl. Source column)
│   ├── 06_rows.md             # Stage 6  rows with p-values + footnotes applied
│   ├── 07_clean.csv           # Stage 7  script output (corrected in place by Stage 9)
│   ├── 07_cleanup_report.md   # Stage 7  script flags
│   ├── 08_completeness.md     # Stage 8  completeness report
│   └── 09_verification_report.md  # Stage 9
├── outcomes.csv               # Stage 10 all tables combined (13 cols)
├── study_info.csv             # Stage 10 the one-row study info (13 cols)
└── 10_ma_relevance.md         # Stage 10 which relevance criteria passed
```

## Procedure
Run the stages **in order**. For each stage: read its input files and its prompt
file, reason explicitly, produce the output, run the stage's checks (redo the
stage **once** if a check fails, then carry on and note any residual issue), and
**write** the output to its scratch file before moving on.

0. **Set up** — create the scratch directory; copy `paper_text.md` to
   `full_text.md`, appending `abstract.md` under a `## Abstract` heading if it
   exists. Read `manifest.json`.

### Part 1 — Study info (from the full text)
1. **Study design** — `prompts/01_study_design.md` → `01_study_design.md`
   (PMID, Year, Study type, Study design, Data source).
2. **Study refine** — `prompts/02_study_refine.md` → `02_study_refine.md`
   (Population, Inclusion criteria, Exclusion criteria, Pregnancy stage,
   Subject N, Drug name, Outcomes), then run `scripts/check_quotes.py` to prove
   the criteria are verbatim → `02_quote_check.md`.

### Part 2 — Outcome values (from the tables)
3. **Select outcome tables** — `prompts/03_select_tables.md`: run
   `scripts/list_tables.py` → `03_tables.md`, then choose → `03_selection.md`.
   If no table holds outcome values, write that in `03_selection.md`, skip to
   Stage 10 (it writes an empty outcome file), and say so.
4. **For each selected table**, in its own `table_<n>/`, run stages 4–9:
   - 4. **Column inventory** — `prompts/04_column_inventory.md` → `04_inventory.md`
   - 5. **Extract rows, column by column** — `prompts/05_extract_rows.md` → `05_rows.md`
   - 6. **P values + footnotes** — `prompts/06_pvalues_footnotes.md` → `06_rows.md`
   - 7. **Row cleanup** (script) — `prompts/07_row_cleanup.md` → `07_clean.csv`
   - 8. **Completeness check** (script + note) — `prompts/08_completeness.md` → `08_completeness.md`
   - 9. **Verify + correct** — `prompts/09_verify_and_correct.md` → corrects
     `07_clean.csv`, writes `09_verification_report.md`

### Part 3 — Combine, relevance, write out
10. **Finalize** (script) — `prompts/10_finalize.md`: run
    `scripts/finalize_pe.py`, which combines every `table_*/07_clean.csv` into
    `outcomes.csv`, builds `study_info.csv`, computes **MA relevant**, writes
    `10_ma_relevance.md`, and copies both deliverables to the output folder.

## Validation (before Stage 10)
- `01_study_design.md` and `02_study_refine.md` hold every field (value or `N/A`).
- `02_quote_check.md` shows no unmatched criteria passage, or each remaining one
  is reported as unresolved.
- Each `07_clean.csv` has the 14 working columns, every row has a non-`N/A`
  `Statistics type`, and no `Outcome` is a bare number.

## Error handling rules
- **Paper not prepared** — prepare it with `pk-pe-prepare` first; do not parse
  HTML/XML by hand.
- **No outcome tables** — still produce the study info; the outcome file is
  header-only. Say so.
- **Duplicate tables** (the same table printed twice, flagged by
  `list_tables.py`) — select only the first copy.
- **A value suppressed / masked / reported as NA** — still produce its row with
  `Main value` = `N/A` and the reason in `Characteristic`.
- **Malformed rows** (wrong cell count) reported by the cleanup script — fix them
  in `06_rows.md` and re-run the script once.

## What this skill deliberately does NOT do
- It does not fetch papers or read PDFs — input is a prepared HTML/XML paper.
- It does not extract values that appear only in running text or figure images.
- It does not calculate anything — every value is copied as printed.
- Its verify → correct loop is **bounded** (≤2 rounds); remaining issues are
  reported, not endlessly retried.
- It does not score itself against a gold standard.

## Write out the result (do this last)
Stage 10's script copies the deliverables for you:
- `$SKILL_OUTPUT_FOLDER/<pmid>/pe-info-outcome-curation.csv` — outcome values,
- `$SKILL_OUTPUT_FOLDER/<pmid>/pe-info-outcome-curation.study_info.csv` — study info,

(`./<pmid>/…` when `SKILL_OUTPUT_FOLDER` is unset). If the user asks for an Excel
file, also run `python scripts/to_xlsx.py <output-dir>/<pmid>` (needs `openpyxl`).
Then tell the user the exact paths written, the MA relevant verdict, and every
unresolved finding.
