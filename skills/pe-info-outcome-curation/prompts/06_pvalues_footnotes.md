# Stage 6 — P values and footnotes (protocol C&D, notes 7–8)

This file is loaded by `SKILL.md`, once per selected table, in that table's
`table_<n>/` directory (`<scratch>`). P-values are easy to miss and easy to
over-apply, so they get their own pass.

## Inputs (read from `<scratch>`)
- `05_rows.md` — Stage 5's rows (P value is still `N/A`).
- `00_markdown_table.md` — the whole table.
- `inputs.md` — caption and **every footnote**.

Read these now.

## Part 1 — Footnotes
Read every footnote. A footnote may carry a p-value, the covariates an estimate
was adjusted for (→ the estimate is adjusted: make sure Statistics type says so),
a variable definition, or why a value is suppressed. Where a footnote defines or
qualifies **a specific cell** (via a symbol such as `a`, `*`, `†`), apply it to the
row extracted from **that cell only**.

## Part 2 — P values
The p-value usually is **not** in the row's own cell: search the **entire table**
(a p-value column, a separate row, a footnote) for the p-value that applies to
each row, then:
- one p-value comparing two or more groups → enter it in **every group row** in
  that comparison;
- one p-value covering several categories or subgroups → enter it in every row
  that test covers;
- a p-value that belongs to a specific crude or adjusted estimate → enter it
  **only** in that effect-estimate row;
- a p-value a footnote links to one specific cell → only the row from that cell;
- no p-value applies → `N/A`.

Copy p-values **exactly as printed** (`0.056`, `<0.001`, `.67`, `NS`). Never
calculate, round or infer one. Do not skip a row that should have one.

Example: a table with columns `Day 1 Fenoldopam | Day 1 Controls | … | P-value`
and one P-value per parameter row → that p-value goes into every row extracted
from that parameter row (both groups, every day), because the one test covers
them all.

## Output of this stage
The same Markdown table as `05_rows.md` (same 14 columns, same rows, same order)
with P value filled and any footnote corrections applied. **Do not add or remove
rows here.** Write it to `06_rows.md`.

Before continuing, check: the row count equals `05_rows.md`'s; every p-value you
entered appears in the table or its footnotes. Redo once if not.
