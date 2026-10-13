# Stage 1 — Study design (protocol part A)

This file is loaded by `SKILL.md`. It extracts the study's identifying and design
information from the full text.

## Inputs (read from the scratch directory)
- `full_text.md` — the paper's full text (and abstract).
- `.paper_assets/<pmid>/manifest.json` (under the same working base as the
  scratch directory) — for `pmid`, `title` and `year`.

Read these now.

## Fields to fill
- **PMID** — the PubMed id: the `pmid` in `manifest.json` (the prepared folder's
  name). Copy it exactly.
- **Year** — the publication year. Use `manifest.json`'s `year` when it is not
  `null`. Otherwise use the year stated explicitly in the title block, citation
  information or header of the article (e.g. "Tan et al., 2024"). Never guess
  from dates of data collection. If not available, `N/A`.
- **Study type** — the area of interest of the article. Choose from
  `Pharmacoepidemiology`, `Clinical Trials`, `Pharmacokinetics`,
  `Pharmacodynamics`, `Pharmacogenetics`. More than one is allowed — join them
  with `/` (e.g. `Pharmacoepidemiology/Pharmacogenetics`). A **case report** is
  `Pharmacoepidemiology`.
- **Study design** — the design described in the article. Common examples:
  Prospective cohort study; Retrospective cohort study; Randomized controlled
  trial (RCT); Double-blind randomized trial; Case-control study; Cross-sectional
  study; Systematic review and meta-analysis; Open-label study; Nested
  case-control study; Pilot study; Chart review; Observational study. If several
  are mentioned (e.g. "prospective, randomized, double-blind"), list them as
  **one string in the same order** as the article.
- **Data source** — the primary location(s) where data were accessed or the
  primary site(s) where the study was conducted (hospitals, databases,
  registries, geographic locations).

Use `N/A` for any field that cannot reasonably be inferred.

## Output of this stage
A two-column Markdown table, exactly these five rows in this order:

```
| Field | Value |
| --- | --- |
| PMID | … |
| Year | … |
| Study type | … |
| Study design | … |
| Data source | … |
```

Do not use the `|` character inside a value (write `/` instead).

Before continuing, check: all five fields present; `Study type` uses only the
five allowed names; `Year` is a 4-digit year or `N/A`. If a check fails, redo
once. Then **write the table to `01_study_design.md`**.
