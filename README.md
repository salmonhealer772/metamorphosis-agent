# metamorphosis-agent 🐢

**Claude Code, but local. Persistent memory. Self-editing. Open source.**

An OpenClaw-powered agent that lives on your machine, remembers everything, reads
its own source code, and rewrites itself to get better. No cloud, no account, no
bullshit. Ships working out of the box.

## What makes it different

| Claude Code | metamorphosis-agent |
|---|---|
| Cloud-dependent | **Fully local** (except LLM API call) |
| No cross-session memory | **Vector memory via OpenViking** — remembers what you did last week |
| Can't touch its own config | **Self-editing** — reads and rewrites its own source |
| Account required | **Zero accounts** — bring your own API key |
| CLI only | **Multi-channel** — webchat, Signal, Discord, terminal |
| Stateless shell | **Full tool access** — filesystem, browser, search, git |

## Quick start

```bash
git clone https://github.com/salmonhealer772/metamorphosis-agent.git
cd metamorphosis-agent
chmod +x setup.sh && ./setup.sh
```

One shell command. The script installs OpenClaw, sets up vector memory (Ollama +
OpenViking), configures private search (SearXNG), and drops your agent workspace
in place. You just supply a name and an API key.

The setup script supports `--help`, `--verbose`, and `--no-colour` flags. No sudo
required at any point.

## What you get

```
workspace/
├── AGENTS.md        # Agent rules — memory workflow, self-editing, group chat
├── SOUL.md          # Personality — direct, helpful, no filler
├── IDENTITY.md      # Your agent's name, emoji, self-description
├── USER.md          # Who you are — name, timezone, preferences
├── TOOLS.md         # Local infra — OpenViking, SearXNG, RepoMap
├── HEARTBEAT.md     # Periodic health checks for your services
├── MEMORY.md        # Curated long-term memory index (agent-maintained)
├── ov.py            # OpenViking CLI — semantic vector memory (on PATH)
├── memory/          # Daily session logs
└── .openclaw/       # Config, approvals, knowledge, health state

scripts/
├── repomap                   # Codebase understanding tool (tree-sitter + PageRank)
├── start-searxng.sh          # Start private search on demand
├── stop-searxng.sh           # Stop private search
├── setup-warp-oss.sh         # Warp OSS builder (remote)
├── build-warp.sh             # Warp OSS builder (local, WSL-friendly)
└── verify-openviking.sh      # Memory system health check

diagnostics/
└── agent-diagnostic-prompt.md  # Full system health check to paste to a fresh agent
```

## Health awareness — it knows its own body

The agent maintains a `~/.openclaw/health-state.json` file that tracks every service.
On startup, it reads this file and proactively reports anything that's down:

> "Btw, Ollama isn't running — starting it now."
> "SearXNG isn't running, use start-searxng.sh if you need search."

Ask it "how do you feel?" and it checks every subsystem — Ollama, OpenViking,
embeddings model, disk space, RepoMap, SearXNG — and reports structured status
for each. No poetry about body parts, just data about the actual infrastructure.

## Memory — cross-session, persistent, automatic

The agent stores everything in a local vector database powered by **Ollama +
all-minilm**. Ollama auto-starts on login via `~/.profile`. The embedding model
is pulled during install with automatic retry if it fails. No manual setup needed.

```bash
ov.py find "what were we working on last week"
ov.py store "decided to use Postgres for the new project"
ov.py status
```

`ov.py` is on your PATH (`~/.local/bin/ov.py`). No cd required.

The agent also manages memory proactively — during heartbeats it evaluates old
daily logs for summarization. Nothing is ever deleted automatically; every
memory action is a conscious choice the agent makes.

## Self-editing

The agent reads and modifies its own config files — AGENTS.md, SOUL.md, TOOLS.md —
to adapt to how you work. It writes its own memory summaries during heartbeats.
It's not a static template; it grows with you.

The agent has two behavioral guardrails:

- **Check Before Act** — pauses before jumping into implementation. If you're
  describing an idea, not asking to build it yet, it asks: "Want me to start on
  this or are we still planning?" No building the house while you're picking
  paint colors.
- **Show Don't Tell** — when asked to read a file, it actually reads and displays
  the contents instead of summarizing or acknowledging. Output over description.

## Private search (SearXNG)

Self-hosted search engine at `localhost:8888`. No Google, no tracking.

SearXNG is installed and configured during setup but does not auto-start.
Run `~/scripts/start-searxng.sh` when you need it, `~/scripts/stop-searxng.sh`
when you're done. The agent knows to manage this lifecycle on its own — it
starts the service before searching and stops it after.

## Codebase understanding (RepoMap)

When code is mentioned, the agent auto-generates a structural map of the
codebase using tree-sitter AST parsing and PageRank ranking. Supports Python,
TypeScript, JavaScript, Go, Rust, Java, C++, shell scripts, markdown, and more.

`repomap` is on your PATH after setup (`~/.local/bin/repomap`).

## Diagnostics

To verify everything is working on a fresh install, paste the contents of
`diagnostics/agent-diagnostic-prompt.md` to the agent. It runs a blanket check
across all components and reports pass/fail.

## Setup script details

`setup.sh` follows the [ralish/bash-script-template](https://github.com/ralish/bash-script-template)
best-practices standard with proper trap handlers, temp file cleanup, and exit
codes. Supports `--help`, `--verbose`, and `--no-colour`.

Zero sudo — pip bootstrap uses `pip.pyz --break-system-packages` to handle
Ubuntu 24.04's PEP 668, with a Python venv fallback. Ollama installs without
root. Every step verifies before proceeding.

## Requirements

- **Linux** (macOS works, WSL2 works)
- **Node.js 18+** (for OpenClaw)
- **Python 3** (for OpenViking CLI)
- **An LLM API key** (DeepSeek, OpenAI, Anthropic, etc.)

## License

MIT — do whatever you want with it.
