# Curating PK/PE data from papers with Claude Code skills on OSC

This guide shows how to use the **PK/PE curation skills** in [`skills/`](skills/) to turn a
biomedical paper (HTML or XML) into a normalized CSV table — pharmacokinetic (PK) parameters,
pharmaco-epidemiology (PE) outcomes, drug/specimen/population breakdowns, and more — running
**Claude Code** against a **local open-weight model served by Ollama**, on an OSC GPU node via
Slurm. No Anthropic API key or internet access to Anthropic is needed: Claude Code talks to your
own Ollama server instead.

> **Prerequisites.** Read [README.md](README.md) first (Ollama basics, Slurm options A/B/C) and
> skim [ollama-guide.md](ollama-guide.md) (pinned containers, model bugs, context length). This
> guide assumes you can already start an Ollama server in a batch job.

**What's in this folder, for this guide specifically**

| File | What it's for |
|---|---|
| `skills-guide.md` (this file) | How the skills work, one-time setup, and running them via Slurm |
| `skills/` | The skill bundle itself — copy this into any project's `.claude/skills/` |
| `osc_skills_job_template.sh` | A batch job script you can copy and edit |

---

## 1. What these skills are

Each skill is a folder of prose instructions (`SKILL.md`) plus a few deterministic helper
scripts. Claude Code reads the matching `SKILL.md` when you ask for it by name or description,
and carries out its procedure step by step as an ordinary agentic conversation — reading files,
running the helper scripts, writing intermediate and final output — the same way it would for any
other task, just following a specific, carefully-written procedure instead of an ad hoc one.

`skills/` has 3 of them:

| Skill | Role |
|---|---|
| `pk-pe-prepare` | **Front door, required.** Converts a raw paper (`.html` or `.xml`) into the canonical input layout the two curation skills below expect: `paper_text.md`, `abstract.md`, one `table_<n>.md`/`table_<n>.html` per table, `manifest.json`. |
| `pk-individual-curation` | Individual-subject PK tables — one row per subject per parameter. |
| `pk-summary-curation` | Cohort/group-summary PK tables — one row per group statistic (mean/median/SD/range/...). |

The order is always **prepare → curate**: prepare the paper once, then trigger whichever of the
two curation skills matches the paper's tables (per-subject values → `pk-individual-curation`;
group-level summary statistics → `pk-summary-curation`; a paper can have both kinds of table and
need both skills run). Triggering one skill at a time (rather than asking Claude to do everything
in one message) keeps that skill's full procedure in front of the model, which matters more the
smaller the model is.

> This is a 3-skill subset of a larger 12-skill PK/PE curation suite (a selector skill plus 8 more
> curation skills for drug/population/specimen breakdowns and pharmaco-epidemiology outcomes).
> Not included here — copy them the same way from the source project if you need them.

Full details, including the two environment variables that control where files are written
(`SKILL_SCRATCH_FOLDER`, `SKILL_OUTPUT_FOLDER`), are in [`skills/INSTALL.md`](skills/INSTALL.md).

---

## 2. One-time setup

1. **Install Claude Code** with its official installer. It installs into your home directory
   (`~/.local/bin/claude`), so it needs no admin rights, and every node sees it because home
   directories are shared:

   ```bash
   curl -fsSL https://claude.ai/install.sh | bash
   claude --version
   ```

   If `claude --version` says `command not found`, add `~/.local/bin` to your `PATH` and try
   again (this makes it permanent, including inside batch jobs):

   ```bash
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

   (Don't use `npm install -g @anthropic-ai/claude-code` here: on OSC it tries to write to
   the system folder `/usr/local` and fails with a permission error.)

2. **Have an Ollama container and a pulled model ready.** Either OSC's `module load
   ollama/<version>` ([README.md](README.md) §1) or your own pinned container
   ([ollama-guide.md](ollama-guide.md) §1) — the skills don't care which, only that something is
   listening on a port and speaks Ollama's Anthropic-compatible endpoint. **Pick the model first**:
   see [§5](#5-choosing-a-model) below before committing to one for a real run.

   OSC's shared model folder doesn't have the models recommended here (qwen3.8, gemma4, ...),
   so you need **your own model folder** with the model pulled into it once
   ([README.md](README.md) §6). Every command below that starts a server sets `OLLAMA_MODELS`
   (interactive) or `MY_OLLAMA_MODELS` (batch template) to that folder.

3. **Clone or copy this repo's `skills/` into your project**, so `.claude/skills/` exists next to
   your paper files:

   ```bash
   mkdir -p .claude/skills
   cp -R /path/to/tabular-data-slurm/skills/* .claude/skills/
   ```

   Claude Code auto-discovers skills from `.claude/skills/` in your current project — nothing
   else to register.

4. **Install the skills' Python dependency.** The helper scripts need Python 3 plus one package,
   `beautifulsoup4` (used to convert the paper's HTML/XML). Pick one way:

   - **Conda environment (recommended)**, from `environment.yml` in this repo:

     ```bash
     module load miniconda3/24.1.2-py310
     conda env create -f /path/to/tabular-data-slurm/environment.yml   # once; creates "pkpe-skills"
     conda activate pkpe-skills          # if this complains, use: source activate pkpe-skills
     python -c "import bs4; print('bs4 OK')"
     ```

     Activate it in every interactive session before running `claude`; the batch template does
     it for you (`CONDA_ENV=pkpe-skills`, the default).
   - **Or pip into your user Python**, with no environment to activate:

     ```bash
     pip install --user -r .claude/skills/pk-pe-prepare/scripts/requirements.txt
     ```

     Then set `CONDA_ENV=` (empty) in the batch template.

5. **Name each paper file after its PMID** (e.g. `12345678.html` or `12345678.xml`). The prepare
   step names its output folder after the file name (`.paper_assets/12345678/`), and the
   curation step has to be given that same name. A file called `paper.html` would end up in
   `.paper_assets/paper/`.

---

## 3. Try it interactively first

Do this once by hand before writing a batch job — it's the fastest way to catch a path or model
mistake cheaply, and lets you watch what each skill actually does.

```bash
# 1. Get a GPU node and start Ollama (see README.md §3 for the full explanation)
sinteractive -A PAS1234 -g 1 -c 8 -t 1:00:00
module load ollama/0.32.0
export OLLAMA_MODELS=/fs/ess/PAS1234/ollama/models     # your own folder (after module load)
mkdir -p "$OLLAMA_MODELS"
export APPTAINERENV_OLLAMA_CONTEXT_LENGTH=131072        # server context; must match step 2
ollama_start > ~/ollama-server.log 2>&1
echo $OLLAMA_PORT
ollama_pull qwen3.8:27b         # first time only; later runs reuse the cached model

# 2. Point Claude Code at that server instead of the real Anthropic API
export ANTHROPIC_BASE_URL="http://127.0.0.1:${OLLAMA_PORT}"
export ANTHROPIC_API_KEY="ollama"              # any non-empty string — Ollama doesn't check it
export ANTHROPIC_MODEL="qwen3.8:27b"
export CLAUDE_CODE_MAX_CONTEXT_TOKENS=131072   # same number as step 1's context — see §5

# 3. Prepare a paper, then curate it
cd /path/to/your/project          # wherever .claude/skills/ lives
claude -p "Use the pk-pe-prepare skill to prepare 12345678.html for curation, pmid 12345678."
claude -p "Use the pk-individual-curation skill to curate individual-subject PK data for paper 12345678."
```

Look for the final CSV in `<pmid>/pk-individual-curation.csv` (current directory by default, or
under `$SKILL_OUTPUT_FOLDER` if you set it). If the skill went off track, re-reading its
transcript (Claude Code prints its reasoning and tool calls as it works) usually shows exactly
which step it misunderstood — it's plain prose, not a black box.

---

## 4. Run it as a Slurm batch job

Once the interactive version works, `osc_skills_job_template.sh` runs the same thing unattended.
It:

1. checks the paper file, `beautifulsoup4` and `claude` are all there, so a setup mistake fails
   in seconds,
2. starts the Ollama server from OSC's module (same pattern as `osc_tabular_job_template.sh`)
   and checks that your model is in your models folder,
3. prepares one paper,
4. curates it with one named skill,
5. records where the deliverable CSV landed.

The PMID is taken from the paper's file name (`PAPER=12345678.html` → PMID `12345678`), so name
your files that way.

```bash
cp osc_skills_job_template.sh my_curation_job.sh
nano my_curation_job.sh        # at minimum: --account, PAPER, SKILL, MY_OLLAMA_MODELS
sbatch my_curation_job.sh
squeue -u $USER
cat skills-job-<jobid>.out
```

Each job curates **one paper with one skill** — that's the unit that keeps token accounting and
failure isolation clean (a crashed job only loses that one paper, not a whole batch). To process
many papers, submit one job per paper (a shell loop, or a Slurm job array) rather than looping
inside a single job — see the comment at the bottom of the template for a worked loop.

---

## 5. Choosing a model

Everything in [ollama-guide.md](ollama-guide.md) §4-6 applies here — same models, same crash-bug
caveat. A few things specific to running skills (vs. a plain chat or a raw API call):

- **Context length**: Claude Code doesn't recognize a local Ollama model name, so it assumes
  200k tokens of context unless told otherwise. Always set `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to
  the **same** value as the server's `OLLAMA_CONTEXT_LENGTH`. If you don't, a long paper can
  silently trigger context-shift truncation instead of a clean error. A reasonable starting point
  for these skills is `131072`–`196608`, depending on model and paper length; start smaller and
  raise it if a paper's conversation runs out of room.
- **`qwen3.6` needs your own pre-regression container** (`ollama-old.sif` in ollama-guide.md's
  own example), because of a real, still-open upstream crash bug triggered specifically by
  agentic tool-calling — which is exactly what running a skill through Claude Code is. None of
  OSC's modules works for it: `ollama/0.32.0` is past the regression, and the older ones
  (0.13.1 and below) predate qwen3.6 and can't load it. To use qwen3.6 in a batch job, replace
  the template's `module load` server block with the own-container pattern from ollama-guide.md
  §3. `qwen3.8` doesn't have this problem; the original project ran `gemma4` on the old
  container out of caution.
- **Set `{"totalTokensReminder": "off"}` in Claude Code's settings before running a skill.**
  Without it, Claude Code re-injects a "N tokens left" reminder whose JSON shape changes on every
  call, which defeats Ollama's prompt-cache and makes every single turn of a multi-step skill
  reprocess the *entire* conversation from scratch — turning a 5-minute paper into an hour-plus
  one, with no change in output quality. This is baked into the job template already; if you're
  running interactively, do it yourself:

  ```bash
  mkdir -p "$CLAUDE_CONFIG_DIR"    # or ~/.claude if you haven't set a custom one
  echo '{"totalTokensReminder": "off"}' > "$CLAUDE_CONFIG_DIR/settings.json"
  ```

---

## 6. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `[ERROR] prepare did not produce .../.paper_assets/<pmid>` | The paper file isn't named `<pmid>.html`/`.xml`. Rename it; the PMID is taken from the file name. |
| `[ERROR] Model ... is not in ...` | `MY_OLLAMA_MODELS` is empty (OSC's shared folder has no qwen3.8) or points at a folder you haven't pulled the model into. See §2 step 2. |
| `[ERROR] Python package beautifulsoup4 is missing` / `[ERROR] Could not activate conda environment` | Do §2 step 4 (create the `pkpe-skills` environment, or pip-install and set `CONDA_ENV=` empty). |
| Claude Code hangs or errors immediately | Check `ANTHROPIC_BASE_URL`/`ANTHROPIC_API_KEY`/`ANTHROPIC_MODEL` are exported, and that the Ollama server is actually up (`curl $ANTHROPIC_BASE_URL/api/tags`). |
| A paper takes far longer than expected (many tens of minutes per paper) | Missing the `totalTokensReminder: off` setting (§5) — this is the single biggest time sink seen with this setup. |
| `API Error: Claude's response exceeded the N output token maximum` | Raise `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, or the model got stuck in an unproductive "thinking" loop. A plain retry of just that paper often succeeds even with temperature 0 — this has been observed repeatedly and isn't fully understood, but it's cheap to try before investigating further. |
| No deliverable CSV where you expected it | Check `SKILL_SCRATCH_FOLDER`/`SKILL_OUTPUT_FOLDER` — both default to the current directory, and a batch job's working directory may not be what you expect. The skill's own transcript will show where it actually wrote files. |
| Not sure whether a paper needs `pk-individual-curation` or `pk-summary-curation` | Check whether its tables report one row per subject (individual) or one row per group statistic like mean/median/SD (summary) — a paper can have both kinds and need both skills. |
| A tool call fails with malformed JSON / a shell-quoting error from the model itself | A real model limitation seen with some open models on some papers (not a setup bug) — a plain retry sometimes works; otherwise try a different model for that paper. |

For everything Ollama-specific (ports, containers, context length, model bugs) that isn't
skills-specific, see [ollama-guide.md](ollama-guide.md)'s own troubleshooting and
[README.md](README.md) §8.

---

## 7. Going further

- `skills/INSTALL.md` — the skill bundle's own reference: what each env var does, dependencies,
  and how this 3-skill subset relates to the larger curation suite it's drawn from.
- Each skill's own `SKILL.md` is readable prose — open it directly if you want to understand or
  adapt its procedure.
