# Stage 2 — Study refine (protocol part B)

This file is loaded by `SKILL.md`. It complements Stage 1 with population,
eligibility, drug and outcome information, in one row.

## Inputs (read from the scratch directory)
- `full_text.md` — the paper's full text (and abstract).
- `01_study_design.md` — Stage 1's result (Study type, Study design, Data source).

Read these now.

## Fields to fill
- **Population** — the age group of the subjects. Common categories:
  `Nonpregnant`, `Maternal` (pregnant individuals), `Pediatric` (birth to ~17
  years), `Neonate` (birth to 28 days), `Newborn` (at delivery or birth),
  `Infant` (>28 days to 1 year), `Children` (1 to 12 years), `Adolescent` (12 to
  18 years), `Adults` (18 years or older). If the study has more than one
  population (e.g. mothers and their newborns), **combine them in this one
  field**, joined with `; ` (e.g. `Maternal; Newborn`).
- **Inclusion criteria** — characteristics participants must have to be in the
  study. **Use the exact wording from the article.** Eligibility is often split
  across the abstract, a Methods subsection and a flow diagram caption — capture
  all of it. Quote each distinct criterion **once, verbatim** (do not paraphrase,
  summarise or truncate), and join the quoted passages with `; `.
- **Exclusion criteria** — characteristics that disqualify participants. Same
  rule: quote every exclusion stated anywhere in the article, verbatim, joined
  with `; `.
- **Pregnancy stage** — the stage of pregnancy for the patients: `Trimester 1`
  (up to ~14 weeks), `Trimester 2` (~15–28 weeks), `Trimester 3` (≥ ~28 weeks),
  `Fetal Stage`, `Delivery` (parturition, labor), `Postpartum` (~6–8 weeks after
  birth), `Lactation` (nursing, breastfeeding). `N/A` if the study is not about
  pregnancy.
- **Subject N** — the number of subjects in the population, as stated in the
  article (copy the number; no arithmetic). If there are several populations,
  give one number per population in the same order, joined with `; `.
- **Drug name** — all drugs of interest as they relate to the study's outcomes.
- **Outcomes** — the measure(s) the investigators consider most important among
  the outcomes examined (usually the primary outcome(s)). **Use the exact wording
  from the article.**

Use `N/A` when a field cannot reasonably be inferred.

### Quoting rules for the three verbatim fields
Inclusion criteria, Exclusion criteria and Outcomes are checked by a script that
looks for each `; `-separated passage **word for word** in `full_text.md`. So:
- copy passages exactly as printed (same words, same numbers, same order);
- you may start or end a passage mid-sentence, but do not join two separate
  sentences into one passage — split them with `; `;
- do not add words of your own (no "Patients were …" lead-ins unless printed);
- do not use `;` inside a passage (split there instead) or `|` anywhere.

## Output of this stage
A two-column Markdown table, exactly these seven rows in this order:

```
| Field | Value |
| --- | --- |
| Population | … |
| Inclusion criteria | … |
| Exclusion criteria | … |
| Pregnancy stage | … |
| Subject N | … |
| Drug name | … |
| Outcomes | … |
```

**Write it to `02_study_refine.md`.** Then run the verbatim check:

```
python scripts/check_quotes.py <scratch>/02_study_refine.md <scratch>/full_text.md \
  > <scratch>/02_quote_check.md
```

`<scratch>` is `.pe_info_outcome_scratch/<pmid>` under the working base. Read the
report. For every passage it marks **NOT FOUND**, find the real wording in
`full_text.md` and fix the passage in `02_study_refine.md` (or remove it if the
article does not say it). Re-run the script **once**. Any passage still not found
is listed as unresolved when you report back — do not loop further.
