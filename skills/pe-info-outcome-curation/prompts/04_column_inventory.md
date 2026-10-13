# Stage 4 — Column inventory (protocol C&D, Step 1)

This file is loaded by `SKILL.md`, once per selected table, in that table's
`table_<n>/` directory (`<scratch>` below).

Map the whole table **before extracting anything**. This bounds the task (a known
set of columns to account for), forces you to classify columns that have no
obvious extraction instead of skipping them, and gives Stage 8's completeness
check its reference list.

## Inputs (read from `<scratch>`)
- `00_markdown_table.md` — the table.
- `inputs.md` — caption, footnotes, paper title.

Read these now, **including every footnote**.

## What to produce
List **every column** of the table, left to right — including the first
(row-label) column and any p-value column. For each column give:
- **Column** — the column's header label **exactly as it appears in the
  Markdown header row** (e.g. `Unnamed_0`, `Day 1_0`, `Controls`, `P-value`).
  Stages 5–8 use this label as the row's `Source column`, so copy it exactly.
- **Meaning** — what the column holds in plain words, using any sub-header row
  under the header (e.g. `Day 1_0` → "Day 1, Fenoldopam group").
- **Row kind** — what rows it will produce, one of:
  - `group size` — numbers of subjects per group (also when the size is printed
    in the header itself, e.g. "Controls, N = 68 225");
  - `event count` — counts (with or without %) of an outcome event;
  - `effect estimate` — OR / RR / HR (crude or adjusted) with intervals;
  - `summary statistic` — mean / median / % of an outcome per group;
  - `not applicable` — produces no rows of its own (row labels, p-value columns,
    out-of-scope baseline values). Say why in Notes.
- **Notes** — anything that affects extraction: the statistic format stated in
  the caption (e.g. "median (interquartile range)"), a group size in the header,
  a footnote that applies to this column, values stacked on two lines.

Also note in Notes when one table row is printed over two Markdown lines (e.g. a
median on one line and its `(IQR)` on the next) — Stage 5 must join them into one
value.

## Output of this stage
Write `04_inventory.md`:

```
| Column | Meaning | Row kind | Notes |
| --- | --- | --- | --- |
| Unnamed_0 | Parameter (row labels) | not applicable | supplies the Outcome for each row |
| Day 1_0 | Day 1, Fenoldopam group | summary statistic | median (IQR) per caption; IQR on the next line |
| … | … | … | … |
| P-value | P value, fenoldopam vs controls | not applicable | p-values; applied to rows in Stage 6 |
```

Before continuing, check: every column of the Markdown header appears exactly once,
labels copied exactly, every column has a Row kind. Redo once if not. Do not
extract any values yet.
