---
name: auto-capture-openviking
description: "Captures every conversation turn to memory/YYYY-MM-DD.md for cross-session context"
metadata:
  openclaw:
    emoji: "🧠"
    events:
      - "message:preprocessed"
    requires:
      bins: ["node"]
homepage: "https://github.com/salmonhealer772/metamorphosis-agent"
---

# Auto-Capture Daily Log Hook

Appends every incoming user message to `memory/YYYY-MM-DD.md` so
the agent reads it on startup. Works in ALL modes (gateway, embedded,
TUI) because `message:preprocessed` fires in the core agent pipeline.
