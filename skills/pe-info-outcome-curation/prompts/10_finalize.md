# Stage 10 — Finalize: combine, relevance, write out (deterministic script)

This file is loaded by `SKILL.md` after every selected table finished Stage 9
(or right after Stage 3 if no table was selected).

## Run the script

```
python scripts/finalize_pe.py <scratch>
```

`<scratch>` is `.pe_info_outcome_scratch/<pmid>` under the working base. The
script needs only the Python standard library. It:
1. stacks every `table_*/07_clean.csv` (in table order) into `outcomes.csv`,
   dropping the `Source column` helper → the 13 outcome columns; exact duplicate
   rows are written once;
2. builds `study_info.csv` (one row, 13 columns) from `01_study_design.md` and
   `02_study_refine.md`;
3. computes **MA relevant** (1 only if all four criteria hold):
   1. Study type includes Pharmacoepidemiology;
   2. Drug name matches a term in `MA_DRUG` (default `oxycodone`);
   3. Outcomes (study info) or any outcome row's Outcome matches a term in
      `MA_OUTCOMES` (default neonatal opioid withdrawal / abstinence syndrome);
   4. some outcome row's Statistics type is an odds ratio, relative/risk ratio
      or hazard ratio;
   and writes which criteria passed to `10_ma_relevance.md`;
4. copies the deliverables to the output folder (`$SKILL_OUTPUT_FOLDER/<pmid>/`,
   or `./<pmid>/` when unset):
   `pe-info-outcome-curation.csv` (outcomes) and
   `pe-info-outcome-curation.study_info.csv`.

It prints the paths it wrote. If it reports an error (e.g. a missing field file),
fix the named file and re-run once.

## Then
Report to the user: the two output paths, the MA relevant verdict with the
per-criterion result from `10_ma_relevance.md`, the selected and excluded tables,
and every unresolved finding from Stages 2, 7, 8 and 9.
