---
name: auto-capture-openviking
description: "Auto-captures every user message and agent response to memory/YYYY-MM-DD.md for passive OpenViking indexing"
metadata:
  openclaw:
    emoji: "🧠"
    events:
      - "message:received"
      - "message:sent"
    requires:
      bins: ["node"]
    install:
      - id: "managed"
        kind: "directory"
homepage: "https://github.com/salmonhealer772/metamorphosis-agent"
---

# Auto-Capture OpenViking

Passively stores every conversation turn into the agent's daily memory log.
OpenViking indexes the file automatically.

**How it works:**
- `message:received` → appends user message to `memory/YYYY-MM-DD.md`
- `message:sent` → appends agent response to `memory/YYYY-MM-DD.md`
- OpenViking's `ov.py index` already watches this file
- Agent reads today's log on startup per AGENTS.md

**Env var required:** `OPENCLAW_WORKSPACE_DIR` pointing to the workspace root
(e.g. `~/.openclaw/workspace`). Set automatically by the setup.sh-generated
`run.sh`.

**Enable:**
```bash
openclaw hooks enable auto-capture-openviking
openclaw gateway restart
```
