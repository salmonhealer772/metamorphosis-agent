# metamorphosis-agent ✨

**Claude Code, but local. Persistent memory. Self-editing. Open source.**

An OpenClaw-powered agent that lives on your machine, remembers everything,
reads its own source code, and rewrites itself to get better. No cloud, no
account, no bullshit. Ships working out of the box.

## What makes it different

| Claude Code | metamorphosis-agent |
|---|---|
| Cloud-dependent | **Fully local** (except LLM API call) |
| No cross-session memory | **Vector memory via OpenViking** |
| Can't touch its own config | **Self-editing** — reads and rewrites its own source |
| Account required | **Zero accounts** — bring your own API key |
| CLI only | **Multi-channel** — webchat, Signal, Discord, terminal |
| Stateless shell | **Full tool access** — filesystem, browser, search, git |

## Quick start

Clone the repo, then run setup — it'll ask where you want everything:

```bash
git clone https://github.com/salmonhealer772/metamorphosis-agent.git
bash metamorphosis-agent/setup.sh
```

Notice there's **no `cd` into the clone** — the script runs from wherever
you are. During setup, you'll be prompted for an install directory:

```
→ Install directory
  Default: /home/you/metamorphosis-agent
  (All agent files go here. Leave empty for default.)
  Path: /home/you/my-agent
```

Enter a path like `~/my-agent` and **everything** — config, workspace, scripts,
dependencies — goes into that one directory. The original clone is
auto-deleted when setup finishes. Your shell stays wherever it was —
no getting stranded in an empty directory.

If you want to install right where the clone is, hit Enter to accept the
default. All files stay inside that directory — no system-wide installs,
no `~/.profile` edits, nothing scattered around.

No sudo required. Supports `--help`, `--verbose`, `--no-colour`.

To skip the API key prompt, pass a `.env` file:

```bash
# .env file (provider-specific key name or generic LLM_API_KEY / API_KEY)
DEEPSEEK_API_KEY=sk-abc123...

./setup.sh --env-file .env
```

## Usage

```bash
cd /path/to/your/install/dir && ./run.sh
```

The run.sh path is printed at end of setup:

```
✅ Metamorphosis ready in: /home/you/my-agent
   cd /home/you/my-agent && ./run.sh
```

## What you get

Inside your install directory:

```
my-agent/
├── run.sh              # Start the agent (portable entry point)
├── setup.sh            # Can re-run to update existing install
├── README.md
├── .local/bin/         # node, npm, openclaw (local binaries)
├── .openclaw/          # OpenClaw config, workspace, tools, health state
│   ├── workspace/      # Agent workspace (AGENTS.md, SOUL.md, ov.py, memory)
│   ├── tools/          # repomap and other tools
│   └── health-state.json
├── .openviking/        # OpenViking vector store config + data
├── scripts/            # Helper scripts
├── workspace/          # Source workspace template
├── diagnostics/
├── .gitignore
├── .setup-complete
└── .npm-cache/
```

Delete the directory and everything is gone — zero system pollution.

## Structure

```
workspace/                    (inside .openclaw/)
├── AGENTS.md                 # Agent rules, behavioral guardrails, memory workflow
├── SOUL.md                   # Personality — direct, helpful, no filler
├── IDENTITY.md               # Your agent's name, emoji, self-description
├── USER.md                   # Who you are — name, timezone, preferences
├── TOOLS.md                  # Local infra — OpenViking, RepoMap
├── HEARTBEAT.md              # Periodic health checks, memory maintenance tasks
├── MEMORY.md                 # Curated long-term memory index (agent-maintained)
├── ov.py                     # OpenViking CLI — semantic vector memory
├── memory/                   # Daily session logs
└── .openviking/              # Vector store data

scripts/
├── repomap                   # Codebase understanding (tree-sitter + PageRank)
├── setup-warp-oss.sh         # Warp OSS builder (remote)
├── build-warp.sh             # Warp OSS builder (local)
└── verify-openviking.sh      # Memory health check

diagnostics/
└── agent-diagnostic-prompt.md  # Full health check prompt
```

## Health awareness — body feeling

The agent maintains `health-state.json` inside `./.openclaw/` — a structured
file that tracks every subsystem. On startup it reads this file and proactively
reports anything that's down:

> "Btw, Ollama isn't running — starting it now."
> "Disk is getting full."

Ask "how do you feel?" and it runs a live scan of Ollama, OpenViking, embeddings
model, disk space, and RepoMap — then reports structured status for
each. It reads health-state.json and reports actual service statuses — this is part of its identity in SOUL.md, not a checklist task.

## Memory — cross-session, persistent

Vector database powered by **Ollama + all-minilm**. Install flow:

1. Ollama installed without sudo
2. Service confirmed running BEFORE model is pulled (fixes silent failure)
3. `all-minilm` model pulled with automatic retry if first attempt fails
4. `ov.py` config written, storage directory created
5. OpenViking import + config verified

`ov.py` is on PATH after setup (symlinked to `.local/bin/ov.py`):

```bash
cd /path/to/install/dir
. .local/bin/ov.py find "what were we working on last week"
. .local/bin/ov.py store "decided to use Postgres for the new project"
. .local/bin/ov.py status
```

Or, from inside the install dir via the full path:

```bash
./.local/bin/ov.py find "query"
```

## Behavioral guardrails

Two rules in AGENTS.md that shape how the agent acts:

- **Check Before Act** — Pauses before jumping into implementation. If you're
  describing an idea, not asking to build it yet, it asks: "Want me to start
  on this or are we still planning?" Normal tool use and conversation are
  unaffected.
- **Show Don't Tell** — When asked to read a file, it reads and displays the
  contents instead of acknowledging or summarizing. Output over description.

## Codebase understanding — RepoMap

When code is mentioned, the agent auto-generates a structural map using
tree-sitter AST parsing and PageRank ranking. Supports Python, TypeScript,
JavaScript, Go, Rust, Java, C++, Shell, Markdown, and more.

The `repomap` tool is at `.openclaw/tools/repomap` inside your install
directory. Dependency `aider-chat` is installed during setup.

## Setup script

`setup.sh` follows the [ralish/bash-script-template](https://github.com/ralish/bash-script-template)
standard — proper trap handlers, temp file cleanup, sourcing guard, exit codes.

**Zero sudo** at any point. Creates an isolated Python venv for all
pip dependencies — sidesteps PEP 668 (`externally-managed-environment`)
without needing `--break-system-packages`. Falls back to `--break-system-packages`
only if Python's `venv` module is unavailable. Every step verifies before
proceeding and retries on failure.

## Diagnostics

Paste `diagnostics/agent-diagnostic-prompt.md` to the agent for a full
blanket check across all components with pass/fail reporting.

## Requirements

- **Linux** (macOS works, WSL2 works)
- **Node.js 18+** (for OpenClaw)
- **Python 3** (for OpenViking CLI)
- **An LLM API key** (DeepSeek, OpenAI, Anthropic, etc.)

## License

MIT — do whatever you want with it.
