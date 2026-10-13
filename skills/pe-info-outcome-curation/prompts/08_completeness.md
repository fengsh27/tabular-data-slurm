# Stage 8 — Completeness check (protocol C&D, note 10)

This file is loaded by `SKILL.md`, once per selected table, in that table's
`table_<n>/` directory (`<scratch>`). It is a **report only** — it must not
change what was extracted.

## Run the script

```
python scripts/completeness_report.py <scratch>/04_inventory.md \
  <scratch>/07_clean.csv > <scratch>/08_completeness.md
```

It lists every inventory column, its Row kind, and how many rows were produced
from it, and flags:
- a column with a Row kind other than `not applicable` that produced **0 rows**;
- rows whose Source column is not in the inventory.

## Then
Read `08_completeness.md`. For each flagged column, append one line to the end of
`08_completeness.md` under a `## Notes` heading saying **why** it has no rows
(e.g. "only baseline values — out of scope", "values only in a figure"). Do not
re-extract or edit `07_clean.csv` in this stage; if the gap is a genuine miss,
note it — Stage 9 is where rows are corrected.
