#!/bin/bash
# =============================================================================
# Ollama batch job template for OSC (Ascend / Cardinal)
#
# What it does: starts an Ollama server on a GPU node, waits until it is ready,
# sends one test prompt, then shuts the server down. Replace step 5 with your
# own work (a Python script, a loop over files, ...).
#
# How to use:
#   1. Change --account below to YOUR project code (e.g. PAS1234).
#   2. Pick a model (MODEL=...). The default runs with no download.
#   3. Submit:   sbatch osc_tabular_job_template.sh
#      Or pick the model at submit time:
#                sbatch --export=ALL,MODEL=qwen3-coder:30b osc_tabular_job_template.sh
#   4. Check progress:  squeue -u $USER      Read output:  cat ollama-<jobid>.out
#      (the server's own log is in ollama-server-<jobid>.log, useful if something fails)
#
# See README.md for an explanation of every step.
# =============================================================================
#SBATCH --job-name=ollama
#SBATCH --account=PCON0100            # <-- CHANGE to your project code
#SBATCH --gpus-per-node=1             # one GPU is enough for models up to ~35B
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=01:00:00
#SBATCH --output=ollama-%j.out        # %j = job id; stdout and stderr both go here

set -u

# === 1. Settings you may change ==============================================
MODEL=${MODEL:-llama3.2:3b}           # which model to talk to
CONTEXT_LENGTH=${CONTEXT_LENGTH:-32768}   # max tokens (prompt + answer) per request

# Where models are stored. Leave unset to use OSC's shared, read-only folder
# (/fs/ess/pub_data/ollama/models: llama3.2, llama3.2-vision, qwen3-coder, tinyllama).
# To use models you downloaded yourself, point it at your own folder, e.g.:
# export MY_OLLAMA_MODELS=/fs/ess/PAS1234/ollama/models
MY_OLLAMA_MODELS=${MY_OLLAMA_MODELS:-}

# === 2. Load OSC's Ollama module =============================================
module load ollama/0.32.0
if [ -n "$MY_OLLAMA_MODELS" ]; then
    export OLLAMA_MODELS="$MY_OLLAMA_MODELS"     # must come AFTER module load
fi
# The server runs with --cleanenv, so settings must use the APPTAINERENV_ prefix
export APPTAINERENV_OLLAMA_CONTEXT_LENGTH=$CONTEXT_LENGTH
echo "[INFO] Node: $(hostname)   Models folder: $OLLAMA_MODELS   Model: $MODEL"

# === 3. Start the server =====================================================
# ("ollama_start" is an alias that only works in interactive shells; in a batch
#  script we call the helper it points to.) It picks a free port and sets
#  $OLLAMA_PORT and $OLLAMA_PID. The server's own (very chatty) messages go to a
#  separate log file so this job's output stays readable.
SERVER_LOG=ollama-server-${SLURM_JOB_ID}.log
source ollama_start_helper > "$SERVER_LOG" 2>&1
BASE_URL="http://127.0.0.1:${OLLAMA_PORT}"
trap 'module unload ollama' EXIT              # always stop the server at the end

# === 4. Wait until it answers (up to 5 minutes) ==============================
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

# === 5. Your work goes here ==================================================
# Example: one request with curl. Programs can use the same URL
# (see README.md, "Calling the server from Python").
curl -s "$BASE_URL/api/generate" \
    -d "{\"model\": \"$MODEL\", \"prompt\": \"Say hello from OSC in one sentence.\", \"stream\": false}" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin); print(r.get("response") or r)'

# Example: run a Python script and give it the server address
# OLLAMA_BASE_URL="$BASE_URL" python3 my_script.py

echo "[INFO] Done."
