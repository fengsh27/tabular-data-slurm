# Running open LLMs on OSC with Ollama

This guide shows how to run open-source large language models (Llama, Qwen, Gemma,
gpt-oss, ...) on the Ohio Supercomputer Center (OSC) GPUs with **Ollama**. You can
chat with them in a browser or call them from your own scripts. It assumes no
experience with Ollama, Slurm or containers.

**What's in this folder**

| File | What it's for |
|---|---|
| `README.md` (this file) | Start here. Concepts, then three ways to run Ollama step by step |
| `osc_tabular_job_template.sh` | A batch job script you can copy and edit (option C) |
| `ollama-guide.md` | Advanced notes: pinning versions, reproducible output, known model bugs |
| `skills-guide.md` | Curate PK/PE data from papers with **Claude Code + a skill**, on an OSC GPU, via Slurm |
| `skills/` | The PK/PE curation skill bundle itself — copy into any project's `.claude/skills/` |
| `osc_skills_job_template.sh` | A batch job script for running a curation skill (see `skills-guide.md`) |

---

## 1. Key ideas (read this first)

- **Ollama** runs LLMs on your own hardware. It has two parts:
  - a **server**, which loads the model onto a GPU and waits for requests, and
  - **clients**, which send it prompts: the `ollama` command line, a web chat page,
    `curl`, or your Python code.

  The server listens on a **port** (a number such as `61234`), and clients reach it at
  `http://127.0.0.1:<port>`.
- **You must run the server on a GPU compute node, not the login node.** When you `ssh`
  into OSC you land on a *login node*, which is shared by everyone and has no usable GPU.
  You ask Slurm (OSC's job scheduler) for a compute node in one of three ways:

  | Option | You get | Best for |
  |---|---|---|
  | **A. OnDemand Desktop + Open WebUI** | A remote Linux desktop in your browser with a ChatGPT-style chat page | Trying models, chatting, demos. No command line needed after setup |
  | **B. Interactive terminal** (`sinteractive`) | A shell on a GPU node | Testing prompts and scripts by hand |
  | **C. Batch job** (`sbatch`) | A script that runs unattended and writes a log | Real workloads, such as processing hundreds of files |

- **OSC already provides Ollama as a module.** `module load ollama/0.32.0` gives you:
  - the Ollama container,
  - helper commands (`ollama_start`, `ollama_pull`, `open_webui_start`, ...), and
  - a shared folder of ready-to-use models.

  You don't need to install anything.
- **Models are big files** (2–60 GB each). They live in a folder set by the environment
  variable `OLLAMA_MODELS`. By default it points to OSC's shared folder, which is
  **read-only** and contains only a few models:

  | Model tag | Size class | Notes |
  |---|---|---|
  | `tinyllama:latest` | 1B | Very fast; good for checking that things work |
  | `llama3.2:3b` | 3B | Small general model |
  | `llama3.2-vision:11b`, `llama3.2-vision:90b` | 11B / 90B | Can read images |
  | `qwen3-coder:30b` | 30B | Coding model |

  To use any other model (from [ollama.com/library](https://ollama.com/library)),
  download it into **your own** folder. See [section 6](#6-using-other-models-your-own-model-folder).

You need:
- an OSC account,
- a **project code** (looks like `PAS1234`; it decides whose allocation is billed), and
- access to the **Ascend** or **Cardinal** cluster (the clusters where OSC offers Ollama).

In the commands below, replace `PAS1234` with your project code.

---

## 2. Option A: OnDemand Desktop + Open WebUI (easiest)

This gives you a chat page in your browser, running on an OSC GPU.

1. **Open OnDemand.** Go to <https://ondemand.osc.edu> and log in with your OSC username.
2. **Start a desktop session.** In the top menu choose **Interactive Apps**, then the
   desktop app for **Ascend** or **Cardinal** (for example *Ascend Desktop*). Fill in the
   form. Exact field names can change over time; look for these:
   - **Project / account:** your project code, e.g. `PAS1234`.
   - **Number of hours:** how long the session lasts, e.g. `2`. The session and the
     models stop when this time runs out.
   - **Node type / GPUs:** choose a **GPU** node with **1 GPU**. Without a GPU the
     models are extremely slow.

   Click **Launch**.
3. **Wait for the session to start.** It shows *Queued*, then *Running*. This
   usually takes seconds to a few minutes, depending on how busy the cluster is. When
   it's running, click **Launch Ascend Desktop** (or the Cardinal equivalent) to open
   the desktop in a new browser tab.
4. **Open a terminal** inside that remote desktop (Applications menu → *Terminal*,
   or the terminal icon).
5. **Start Ollama and the chat page** by typing these commands in the terminal:

   ```bash
   module load ollama/0.32.0
   ollama_start          # prints e.g. "Ollama port: 61234"; wait ~10 s for it to load
   open_webui_start      # prints "Open_WebUI port: ...", then opens a browser after ~30 s
   ```

   Leave this terminal open. Closing it stops the server.

   *Optional:* to use models you downloaded yourself, run
   `export OLLAMA_MODELS=/path/to/your/models` **after** `module load` and **before**
   `ollama_start` (see [section 6](#6-using-other-models-your-own-model-folder)).
6. **Chat.** A browser window opens *inside the remote desktop* with Open WebUI. If it
   doesn't open, start Firefox in the desktop and go to `http://localhost:<Open_WebUI
   port>`, using the port printed in step 5.
   1. Pick a model from the drop-down at the top left (e.g. `llama3.2:3b`).
   2. Type a message.

   The first message after picking a model is slow, because the model is being loaded
   onto the GPU (a few seconds for a 3B model, up to a minute for 30B+). After that,
   replies are fast.

   Your chat history is saved in `~/.open_webui/data`, so it is still there next time.
7. **When you're finished**, stop the services, then delete the session so you don't
   keep using your allocation:

   ```bash
   open_webui_stop
   ollama_stop
   ```

   Then click **Delete** on the session card in OnDemand → *My Interactive Sessions*.

> OSC notes that its Ollama service is in an early testing phase. Do **not** use it with
> protected or sensitive data (e.g. identifiable patient data).

---

## 3. Option B: an interactive terminal on a GPU node

Use this to try prompts from the command line or to debug a script before turning it
into a batch job. Run all of this from an OSC terminal: `ssh <username>@ascend.osc.edu`,
or OnDemand → *Clusters* → *Ascend Shell Access*.

```bash
# 1. Ask for 1 GPU, 8 CPU cores and 1 hour on a compute node. Wait for the prompt
#    to change to a node name like "a0123".
sinteractive -A PAS1234 -g 1 -c 8 -t 1:00:00

# 2. Load Ollama and start the server. Send its messages to a log file so they don't
#    flood your screen.
module load ollama/0.32.0
ollama_start > ~/ollama-server.log 2>&1
echo $OLLAMA_PORT            # the port it picked, e.g. 61234

# 3. Wait until the server answers. Re-run this until it prints a list of models (JSON).
curl -s http://127.0.0.1:$OLLAMA_PORT/api/tags

# 4. Chat in the terminal (type /bye to quit).
apptainer exec --env OLLAMA_HOST=127.0.0.1:$OLLAMA_PORT $OLLAMA_IMG \
    ollama run llama3.2:3b

# ...or send one prompt with curl:
curl -s http://127.0.0.1:$OLLAMA_PORT/api/generate \
    -d '{"model": "llama3.2:3b", "prompt": "Why is the sky blue?", "stream": false}'

# 5. When done: stop the server, then leave the node (this ends the job).
ollama_stop
exit
```

Tips:
- To save typing, define a shortcut for the `ollama` command (do this after step 2):
  `alias ollama='apptainer exec --env OLLAMA_HOST=127.0.0.1:$OLLAMA_PORT $OLLAMA_IMG ollama'`.
  Then `ollama list`, `ollama ps` and `ollama run <model>` work as in the Ollama docs.
- `ollama ps` shows what is loaded and whether it is on the GPU (`100% GPU`). If it
  says CPU, the model didn't fit in GPU memory (see [section 7](#7-choosing-a-model-and-resources)).
- `sinteractive` uses the `debug` partition by default, which has a short time limit. For
  longer sessions add `-p batch`.

---

## 4. Option C: a batch job (for real workloads)

A batch job runs a script on a compute node without you watching it. Use this for
anything long or repetitive. `osc_tabular_job_template.sh` is a ready-made, commented
example that:
1. starts the server,
2. waits until it's ready,
3. sends a test prompt, and
4. shuts the server down.

```bash
# 1. Copy the template and edit it. At least change "#SBATCH --account=" to your
#    project code.
cp osc_tabular_job_template.sh my_job.sh
nano my_job.sh

# 2. Submit it.
sbatch my_job.sh                          # prints "Submitted batch job 1234567"

# 3. Watch it. ST = PD means waiting in the queue, R means running; when it
#    disappears from the list, it has finished.
squeue -u $USER

# 4. Read the output. The server's own detailed log is in a second file;
#    look there if something failed.
cat ollama-1234567.out
less ollama-server-1234567.log
```

Choose a different model without editing the file:
`sbatch --export=ALL,MODEL=qwen3-coder:30b my_job.sh`.

To do your own work, replace the example `curl` in step 5 of the script with your
program, e.g. `OLLAMA_BASE_URL="$BASE_URL" python3 my_script.py`. Your program reads the
server address from that variable (see the next section).

Two details in the template matter in batch scripts, and are easy to get wrong if you
write your own:
- **Start the server with `source ollama_start_helper`, not `ollama_start`.**
  `ollama_start` is a shell *alias*, and aliases don't work in batch scripts.
- **Set server options with the `APPTAINERENV_` prefix**, e.g.
  `export APPTAINERENV_OLLAMA_CONTEXT_LENGTH=32768`. OSC starts the server with a clean
  environment, so a plain `export OLLAMA_CONTEXT_LENGTH=...` would be ignored.

---

## 5. Calling the server from Python

Any program on the **same node** as the server can use it. The request goes to
`http://127.0.0.1:<port>`.

**Option 1: the plain HTTP API** (needs only the `requests` package):

```python
import os, requests

base_url = os.environ.get("OLLAMA_BASE_URL", "http://127.0.0.1:11434")

resp = requests.post(f"{base_url}/api/chat", json={
    "model": "llama3.2:3b",
    "messages": [{"role": "user", "content": "Summarize: Ollama runs LLMs locally."}],
    "stream": False,
    "options": {"temperature": 0},      # 0 = most repeatable answers
})
print(resp.json()["message"]["content"])
```

**Option 2: the OpenAI-compatible API.** Ollama also accepts the same requests as
OpenAI's API at `<base_url>/v1`, so code written for the `openai` package works with
two changes:

```python
from openai import OpenAI
client = OpenAI(base_url=f"{base_url}/v1", api_key="ollama")   # any non-empty key works
reply = client.chat.completions.create(
    model="llama3.2:3b",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(reply.choices[0].message.content)
```

Ask for JSON output by adding `"format": "json"`, or a JSON schema, to the `/api/chat`
request. See the [Ollama API docs](https://docs.ollama.com/api) for all options.

---

## 6. Using other models (your own model folder)

The shared OSC folder is read-only. To use other models, make your own folder and
download into it. **Run downloads inside a session or job on a compute node**
(options A–C), not on the login node.

1. **Pick a location with enough space.** Models are large (an 8B model is about 5 GB,
   30B is about 20 GB, 70B is about 40 GB). A **project folder** is better than your
   home directory, and your group can share it:

   ```bash
   mkdir -p /fs/ess/PAS1234/ollama/models
   ```

   Check your space with `quota -s`, or on OnDemand's dashboard.
2. **Point Ollama at it** every time, after `module load` and before starting the server:

   ```bash
   module load ollama/0.32.0
   export OLLAMA_MODELS=/fs/ess/PAS1234/ollama/models
   ollama_start                  # in a batch script: source ollama_start_helper
   ```

3. **Download models.** Find names on [ollama.com/library](https://ollama.com/library);
   the part after `:` is the size or variant.

   ```bash
   ollama_pull qwen3:8b          # downloads into $OLLAMA_MODELS; needs the server running
   ollama_rm qwen3:8b            # deletes a model you no longer need
   ```

   Each model downloads once. Every later session or job that sets the same
   `OLLAMA_MODELS` reuses it.

Notes:
- Once you set your own `OLLAMA_MODELS`, the models in OSC's shared folder are no
  longer listed. Pull the ones you need into your folder too (e.g. `ollama_pull llama3.2:3b`).
- To share models with a colleague, put the folder in a project directory you both belong
  to. Home directories (`/users/...`) are private to you.

---

## 7. Choosing a model and resources

- **The model must fit in GPU memory.** A rough rule: the download size plus a few GB for
  the conversation. One A100 GPU handles models up to about 30–35B (download size 20–25 GB).
  Larger models need more GPUs (`--gpus-per-node=2`) or run partly on CPU, which is much
  slower. Check with `ollama ps`.
- **Start small.** Get everything working with `tinyllama` or `llama3.2:3b`, then switch
  to the model you actually want.
- **Context length** is how much text (prompt plus answer, counted in *tokens*; one
  token is about ¾ of a word) the model sees at once. Ollama's default is small. Raise
  it if you send long documents: in a batch job set `CONTEXT_LENGTH` in the template;
  elsewhere use `export APPTAINERENV_OLLAMA_CONTEXT_LENGTH=32768` before starting the
  server. Bigger contexts use more GPU memory.
- **Reproducible results:** set `"temperature": 0` in the request options. See
  `ollama-guide.md` §5 for fully pinning a model's sampling settings.

---

## 8. Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `ollama_start: command not found` | You didn't run `module load ollama/0.32.0` in this shell. In a batch script, use `source ollama_start_helper`. |
| `curl: (7) Failed to connect` | The server is still starting (wait 10–30 s and retry), or it crashed (check `~/ollama-server.log`, or `ollama-server-<jobid>.log` for a batch job). Make sure you're on the same node as the server. |
| `model "xyz" not found` | It isn't in the current `OLLAMA_MODELS` folder. Run `ollama list` to see what's there, and `ollama_pull xyz` (into your own folder) to add it. |
| `ollama_pull` fails with permission denied | You're still using OSC's read-only shared folder. Set your own `OLLAMA_MODELS` first ([section 6](#6-using-other-models-your-own-model-folder)). |
| Answers are extremely slow | No GPU (you forgot `-g 1`, or picked a non-GPU node in OnDemand), or the model doesn't fit and is running on CPU. `ollama ps` shows which. |
| Download stops with "disk quota exceeded" | The models folder is full. Delete unused models with `ollama_rm`, or use a project folder with more space. |
| Long inputs get cut off or answers ignore the start of a document | The context length is too small. See [section 7](#7-choosing-a-model-and-resources). |
| Job sits in `PD` (pending) for a long time | The GPU queue is busy. Ask for less time, or use `-p debug` (max 1 hour) for quick tests. |

OSC's own page for this service:
<https://www.osc.edu/resources/available_software/software_list/ollama>. For account
or cluster problems, contact OSC Help (oschelp@osc.edu).

---

## 9. Going further

`ollama-guide.md` collects lessons from a larger benchmarking project. Read it before
you run long or important workloads. It covers:
- using your own container image instead of OSC's module (to pin an exact Ollama version),
- avoiding port clashes when many jobs share a node,
- making outputs fully reproducible,
- a known crash with Qwen3.6 on newer Ollama versions, and
- connecting Claude Code to a local model.

**Want to do real work with a local model, not just chat?** `skills-guide.md` shows how to run
**Claude Code skills** — structured, reusable procedures, not just prompts — against your Ollama
server to curate structured data (PK/PE tables) out of research papers, as a Slurm batch job.
