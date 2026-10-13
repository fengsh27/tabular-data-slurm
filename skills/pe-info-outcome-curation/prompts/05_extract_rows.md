# Stage 5 — Extract rows, column by column (protocol C&D, Step 2)

This file is loaded by `SKILL.md`, once per selected table, in that table's
`table_<n>/` directory (`<scratch>`).

## Inputs (read from `<scratch>`)
- `00_markdown_table.md` — the table.
- `inputs.md` — caption, footnotes, paper title.
- `04_inventory.md` — Stage 4's column inventory.
- `../01_study_design.md` and `../02_study_refine.md` — study info, for the
  overall study population (Characteristic) and the drug (Exposure).

Read these now.

## How to extract
Work **column by column**, in inventory order — not row by row. For each column
whose Row kind is not `not applicable`, go down the column and produce **one
output row for every reported value** in it. One visual table row often holds a
group size, an event count, a crude estimate and an adjusted estimate — those are
separate output rows. For a two-arm outcome you normally produce: the group size
of each arm, the event count of each arm, and each effect estimate separately. A
crude and an adjusted estimate are **two rows**. Do not stop once the effect
estimates are captured — extract the count columns too.

Read both the **row header** and the **column header** (and sub-header rows) of
every cell: together they tell you the Characteristic, Exposure and Outcome.

## The 14 columns of each row
- **Source location** — `Table <n>` for this table (provenance only).
- **Characteristic** — the overall study population, in every row (e.g.
  `Neonates undergoing cardiopulmonary bypass`). If the row belongs to a
  subgroup: `<overall population>; <subgroup>` (e.g. `Full cohort; Nulliparous`,
  `…; After PS matching`, `…; Age ≥35`). Never the table or figure name. If the
  value is suppressed/masked/NA, add the reason here (e.g. `…; suppressed, n<11`).
- **Exposure** — the exposure the value belongs to: a drug, condition or
  comparison group (`Fenoldopam`, `Controls`, `Cocaine exposed`). A column header
  that names a drug is very likely the Exposure. For an effect estimate comparing
  groups, name the comparison (`Oxycodone vs no opioid`).
- **Outcome** — what the value measures (`Serum lactate on postoperative day 1`,
  `Neonatal abstinence syndrome`, `Number of subjects`). Never the number itself.
  Include the time point when the column or row gives one.
- **Main value** — the reported value, copied **exactly as printed** (not a
  range). For a group size printed in a header (`Controls, N = 68 225`), the
  number (`68 225`).
- **Main value unit** — `kg`, `mmHg`, `mmol/l`, `Count`, … — **never** a
  statistic such as SD or IQR. Ratios (OR/RR/HR) have unit `N/A`.
- **Statistics type** — what Main value is, **including crude or adjusted**, as
  specifically as the article reports: `Crude odds ratio`, `Adjusted odds ratio`,
  `Crude risk ratio`, `Adjusted risk ratio`, `Hazard ratio`, `Reporting odds
  ratio`, `Sum`, `Mean`, `Median`, `Proportion`, `%`. **Required** — never `N/A`.
- **Variation type** / **Variation value** — e.g. `SD` and its single value.
- **Interval type** / **Lower bound** / **Upper bound** — e.g. `95% CI`, `IQR`,
  `Range`, with the two ends in separate columns. An interval is **never** put in
  Variation value.
- **P value** — leave `N/A` here; Stage 6 fills p-values.
- **Source column** — the inventory `Column` label this value came from, copied
  exactly (a helper for Stage 8; it is removed from the final output).

### Counts, percentages and group sizes
- **Count with percentage** (`12 (14.1%)`): Main value `12`, unit `Count`,
  Statistics type `Sum`, Variation type `%`, Variation value `14.1`.
- **Count without percentage**: Main value = the count, unit `Count`,
  Statistics type `Sum`, Variation type/value `N/A`. It still gets a row.
- **Group size in a header, row label or caption** (`Controls, N = 68 225`,
  `Fenoldopam (n = 20)`): its own row — Outcome `Number of subjects`, unit
  `Count`, Statistics type `Sum`, Source column = the column it labels.
- **Suppressed / masked / NA value**: still a row, Main value `N/A`, reason in
  Characteristic. Do not omit it.

## Hard rules
- **No calculations** — every value is copied from the table exactly; never
  compute a percentage, difference, sum or bound.
- Every cell is a string; use `N/A` for anything that cannot be filled.
- Out-of-scope values (baseline characteristics, balance statistics) are not
  extracted even inside this table — their columns are `not applicable`.
- Do not use the `|` character inside a cell (write `/`).

## Output of this stage
A Markdown table with exactly this header, one row per extracted value:

```
| Source location | Characteristic | Exposure | Outcome | Main value | Main value unit | Statistics type | Variation type | Variation value | Interval type | Lower bound | Upper bound | P value | Source column |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Table 4 | Neonates undergoing cardiopulmonary bypass | Fenoldopam | Serum lactate on postoperative day 1 | 2.7 | mmol/l | Median | N/A | N/A | IQR | 1.7 | 4.1 | N/A | Day 1_0 |
```

Before continuing, check: every row has 14 cells; every inventory column with a
Row kind other than `not applicable` has at least one row (or you can say why
not); no Statistics type is `N/A`; no unit is a statistic. Redo once if a check
fails. Then **write the table to `05_rows.md`**.
