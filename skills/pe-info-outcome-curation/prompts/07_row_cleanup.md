# Stage 7 — Row cleanup (deterministic script)

This file is loaded by `SKILL.md`, once per selected table, in that table's
`table_<n>/` directory (`<scratch>`). It applies the mechanical rules with a
bundled script — do not apply them by hand.

## Run the cleanup script

```
python scripts/clean_pe_outcome_rows.py <scratch>/06_rows.md \
  --table <scratch>/00_markdown_table.md \
  -o <scratch>/07_clean.csv --report <scratch>/07_cleanup_report.md
```

The script:
1. parses the 14-column Markdown table and reports any row with the wrong number
   of cells (it cannot fix those — you must);
2. normalizes empty / `-` / `none` / `nan` / `unknown` cells to `N/A`;
3. moves an interval that was put in Variation value (`1.1–15.8`, `1.1 to 15.8`)
   into Lower bound / Upper bound (splitting, not calculating);
4. drops exact duplicate rows;
5. writes `07_clean.csv` (14 columns, every cell a string) and a report that
   **flags** — without changing — rows where: Statistics type is `N/A`; the unit
   is a statistic (SD, SE, IQR, CI, range); Outcome is just a number;
   Characteristic names a table/figure; or a Source column is not a column of the
   table.

It needs only the Python standard library.

## Then
Read `07_cleanup_report.md`. If it lists malformed rows or flags, fix **those
rows** in `06_rows.md` (from the source table — no calculations) and re-run the
script **once**. Leave any flag you believe is a false alarm and say why in your
reply. Then proceed to Stage 8.
