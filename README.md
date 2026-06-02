# metamorphosis-agent 🐢

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

```bash
git clone https://github.com/salmonhealer772/metamorphosis-agent.git
cd metamorphosis-agent
chmod +x setup.sh && ./setup.sh
```

No sudo required. Supports `--help`, `--verbose`, `--no-colour`.

## What you get

```
workspace/
├── AGENTS.md        # Agent rules, behavioral guardrails, memory workflow
├── SOUL.md          # Personality — direct, helpful, no filler
├── IDENTITY.md      # Your agent's name, emoji, self-description
├── USER.md          # Who you are — name, timezone, preferences
├── TOOLS.md         # Local infra — OpenViking, SearXNG, RepoMap
├── HEARTBEAT.md     # Periodic health checks, memory maintenance tasks
├── MEMORY.md        # Curated long-term memory index (agent-maintained)
├── ov.py            # OpenViking CLI — semantic vector memory (on PATH)
├── memory/          # Daily session logs
└── .openclaw/       # Config, approvals, knowledge, health state

scripts/
├── repomap              # Codebase understanding (tree-sitter + PageRank)
├── start-searxng.sh     # Start private search
├── stop-searxng.sh      # Stop private search
├── setup-warp-oss.sh    # Warp OSS builder (remote)
├── build-warp.sh        # Warp OSS builder (local)
└── verify-openviking.sh # Memory health check

diagnostics/
└── agent-diagnostic-prompt.md  # Full health check prompt
```

## Health awareness — body feeling

The agent maintains `~/.openclaw/health-state.json` — a structured file that
tracks every subsystem. On startup it reads this file and proactively reports
anything that's down:

> "Btw, Ollama isn't running — starting it now."
> "SearXNG is down — restarting it."

Ask "how do you feel?" and it runs a live scan of Ollama, OpenViking, embeddings
model, disk space, RepoMap, and SearXNG — then reports structured status for
each. No poetry about body parts.

## Memory — cross-session, persistent

Vector database powered by **Ollama + all-minilm**. Install flow:

1. Ollama installed without sudo, auto-starts on login via `~/.profile`
2. Service confirmed running BEFORE model is pulled (fixes silent failure)
3. `all-minilm` model pulled with automatic retry if first attempt fails
4. `ov.py` config written, storage directory created
5. `ov.py status` verifies semantic search is online

```bash
ov.py find "what were we working on last week"
ov.py store "decided to use Postgres for the new project"
ov.py status
```

`ov.py` is on PATH (`~/.local/bin/ov.py`). No `cd` required.

## Private search — SearXNG

Self-hosted at `localhost:8888`. No Google, no tracking.

Always on by default — auto-starts during setup and on every login via
`~/.profile`. The module import issue (ModuleNotFoundError from running
outside the clone directory) is fixed by `cd ~/searxng` before launch.

The agent can stop SearXNG with `~/scripts/stop-searxng.sh` if needed,
but default is always available.

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

`repomap` is on PATH (`~/.local/bin/repomap`). Dependency `aider-chat` is
installed during setup.

## Setup script

`setup.sh` follows the [ralish/bash-script-template](https://github.com/ralish/bash-script-template)
standard — proper trap handlers, temp file cleanup, sourcing guard, exit codes.

**Zero sudo** at any point — pip.pyz with `--break-system-packages` handles
Ubuntu 24.04's PEP 668, Python venv as fallback. Every step verifies before
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
