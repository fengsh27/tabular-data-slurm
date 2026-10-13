# Stage 3 — Select the outcome tables

This file is loaded by `SKILL.md`. It decides which tables hold outcome values
(protocol part C&D: "we will specify which table/s data needs to be extracted").

## If the user named the tables
Use exactly the tables the user named, skip the judgment below, and still write
`03_selection.md` (listing them, reason: "named by the user").

## Otherwise — list the tables first (script)

```
python scripts/list_tables.py <assets> > <scratch>/03_tables.md
```

`<assets>` is `.paper_assets/<pmid>` and `<scratch>` is
`.pe_info_outcome_scratch/<pmid>`, both under the working base. The listing shows
each table's caption, size and column headers, and flags:
- **DUPLICATE of table_k** — the same table printed twice; never select the copy;
- **baseline?** — the caption looks like a baseline/demographics table (a hint
  only — read the table to decide).

Read `03_tables.md`, then open the `table_<n>.md` of any table whose role is not
clear from its listing.

## Selection rule
**Select** a table if it reports values that bear on an outcome:
- effect estimates for an outcome (odds/risk/hazard ratios, crude or adjusted);
- event counts, percentages, or summary statistics (mean, median, …) of an
  outcome per group;
- outcome measurements over time per group (e.g. a lab value on day 1/2/3).

**Do not select**:
- baseline demographic / clinical characteristics of the groups (age, weight,
  BMI, parity, smoking, comorbidities, baseline medication, baseline lab values
  taken before exposure), unless the article analyses them as outcomes;
- covariate-balance tables (standardised mean differences, matching
  diagnostics);
- tables that only classify or list patients (diagnoses, procedures) without
  outcome values;
- duplicates.

When unsure, re-read how the article's Methods and Results describe the table:
if the text treats its values as results of the exposure, it is an outcome table.

## Output of this stage
Write `03_selection.md`:

```
## Reasoning
- table_1: <one line: what it reports> — Selected / Excluded (<reason>)
- table_2: …

Selected tables: table_3, table_4
```

The last line lists the selected labels exactly as in the listing (or
`Selected tables: none`). Then, for each selected table, create
`table_<n>/` and write:
- `table_<n>/00_markdown_table.md` — the Markdown table from the `**Table:**`
  block of `.paper_assets/<pmid>/table_<n>.md` (copy it; do not re-convert the
  HTML);
- `table_<n>/inputs.md` — that table's caption and footnotes (verbatim, from the
  same file) and the paper title.
