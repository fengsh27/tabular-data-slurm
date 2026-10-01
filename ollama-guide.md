# Ollama on OSC: advanced notes

> **New to Ollama or OSC? Start with [README.md](README.md).** It explains the basics and
> uses OSC's built-in `ollama` module, which is the easiest route. This file is the next
> step, for long or important workloads.

These notes come from a benchmarking project (pk-summary / pk-individual) that ran
qwen3.6, qwen3.8, gemma4 and gpt-oss through hundreds of Slurm jobs. They cover:
- how to run Ollama from **your own pinned container** instead of OSC's module,
- how to avoid port clashes,
- how to make output reproducible, and
- the model bugs that actually caused problems in that project.

Paths such as `~/ollama/...` and `tabular-data-benchmark/...` refer to the original
author's account. Home directories at OSC are private, so substitute your own (ideally
project) paths.

## 0. OSC's module or your own container?

`module load ollama/<version>` (see the README) runs the same upstream Ollama container
that OSC builds and maintains. Use it unless you need one of the following:

| You need... | Why the module doesn't cover it |
|---|---|
| A specific older Ollama version | The module offers a fixed set (`module spider ollama`: 0.5.13 … 0.32.0). Qwen3.6 needs a build from before 2026-04 (§6). |
| Full control over server settings | The module starts the server with `--cleanenv`. Other settings only get through with the `APPTAINERENV_` prefix (e.g. `APPTAINERENV_OLLAMA_CONTEXT_LENGTH`). |
| The server reachable only from its own node | The module binds `0.0.0.0` (reachable from other nodes); §3 binds `127.0.0.1`. |

Both routes can share the same model folder (`OLLAMA_MODELS`). A model pulled with one
works with the other, as long as the Ollama version is new enough for that model.

## 1. Using your own container

Ollama runs from an Apptainer image built from the upstream Docker image — there is no
`apptainer`/`singularity` module to load, it's already on `PATH` (`apptainer version`
to check). Build it once per host directory you want to keep it in:

```bash
mkdir -p ~/ollama && cd ~/ollama
apptainer pull ollama.sif docker://ollama/ollama:latest
```

**Pin the file, don't keep re-pulling `latest`.** `docker://ollama/ollama:latest` is a
floating tag: pulling it again later silently gives you a different served version.
This project hit a real regression from doing that — see [Known issue: qwen3.6 crashes
newer Ollama builds](#known-issue-qwen36-crashes-newer-ollama-builds) below. Practical
rule: pull once, rename/copy the `.sif` somewhere stable, and only re-pull deliberately
(recording the date and the version you get via `apptainer exec ollama.sif ollama
--version`). This project keeps two images side by side for exactly this reason:

| file | pulled | served version | status |
|---|---|---|---|
| `ollama-old.sif` | 2026-04-03 | v0.20.0 | required for qwen3.6 (see below) |
| `ollama.sif` | 2026-08-26 | v0.33.0 | fine for qwen3.8, gemma4, gpt-oss |

## 2. Model storage

Models live outside the container, in a directory you point Ollama at with
`OLLAMA_MODELS`. Put it somewhere persistent (home or a project scratch directory that
isn't purged), not the job's scratch — it's a shared cache across every job/model:

```bash
export OLLAMA_MODELS=~/ollama/models   # or a project path; ~15-30 GB per model
mkdir -p "$OLLAMA_MODELS"
```

Every job that serves a model exports this same path so it reuses the cache instead of
re-downloading. Layout is Ollama's own (`models/manifests/registry.ollama.ai/library/<name>/<tag>`,
`models/blobs/`) — don't hand-edit it.

## 3. Starting the server in a job

The pattern every job script here uses:

```bash
#SBATCH --gres=gpu:a100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G

OLLAMA_SIF=~/ollama/ollama.sif        # or ollama-old.sif, see model table below
OLLAMA_MODELS=~/ollama/models

# Unique port: never hardcode 11434. Two jobs can land on the same node, and a
# stale/foreign server on 11434 would otherwise get "adopted" by accident.
# Fold the (large, 7-digit) Slurm job id into a safe range and linear-probe if busy.
OLLAMA_PORT=$(( 20000 + SLURM_JOB_ID % 20000 ))
while ss -tln 2>/dev/null | grep -q ":${OLLAMA_PORT} "; do
  OLLAMA_PORT=$(( OLLAMA_PORT + 1 ))
done
export OLLAMA_HOST="127.0.0.1:${OLLAMA_PORT}"
BASE_URL="http://127.0.0.1:${OLLAMA_PORT}"

apptainer exec --nv \
  --env OLLAMA_MODELS="$OLLAMA_MODELS" \
  --env OLLAMA_HOST="$OLLAMA_HOST" \
  --env OLLAMA_CONTEXT_LENGTH=131072 \
  "$OLLAMA_SIF" \
  ollama serve &
OLLAMA_PID=$!

# Poll readiness; die fast if OUR process exited (don't silently wait forever,
# and don't let a neighbour job's server on a colliding port look "ready").
for i in {1..60}; do
  sleep 5
  if ! kill -0 "$OLLAMA_PID" 2>/dev/null; then
    echo "[ERROR] Ollama process exited (port conflict or crash)."; exit 1
  fi
  curl -sf "${BASE_URL}/api/tags" > /dev/null && break
done

# ... run your workload against $BASE_URL ...

kill "$OLLAMA_PID" 2>/dev/null
wait "$OLLAMA_PID" 2>/dev/null
```

`--nv` is required (GPU passthrough into the container). `--gres=gpu:a100:1` +
`--mem=64G` + `--cpus-per-task=8` is the sizing used across every job in this project
for a single ~20-35B dense model; it hasn't been pushed lower deliberately.

**`OLLAMA_CONTEXT_LENGTH`** sets the server's default context window. If a client sends
its own `num_ctx` per request (below), that overrides this default — the server value
only matters as a fallback / upper bound. Contexts actually used here:

| workload | server `OLLAMA_CONTEXT_LENGTH` | client override |
|---|---|---|
| simple single-shot prompt | 65536 | `--num-ctx 65536` (same) |
| pipeline / multi-agent | 131072 | 49152 (agent code sends this per request) |
| Claude Code + a skill | 196608 | none — Code uses the server default directly |

For the skills case, also set `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to the **same** number.
Claude Code doesn't recognize a local Ollama model name and defaults to assuming 200k
context; if that's above what the server actually has, requests silently trigger
`llama-server`'s context-shift (truncation) instead of erroring, which is much worse
than a clean failure. Keep the two in lockstep.

## 4. Loading a model

```bash
apptainer exec --nv --env OLLAMA_MODELS="$OLLAMA_MODELS" --env OLLAMA_HOST="$OLLAMA_HOST" \
  "$OLLAMA_SIF" ollama pull qwen3.6:35b
```

This can be done as a one-off interactive step against a server you started manually,
or as the first thing a job does before serving requests — either way it lands in the
shared `$OLLAMA_MODELS` and every later job with the same env var reuses it (no re-pull).

Models actually installed and used in this project, from Ollama's library:

| model | tag pulled | notes |
|---|---|---|
| Qwen3.6 (dense, 35B) | `qwen3.6:35b` | see the crash-bug section — needs the old container |
| Qwen3.8 (dense, 27B, hybrid attention) | `qwen3.8:27b` | fine on the current container |
| Gemma 4 | `gemma4:31b` (also have `gemma4:26b`) | |
| gpt-oss | `gpt-oss:20b` | |
| Llama 4 | `llama4:scout` | |

### MedGemma

MedGemma is not in Ollama's own model library (as of this writing), so `ollama pull
medgemma` will fail. Ollama can pull GGUF weights directly from a Hugging Face repo
instead, using the `hf.co/<user>/<repo>` form:

```bash
ollama pull hf.co/unsloth/medgemma-27b-text-it-GGUF:Q4_K_M
# or the 4B multimodal variant, e.g.:
ollama pull hf.co/unsloth/medgemma-4b-it-GGUF:Q4_K_M
```

Check the actual repo name and available quantizations on huggingface.co before
pulling — several community GGUF conversions exist with slightly different repo names
and quant tags; pick one and pin the exact `repo:tag` you tested, same reasoning as
pinning the container above. **This has not yet been run on this cluster** — nothing
in this project has loaded MedGemma — so treat the command above as a starting point
to verify, not a proven recipe: confirm the pull succeeds, the model loads
(`ollama run <tag> "hi"`), and check `ollama show <tag> --parameters` for its default
sampling params the same way this project did for Qwen (next section) before relying
on it for anything.

## 5. Deterministic decoding: custom `-t0` variants

For anything that needs reproducible output (grading, benchmarking), don't rely on a
model's shipped defaults — pin sampling explicitly with an Ollama `Modelfile` and
create a derived tag:

```
# qwen36-t0.Modelfile
FROM qwen3.6:35b
PARAMETER temperature 0
PARAMETER top_p 1
PARAMETER top_k 1
PARAMETER seed 42
PARAMETER presence_penalty 0
```

```bash
apptainer exec --nv --env OLLAMA_MODELS="$OLLAMA_MODELS" --env OLLAMA_HOST="$OLLAMA_HOST" \
  "$OLLAMA_SIF" ollama create qwen3.6:35b-t0 -f qwen36-t0.Modelfile
```

Then request `qwen3.6:35b-t0` instead of the base tag. Two things worth checking per
model before you assume temperature 0 is enough:

- **`top_p`/`top_k` are inert once `temperature=0`, but pin them anyway** — a derived
  model should carry no inherited sampling randomness if someone later re-derives from
  it.
- **Check `ollama show <model> --parameters` for a non-neutral default you didn't
  expect.** `qwen3.6:35b` ships `presence_penalty=1.5`; every other model here
  (`qwen3.8:27b`, gemma4) ships it unset/0. A presence penalty fights structured/JSON
  output (it penalizes re-emitting tokens already used, e.g. repeated braces and
  repeated field names across list entries) and caused `qwen3.6:35b` to intermittently
  emit malformed JSON under schema-constrained decoding until pinned back to 0.
  `langchain_ollama.ChatOllama` has no field for `presence_penalty` at all — passing it
  as a constructor kwarg is silently dropped — so this can only be fixed in the
  Modelfile, not from client code. Do this check for MedGemma too before trusting its
  output under any schema-constrained / tool-calling client.

## 6. Known issue: qwen3.6 crashes newer Ollama builds

If you rebuild `ollama.sif` from `docker://ollama/ollama:latest` today, **do not run
qwen3.6 through agentic / tool-calling / JSON-schema-constrained requests against it**
(this includes Claude Code with a skill, or any LangChain agent loop) — it will
eventually hit a CUDA illegal-memory-access crash
(`ggml_cuda_op_gated_delta_net_fused_cache`).

- Root cause: a regression in llama.cpp's Gated-Delta-Net prompt-cache path, bisected
  to a commit range between 2026-03-19 (last known good) and 2026-04-03 (first
  broken). It reproduces specifically under "agentic frameworks, large prompts with
  dynamic context, multi-turn tool-call loops" — exactly this project's workload.
- Upstream status (checked against Ollama v0.34.2, 2026-09-15, and the two releases
  before it): **open, unfixed**. `ollama/ollama#17434` has no maintainer response;
  `ggml-org/llama.cpp#21383` was closed "not planned". There are other unresolved
  Qwen3.5/3.6 GatedDeltaNet bugs in Ollama too (e.g. `#15865`) — upgrading further is
  not a fix.
- **The fix used here**: keep a container pulled *before* the regression window
  (`ollama-old.sif`, pulled 2026-04-03, served version v0.20.0) and run qwen3.6 through
  that one specifically. It was proven clean for this exact workload by a dedicated
  smoke test (~130 sequential tool-calling turns, zero crashes, every call HTTP 200).
  Every crash log ever produced in this project is dated after the newer container was
  built, none before.
- **This includes OSC's module.** `ollama/0.32.0` is well past the regression, so don't
  run qwen3.6 agentic workloads on it either. The older module versions (0.5.13–0.13.1)
  predate qwen3.6 entirely and can't load it. Use your own pre-regression container.
- Qwen3.8 does **not** trigger this bug (different attention implementation) and runs
  fine on the current `ollama.sif`. Gemma models haven't been confirmed either way; this
  project ran gemma4 through `ollama-old.sif` out of caution rather than assuming it was
  safe.
- **Before trusting any newly-pulled or newly-built container with qwen3.6** (or, by
  the same logic, an untested model like MedGemma) under an agentic/tool-calling
  client: run a smoke test of ~100+ sequential tool-calling turns and check for zero
  crashes before relying on it, and note the container's build date and
  `ollama --version` output next to your results so a future regression is traceable.

## 7. Quick reference: full worked jobs

Copy-adapt one of these rather than starting from scratch:

- `tabular-data-benchmark/pk-individual/jobs/job_simple_prompt_qwen36.sh` — simplest
  full pattern: server + one Python call, single job, `ollama-old.sif`.
- `tabular-data-benchmark/pk-summary/jobs/job_pipeline_gemma4.sh` — same pattern, 131072
  server context, `gemma4:31b`.
- `tabular-data-benchmark/pk-individual/jobs/job_skills_qwen36.sh` /
  `job_skills_qwen38.sh` — the Claude Code + skill variant: Anthropic-compatible
  endpoint env vars (`ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY=ollama` — any non-empty
  string works, Ollama doesn't check it — `ANTHROPIC_MODEL`), `CLAUDE_CODE_MAX_CONTEXT_TOKENS`
  kept equal to the server's `OLLAMA_CONTEXT_LENGTH`, and a per-job `CLAUDE_CONFIG_DIR`
  so parallel jobs don't contend on `~/.claude`.
- `tabular-data-benchmark/pk-individual/jobs/bench_gpu.sh` — a minimal smoke/throughput
  test (prefill and generation tok/s) to sanity-check a server + model combination
  before committing a full run to it.
