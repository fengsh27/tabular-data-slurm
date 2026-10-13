# Stage 9 — Verification + correction

This file is loaded by `SKILL.md`, once per selected table, in that table's
`table_<n>/` directory (`<scratch>`). It follows the shared procedure in
`verify_and_correct.md` (deterministic provenance check → adversarial semantic
check → bounded ≤2-round correction loop). Read that file and follow it, with the
parameters below.

## Parameters for the shared procedure
- **`<FINAL_CSV>`** = `<scratch>/07_clean.csv`
- **`<SOURCE FILES>`** = `<scratch>/00_markdown_table.md <scratch>/inputs.md`
- **`<VALUE-COLUMNS>`** = `Main value,Variation value,Lower bound,Upper bound,P value`
- **`<LABEL-COLUMNS>`** = `Source column,Outcome,Exposure`
- **`<CAUTION-COLUMNS>`** = `P value`, and `Main value` **for rows whose
  Outcome is `Number of subjects`**:
  - a p-value usually sits in its own P-value column (or a footnote), not under
    the row's group column, so the script's *attribution* check flags most
    p-values as "misattributed" — that is expected. Judge p-values only by the
    Stage 6 scope rules (right test, right rows); its *existence* check still
    applies.
  - a group size may come from the caption or a header rather than a table cell;
    judge those by reading the source, do not auto-correct.

So the concrete script invocation is:

```
python scripts/verify_provenance.py \
  <scratch>/07_clean.csv \
  <scratch>/00_markdown_table.md \
  <scratch>/inputs.md \
  --value-columns "Main value,Variation value,Lower bound,Upper bound,P value" \
  --attribution \
  --label-columns "Source column,Outcome,Exposure" \
  --json
```

## What the semantic check (Step B) must confirm, row by row
- the value, statistic and interval are what the table reports **for that row
  header and that column header** — the right group, the right time point;
- crude vs adjusted is labelled correctly (footnotes!);
- the unit is a unit, not a statistic;
- the p-value is in exactly the rows the test covers;
- the row is **in scope** (an outcome value, not a baseline characteristic).

A value from the right column but the wrong row (or vice versa) is the most
common error and attribution only partly catches it — check it yourself.

## Output
Overwrite `07_clean.csv` with the corrected rows (keep its 14 columns) and write
`09_verification_report.md`, exactly as the shared procedure's "Output of this
stage" section specifies.
