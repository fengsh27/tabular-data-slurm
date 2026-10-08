# Installing the Ollama PK/PE curation skills

This `skills/` bundle is a **flat, self-contained** subset of a larger PK/PE curation
suite, tuned for smaller open models (e.g. Qwen via Ollama) run through Claude Code.
Each curation pipeline is its **own** top-level skill with its **own** scripts and
resources — there is no shared `curation-common/`.

See [`skills-guide.md`](../skills-guide.md) for the full walkthrough, including
running these skills in an OSC Slurm batch job against a local Ollama server.

## Install
Copy every folder in here into your project's `.claude/skills/`:

```bash
cp -R skills/* <your-project>/.claude/skills/
```

You then have 3 skills: the `pk-pe-prepare` front door (a required dependency —
it converts a raw paper into the input layout the other two expect), and the two
curation skills, `pk-individual-curation` (individual-subject PK tables) and
`pk-summary-curation` (cohort/group-summary PK tables). The larger suite this is
drawn from also has a selector skill and 8 more curation skills (drug/population/
specimen breakdowns, pharmaco-epidemiology outcomes) — not included in this subset;
copy them the same way from the source project if you need them.

## Use
- **Prepare first (always):** trigger `pk-pe-prepare` (or run its
  `scripts/prepare_paper.py`) on a raw `.html` **or** `.xml` paper to produce
  `./.paper_assets/<pmid>/`.
- **Then curate:** trigger `pk-individual-curation` or `pk-summary-curation`
  depending on whether the paper's tables report per-subject or per-cohort
  values, pointing it at the prepared `./.paper_assets/<pmid>/` files.

## Where files go (two env vars)
Each skill writes two kinds of files; both default to the user's current working
directory and can be redirected with an environment variable:

- **Intermediate / working files** — the prepared `.paper_assets/` and the
  per-skill `.<name>_scratch/` dirs (git-ignored). Set **`SKILL_SCRATCH_FOLDER`**
  to root them elsewhere.
- **Final results** — each curation skill copies its deliverable CSV to
  `<pmid>/<skill>.csv` as its last step. Set **`SKILL_OUTPUT_FOLDER`** to root those
  elsewhere (e.g. one clean results dir, separate from the noisy scratch dirs).

```bash
export SKILL_SCRATCH_FOLDER=/tmp/pkpe-work       # intermediates
export SKILL_OUTPUT_FOLDER=/data/pkpe-results    # final CSVs
```

Unset (the default), both go in the current directory. The two are independent —
set either, both, or neither.

## Dependencies
Pipelines that convert HTML tables or prepare papers need BeautifulSoup:
`pip install -r <skill>/scripts/requirements.txt` (provides `beautifulsoup4`), or create
the conda environment from the repo's top-level `environment.yml`
(`conda env create -f environment.yml`, then `conda activate pkpe-skills`).
`verify_provenance.py` and the `clean_*_rows.py` cleanup scripts are Python-3
stdlib only.

## Updating

This bundle is a point-in-time copy. If the source project's skills change,
re-copy the folders you need from there rather than hand-editing deep logic
here — but small local fixes (a prompt tweak, a path) are fine to make
directly in this repo.
