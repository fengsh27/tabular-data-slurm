#!/bin/bash
# =============================================================================
# Smoke test: curate examples/33650231.html with the pe-info-outcome-curation
# skill, using qwen3.8:27b served by Ollama on one GPU.
#
# Submit from the repo root (the job finds skills/ and examples/ from there):
#     sbatch scripts/pe-qwen38-27b-smoke.sbatch
# Override any setting at submit time, e.g.:
#     sbatch --export=ALL,MODEL=qwen3.8:27b,MY_OLLAMA_MODELS=/fs/ess/PAS1234/ollama/models \
#            scripts/pe-qwen38-27b-smoke.sbatch
#
# Each run gets its own folder runs/pe-smoke-<jobid>/ holding a copy of the paper
# and the skills, the scratch files, the deliverables (skill_output/33650231/) and
# the server log; the job's own output is runs/pe-smoke-<jobid>.out.
# A previous run took ~27 min (about 23 min of it curating) and gave 77 rows.
# =============================================================================
#SBATCH --job-name=pe-smoke
#SBATCH --account=PCON0100            # <-- CHANGE to your project code
#SBATCH --gpus-per-node=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=01:30:00
#SBATCH --output=runs/pe-smoke-%j.out

set -u

# === 1. Settings ==============================================================
PAPER=${PAPER:-examples/33650231.html}          # named <pmid>.html — the file name is the PMID
SKILL=pe-info-outcome-curation
MODEL=${MODEL:-qwen3.8:27b-t0}                  # qwen3.8:27b with temperature 0 (Modelfile);
                                                # plain qwen3.8:27b also works
export CONTEXT_LENGTH=${CONTEXT_LENGTH:-131072}  # CLAUDE_CODE_MAX_CONTEXT_TOKENS must match
MAX_OUTPUT_TOKENS=${MAX_OUTPUT_TOKENS:-32000}
# qwen3.8 needs Ollama newer than the module's 0.32.0, so use your own image
export OLLAMA_SIF=${OLLAMA_SIF:-$HOME/ollama/ollama.sif}
export MY_OLLAMA_MODELS=${MY_OLLAMA_MODELS:-$HOME/ollama/models}
CONDA_ENV=${CONDA_ENV-pkpe-skills}
export MODEL

REPO=${SLURM_SUBMIT_DIR:-$PWD}
PMID=$(basename "${PAPER%.*}")

# --- Pre-flight checks ----------------------------------------------------------
if [ ! -d "$REPO/skills/$SKILL" ]; then
    echo "[ERROR] $REPO/skills/$SKILL not found — submit from the repo root."; exit 1
fi
if [ ! -f "$REPO/$PAPER" ] && [ ! -f "$PAPER" ]; then
    echo "[ERROR] Paper file not found: $PAPER"; exit 1
fi
[ -f "$REPO/$PAPER" ] && PAPER="$REPO/$PAPER"
if [ -n "$CONDA_ENV" ]; then
    module load miniconda3/24.1.2-py310
    eval "$(conda shell.bash hook)"
    conda activate "$CONDA_ENV" || {
        echo "[ERROR] Could not activate '$CONDA_ENV'. Create it once with:"
        echo "        module load miniconda3/24.1.2-py310 && conda env create -f environment.yml"
        exit 1
    }
fi
python -c "import bs4" 2>/dev/null || { echo "[ERROR] beautifulsoup4 missing for $(command -v python)"; exit 1; }
command -v claude > /dev/null || { echo "[ERROR] 'claude' is not on PATH (skills-guide.md §2)"; exit 1; }

# === 2. Run folder: paper + skills copied in, so Claude Code finds the skills ===
RUN_DIR="$REPO/runs/pe-smoke-${SLURM_JOB_ID}"
mkdir -p "$RUN_DIR/.claude"
cp -r "$REPO/skills" "$RUN_DIR/.claude/skills"
cp "$PAPER" "$RUN_DIR/"
cd "$RUN_DIR" || exit 1
PAPER_FILE=$(basename "$PAPER")

export SKILL_SCRATCH_FOLDER="$RUN_DIR/.skill_scratch"
export SKILL_OUTPUT_FOLDER="$RUN_DIR/skill_output"
mkdir -p "$SKILL_SCRATCH_FOLDER" "$SKILL_OUTPUT_FOLDER"

# === 3. Start Ollama and load the model ==========================================
export OLLAMA_SERVER_LOG="$RUN_DIR/ollama-server.log"
T_START=$(date +%s)
source "$REPO/scripts/ollama-server.sh" || exit 1
echo "[INFO] Server + model ready after $(( $(date +%s) - T_START ))s"

# === 4. Point Claude Code at the server ===========================================
export ANTHROPIC_BASE_URL="$OLLAMA_BASE_URL"
export ANTHROPIC_API_KEY="ollama"               # any non-empty string
export ANTHROPIC_MODEL="$MODEL"
export CLAUDE_CODE_MAX_CONTEXT_TOKENS=$CONTEXT_LENGTH
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=$MAX_OUTPUT_TOKENS
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_AUTOUPDATER=1
export DISABLE_TELEMETRY=1
export CLAUDE_CONFIG_DIR="$RUN_DIR/.claude_home"
mkdir -p "$CLAUDE_CONFIG_DIR"
# Keeps Ollama's prompt cache working across turns (skills-guide.md §5)
echo '{"totalTokensReminder": "off"}' > "$CLAUDE_CONFIG_DIR/settings.json"

# === 5. Prepare, then curate ======================================================
echo "[INFO] Preparing $PAPER_FILE (pmid $PMID)..."
claude -p "Use the pk-pe-prepare skill to prepare ${PAPER_FILE} for curation, pmid ${PMID}." \
    --dangerously-skip-permissions
if [ ! -d "$SKILL_SCRATCH_FOLDER/.paper_assets/$PMID" ]; then
    echo "[ERROR] prepare did not produce $SKILL_SCRATCH_FOLDER/.paper_assets/$PMID"; exit 1
fi

echo "[INFO] Curating with $SKILL..."
T0=$(date +%s)
claude -p "Use the ${SKILL} skill to curate paper ${PMID}. Its prepared assets are in ${SKILL_SCRATCH_FOLDER}/.paper_assets/${PMID}/. Run the full skill procedure end to end and write the final deliverables to ${SKILL_OUTPUT_FOLDER}/${PMID}/." \
    --dangerously-skip-permissions
echo "[INFO] Claude exit code: $?  curation: $(( $(date +%s) - T0 ))s"

# === 6. Check the deliverables =====================================================
OUT="$SKILL_OUTPUT_FOLDER/$PMID"
STATUS=0
for f in "$OUT/$SKILL.csv" "$OUT/$SKILL.study_info.csv"; do
    if [ -s "$f" ]; then
        echo "[INFO] OK: $f ($(python -c "import csv,sys; print(sum(1 for _ in csv.reader(open(sys.argv[1]))) - 1)" "$f") row(s))"
    else
        echo "[FAIL] missing or empty: $f"; STATUS=1
    fi
done
if [ "$STATUS" -eq 0 ]; then
    python "$RUN_DIR/.claude/skills/$SKILL/scripts/to_xlsx.py" "$OUT"
    echo "[INFO] Study info:"
    cat "$OUT/$SKILL.study_info.csv"
    echo "[INFO] SMOKE TEST PASSED in $(( $(date +%s) - T_START ))s"
else
    echo "[INFO] SMOKE TEST FAILED — look under $SKILL_SCRATCH_FOLDER for partial results"
fi
exit $STATUS
