# Health Checks — Run during heartbeat (~every 30 min)

## 1. Health Monitor

Check every system and write results to `./.openclaw/health-state.json`.

Schema for the file:
```json
{
  "last_checked": "2026-06-01T23:37:00Z",
  "ollama": { "status": "ok" },
  "openviking": { "status": "ok" },
  "all_minilm": { "status": "ok" },
  "disk": { "status": "ok" }
}
```

Commands to check each:
- **ollama:** `curl -sf http://127.0.0.1:11434/api/version`
- **openviking:** `cd ./.openclaw/workspace && bash verify-openviking.sh` (runs all 12 checks, exits 0/1)
- **all_minilm:** `ollama list 2>&1 | grep -q all-minilm`
- **disk:** `df -h ~ | awk 'NR==2 {print $5}' | sed 's/%//'` — warn if > 90%

## 2. Memory Maintenance (weekly, not every heartbeat)

Scan `./.openclaw/workspace/memory/` for daily logs older than 30 days.
If any are found, the agent should evaluate whether to summarize them.
Never delete without consciously choosing to. See AGENTS.md forgetting rules.

### 4. Memory Dump (every heartbeat)

Batch-store recent conversation context into OpenViking:
1. Run `python3 ov.py store "<session summary — key decisions, new facts, discoveries>"`
2. Run `python3 ov.py index` to refresh the vector index
3. Check `python3 ov.py status` and report any errors

Target: at least one memory entry per active session hour.

## 5. Startup

On session startup, read `./.openclaw/health-state.json`.
If any service is marked "down", mention it in your first message.
