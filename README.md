# metamorphosis-agent 🔥

**Claude Code, but local. Persistent memory. Self-editing. Open source.**

An OpenClaw-powered agent that lives on your machine, remembers everything, reads
its own source code, and rewrites itself to get better. No cloud, no account, no
bullshit.

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
├── ov.py            # OpenViking CLI — semantic vector memory
├── memory/          # Daily session logs
└── .openclaw/       # Config, approvals, knowledge

scripts/
├── setup-warp-oss.sh        # Warp OSS builder (remote)
├── build-warp.sh            # Warp OSS builder (local, WSL-friendly)
└── verify-openviking.sh     # Memory system health check
```

## The memory system (OpenViking)

The agent stores everything in a local vector database powered by **Ollama +
all-minilm**. Across sessions — weeks apart — it remembers who you are, what
you're working on, decisions you made, and lessons learned.

```bash
python3 ov.py find "what were we working on last week"
python3 ov.py store "decided to use Postgres for the new project"
python3 ov.py status
```

No cloud, no sync, no accounts. Your memory stays on your machine.

## Self-editing

The agent has access to its own workspace. It reads and modifies its own config
files — AGENTS.md, SOUL.md, TOOLS.md — to adapt to how you work. It writes its
own memory summaries during heartbeats. It's not a static template; it grows
with you.

## Private search (SearXNG)

Optional self-hosted search engine at `localhost:8888`. No Google, no tracking.
The agent uses it for web searches without leaking your queries.

## Requirements

- **Linux** (macOS works, WSL2 works)
- **Node.js 18+** (for OpenClaw)
- **Python 3** (for OpenViking CLI)
- **An LLM API key** (DeepSeek, OpenAI, Anthropic — bring your own)

## License

MIT — do whatever you want with it.
