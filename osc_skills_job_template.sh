#!/bin/bash
# =============================================================================
# PK/PE curation-skill batch job for OSC (Ascend / Cardinal)
#
# What it does: starts an Ollama server on a GPU node, points Claude Code at it,
# prepares one paper, then curates it with one named skill from skills/. See
# skills-guide.md for the full walkthrough and the one-time setup this assumes
# (Claude Code installed, skills/ copied into .claude/skills/ of the directory
# you submit this from).
#
# How to use:
#   1. Change --account below to YOUR project code (e.g. PAS1234).
#   2. Name each paper file after its PMID (e.g. 12345678.html). The prepare
#      step names its output folder after the file name, so the file name IS
#      the PMID this job uses.
#   3. Set PAPER / SKILL / MY_OLLAMA_MODELS below (or override at submit time).
#   4. Submit:   sbatch osc_skills_job_template.sh
#      Or override settings at submit time, e.g.:
#                sbatch --export=ALL,PAPER=87654321.html,SKILL=pk-summary-curation \
#                       osc_skills_job_template.sh
#   5. Check progress:  squeue -u $USER
#      Read output:     cat skills-job-<jobid>.out
#      (the server's own log is in ollama-server-<jobid>.log, useful if something fails)
#
# This job curates ONE paper with ONE skill. To process many papers, submit one
# job per paper (see the loop example in the last comment block) rather than
# looping inside a single job — that keeps token accounting and failure
# isolation clean (one bad paper doesn't take the rest down with it).
# =============================================================================
#SBATCH --job-name=pkpe-skill
#SBATCH --account=PCON0100            # <-- CHANGE to your project code
#SBATCH --gpus-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=skills-job-%j.out

set -u

# === 1. Settings you may change ==============================================
PAPER=${PAPER:-12345678.html}                   # the raw paper file (.html or .xml), named <pmid>.html/.xml
PMID=$(basename "${PAPER%.*}")                  # derived from the file name; don't set it separately
SKILL=${SKILL:-pk-individual-curation}           # which curation skill to run (see skills-guide.md §1)
MODEL=${MODEL:-qwen3.8:27b}                     # must NOT be qwen3.6 unless you switch to a
                                                 # pre-regression container (see ollama-guide.md §6)
CONTEXT_LENGTH=${CONTEXT_LENGTH:-131072}         # keep CLAUDE_CODE_MAX_CONTEXT_TOKENS equal to this
MAX_OUTPUT_TOKENS=${MAX_OUTPUT_TOKENS:-32000}

# Where models are stored. OSC's shared folder (used when this is empty) does NOT
# have qwen3.8 or the other models recommended for these skills, so point this at
# your own folder and pull the model into it once first (README.md section 6):
MY_OLLAMA_MODELS=${MY_OLLAMA_MODELS:-}          # e.g. /fs/ess/PAS1234/ollama/models

# Python environment for the skills' helper scripts, created once from this
# repo's environment.yml (skills-guide.md section 2). Set to empty if you
# pip-installed beautifulsoup4 into your user Python instead.
CONDA_ENV=${CONDA_ENV-pkpe-skills}

# --- Pre-flight checks: fail in seconds, before starting the server -----------
if [ ! -f "$PAPER" ]; then
    echo "[ERROR] Paper file not found: $PAPER (looked in $PWD)"; exit 1
fi
if [ -n "$CONDA_ENV" ]; then
    module load miniconda3/24.1.2-py310
    eval "$(conda shell.bash hook)"
    conda activate "$CONDA_ENV" || {
        echo "[ERROR] Could not activate conda environment '$CONDA_ENV'. Create it once with:"
        echo "        module load miniconda3/24.1.2-py310 && conda env create -f environment.yml"
        exit 1
    }
fi
# The skills call "python", so check that one
if ! python -c "import bs4" 2>/dev/null; then
    echo "[ERROR] Python package beautifulsoup4 is missing for $(command -v python)."
    echo "        Create the conda environment (environment.yml) or run:"
    echo "        pip install --user -r .claude/skills/pk-pe-prepare/scripts/requirements.txt"
    exit 1
fi
if ! command -v claude > /dev/null; then
    echo "[ERROR] Claude Code ('claude') is not on PATH. See skills-guide.md section 2."; exit 1
fi

# Where this job's own working files go. Keeping scratch and final output apart
# makes it easy to clean up intermediates without touching results you care about.
SKILL_SCRATCH_FOLDER=${SKILL_SCRATCH_FOLDER:-$PWD/.skill_scratch/${SLURM_JOB_ID}}
SKILL_OUTPUT_FOLDER=${SKILL_OUTPUT_FOLDER:-$PWD/skill_output}
export SKILL_SCRATCH_FOLDER SKILL_OUTPUT_FOLDER
mkdir -p "$SKILL_SCRATCH_FOLDER" "$SKILL_OUTPUT_FOLDER"

# === 2. Load OSC's Ollama module and start the server ========================
# Same bootstrap as osc_tabular_job_template.sh — see README.md §4 for a line-by-
# line explanation. If you need qwen3.6 specifically, switch this section to your
# own pinned pre-regression container per ollama-guide.md §1/§6 instead of OSC's
# module, which is past the regression window.
module load ollama/0.32.0
if [ -n "$MY_OLLAMA_MODELS" ]; then
    export OLLAMA_MODELS="$MY_OLLAMA_MODELS"     # must come AFTER module load
fi
export APPTAINERENV_OLLAMA_CONTEXT_LENGTH=$CONTEXT_LENGTH
echo "[INFO] Node: $(hostname)   Models folder: $OLLAMA_MODELS   Model: $MODEL"

SERVER_LOG=ollama-server-${SLURM_JOB_ID}.log
source ollama_start_helper > "$SERVER_LOG" 2>&1
BASE_URL="http://127.0.0.1:${OLLAMA_PORT}"
trap 'module unload ollama' EXIT

for i in {1..60}; do
    sleep 5
    if ! kill -0 "$OLLAMA_PID" 2>/dev/null; then
        echo "[ERROR] Ollama server exited during startup. See $SERVER_LOG"
        exit 1
    fi
    curl -sf "$BASE_URL/api/tags" > /dev/null && break
done
curl -sf "$BASE_URL/api/tags" > /dev/null || { echo "[ERROR] Server never became ready. See $SERVER_LOG"; exit 1; }
echo "[INFO] Ollama is ready at $BASE_URL"

# Is the model actually in this models folder? (A missing model would otherwise
# only surface as a confusing Claude Code error later.)
if ! curl -s "$BASE_URL/api/tags" | python3 -c "import json,sys; names=[m['name'] for m in json.load(sys.stdin)['models']]; sys.exit(0 if '$MODEL' in names else 1)"; then
    echo "[ERROR] Model $MODEL is not in $OLLAMA_MODELS."
    echo "        Set MY_OLLAMA_MODELS to the folder you pulled it into (README.md section 6)."
    exit 1
fi

# === 3. Point Claude Code at this server ======================================
export ANTHROPIC_BASE_URL="$BASE_URL"
export ANTHROPIC_API_KEY="ollama"               # any non-empty string — Ollama doesn't check it
export ANTHROPIC_MODEL="$MODEL"
export CLAUDE_CODE_MAX_CONTEXT_TOKENS=$CONTEXT_LENGTH   # keep equal to OLLAMA_CONTEXT_LENGTH above —
                                                          # see skills-guide.md §5 for why
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=$MAX_OUTPUT_TOKENS
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_AUTOUPDATER=1
export DISABLE_TELEMETRY=1

# Per-job config dir: avoids contention with other parallel jobs on ~/.claude,
# and this is where the totalTokensReminder fix below actually takes effect.
export CLAUDE_CONFIG_DIR="$PWD/.claude_home/${SLURM_JOB_ID}"
mkdir -p "$CLAUDE_CONFIG_DIR"
# Without this, Claude Code's own "N tokens left" reminder defeats Ollama's
# prompt-cache on every single call, making a multi-step skill reprocess the
# ENTIRE conversation from scratch each turn — see skills-guide.md §5.
echo '{"totalTokensReminder": "off"}' > "$CLAUDE_CONFIG_DIR/settings.json"

# === 4. Prepare the paper, then curate it =====================================
echo "[INFO] Preparing ${PAPER} (pmid ${PMID})..."
claude -p "Use the pk-pe-prepare skill to prepare ${PAPER} for curation, pmid ${PMID}." \
    --dangerously-skip-permissions
if [ ! -d "${SKILL_SCRATCH_FOLDER}/.paper_assets/${PMID}" ]; then
    echo "[ERROR] prepare did not produce ${SKILL_SCRATCH_FOLDER}/.paper_assets/${PMID}"
    exit 1
fi

echo "[INFO] Curating with ${SKILL}..."
T0=$(date +%s)
claude -p "Use the ${SKILL} skill to curate paper ${PMID}. Its prepared assets are in ${SKILL_SCRATCH_FOLDER}/.paper_assets/${PMID}/. Run the full skill procedure end to end and write the final deliverable to ${SKILL_OUTPUT_FOLDER}/${PMID}/${SKILL}.csv." \
    --dangerously-skip-permissions
CLAUDE_EXIT=$?
echo "[INFO] Claude exit code: ${CLAUDE_EXIT}  elapsed: $(( $(date +%s) - T0 ))s"

# === 5. Report where the deliverable landed ===================================
DEST="${SKILL_OUTPUT_FOLDER}/${PMID}/${SKILL}.csv"
if [ -s "$DEST" ]; then
    echo "[INFO] OK: $DEST"
else
    echo "[WARN] Expected deliverable not found at $DEST — check the transcript above,"
    echo "       and look under ${SKILL_SCRATCH_FOLDER} for a stage-final CSV to recover by hand."
fi

echo "[INFO] Done."

# -----------------------------------------------------------------------------
# To process many papers: submit one job per paper instead of looping in here,
# e.g. for every paper in a folder:
#
#   for paper in papers/*.html; do      # each file named <pmid>.html
#     sbatch --export=ALL,PAPER="$paper" osc_skills_job_template.sh
#   done
# -----------------------------------------------------------------------------
