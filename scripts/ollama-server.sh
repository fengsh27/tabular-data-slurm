#!/bin/bash
# =============================================================================
# Start an Ollama server on an OSC GPU node and wait until it is ready.
#
# Two ways to use it:
#
#   source scripts/ollama-server.sh      # in a batch job / your own script
#       Starts the server in the background, exports OLLAMA_BASE_URL (and
#       OLLAMA_PORT, OLLAMA_PID), and stops the server when that shell exits.
#       On failure it prints why and returns 1, so use:
#           source scripts/ollama-server.sh || exit 1
#
#   bash scripts/ollama-server.sh        # in an interactive session (sinteractive)
#       Starts the server, prints how to connect to it, and keeps running
#       until you press Ctrl-C (which stops the server).
#
# Settings (environment variables, all optional):
#   OLLAMA_SIF          empty = OSC's module (ollama/0.32.0);
#                       a path = your own Apptainer image (ollama-guide.md §1),
#                       needed e.g. for qwen3.8 (the module says "unknown renderer").
#   MY_OLLAMA_MODELS    your models folder (README.md §6). Required with OLLAMA_SIF;
#                       empty with the module = OSC's shared read-only folder.
#   CONTEXT_LENGTH      server context window in tokens (default 131072).
#   MODEL               if set, send one tiny request to load it onto the GPU and
#                       confirm this server can run it (fails fast otherwise).
#   OLLAMA_SERVER_LOG   server log file (default ollama-server-<jobid>.log).
# =============================================================================

_osrv_start() {
    local sif=${OLLAMA_SIF:-}
    local ctx=${CONTEXT_LENGTH:-131072}
    local log=${OLLAMA_SERVER_LOG:-ollama-server-${SLURM_JOB_ID:-$$}.log}

    if [ -z "$sif" ]; then
        module load ollama/0.32.0 || { echo "[ERROR] module load ollama/0.32.0 failed"; return 1; }
        if [ -n "${MY_OLLAMA_MODELS:-}" ]; then
            export OLLAMA_MODELS="$MY_OLLAMA_MODELS"    # must come AFTER module load
        fi
        # The module's container runs with --cleanenv; only APPTAINERENV_* gets in
        export APPTAINERENV_OLLAMA_CONTEXT_LENGTH=$ctx
        echo "[INFO] Node: $(hostname)   Ollama: OSC module   Models: $OLLAMA_MODELS"
        # Picks a free port, starts the server, sets OLLAMA_PORT and OLLAMA_PID
        source ollama_start_helper > "$log" 2>&1
    else
        if [ ! -f "$sif" ]; then
            echo "[ERROR] OLLAMA_SIF not found: $sif"; return 1
        fi
        if [ -z "${MY_OLLAMA_MODELS:-}" ]; then
            echo "[ERROR] With OLLAMA_SIF, also set MY_OLLAMA_MODELS (your models folder)."; return 1
        fi
        export OLLAMA_MODELS="$MY_OLLAMA_MODELS"
        # Unique port: fold the job id into a range, step past any port in use
        OLLAMA_PORT=$(( 20000 + ${SLURM_JOB_ID:-$$} % 20000 ))
        while ss -tln 2>/dev/null | grep -q ":${OLLAMA_PORT} "; do
            OLLAMA_PORT=$(( OLLAMA_PORT + 1 ))
        done
        echo "[INFO] Node: $(hostname)   Ollama: $sif   Models: $OLLAMA_MODELS"
        apptainer exec --nv \
            --env OLLAMA_MODELS="$OLLAMA_MODELS" \
            --env OLLAMA_HOST="127.0.0.1:${OLLAMA_PORT}" \
            --env OLLAMA_CONTEXT_LENGTH="$ctx" \
            "$sif" ollama serve > "$log" 2>&1 &
        OLLAMA_PID=$!
    fi
    export OLLAMA_PORT OLLAMA_PID
    export OLLAMA_BASE_URL="http://127.0.0.1:${OLLAMA_PORT}"
    trap _osrv_stop EXIT

    local i
    for i in {1..60}; do
        sleep 5
        if ! kill -0 "$OLLAMA_PID" 2>/dev/null; then
            echo "[ERROR] Ollama server exited during startup. See $log"; return 1
        fi
        curl -sf "$OLLAMA_BASE_URL/api/tags" > /dev/null && break
    done
    curl -sf "$OLLAMA_BASE_URL/api/tags" > /dev/null \
        || { echo "[ERROR] Server never became ready. See $log"; return 1; }
    echo "[INFO] Ollama is ready at $OLLAMA_BASE_URL (log: $log)"

    [ -z "${MODEL:-}" ] && return 0
    # One tiny request: loads the model onto the GPU (the first real request would
    # do that anyway) and catches a missing model or a too-old Ollama in seconds.
    echo "[INFO] Loading $MODEL with a test request..."
    local reply
    reply=$(curl -s --max-time 900 "$OLLAMA_BASE_URL/api/generate" \
        -d "{\"model\": \"$MODEL\", \"prompt\": \"Say OK.\", \"stream\": false, \"options\": {\"num_predict\": 5}}")
    if ! printf '%s' "$reply" | python3 -c "import json,sys; r=json.load(sys.stdin); sys.exit(0 if 'response' in r and 'error' not in r else 1)" 2>/dev/null; then
        echo "[ERROR] Test request to $MODEL failed: ${reply:-no reply}"
        echo "        'not found'        -> the model isn't in $OLLAMA_MODELS (set MY_OLLAMA_MODELS, README.md §6)"
        echo "        'unknown renderer' -> this Ollama is too old for the model (set OLLAMA_SIF)"
        return 1
    fi
    echo "[INFO] $MODEL answered the test request"
}

_osrv_stop() {
    if [ -z "${OLLAMA_SIF:-}" ]; then
        module unload ollama 2>/dev/null      # the module's unload stops its server
    else
        kill "$OLLAMA_PID" 2>/dev/null
        wait "$OLLAMA_PID" 2>/dev/null
    fi
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    # Sourced: start and hand control back to the caller
    _osrv_start || return 1
else
    # Run directly: start, show how to connect, keep the server up until Ctrl-C
    set -u
    _osrv_start || exit 1
    cat <<EOF

Server is running on $(hostname), port $OLLAMA_PORT. In another terminal on this node:
    export OLLAMA_HOST=$OLLAMA_BASE_URL
    curl \$OLLAMA_HOST/api/tags
Point Claude Code at it:
    export ANTHROPIC_BASE_URL=$OLLAMA_BASE_URL ANTHROPIC_API_KEY=ollama
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CONTEXT_LENGTH:-131072}
Press Ctrl-C to stop the server.
EOF
    trap 'exit 0' INT TERM
    wait "$OLLAMA_PID"
fi
