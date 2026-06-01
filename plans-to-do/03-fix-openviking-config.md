# Plan: Fix OpenViking config + ov.py hardcoded path

**Difficulty:** 🟢 Easy — replace template block + one line in ov.py
**Code audit:** ⚠️ **Two issues found: heredoc expansion + hardcoded path**

## Issue 1: Config format is INI, needs JSON
`setup.sh` lines 168-177 write INI format. OpenViking v0.3.19 expects JSON.

Current:
```bash
cat > "$HOME/.openviking/ov.conf" << 'OVCONF'
[server]
host = 127.0.0.1
port = 11434
model = all-minilm
[workspace]
path = ~/.openclaw/workspace/.openviking
[cli]
default = python3 ~/.openclaw/workspace/ov.py
OVCONF
```

## Issue 2: `'OVCONF'` is quoted → `$HOME` won't expand
The heredoc delimiter `'OVCONF'` prevents bash from expanding `$HOME` inside the JSON. Must use unquoted `OVCONF`. Safe because the JSON has no other `$`-prefixed tokens.

## Issue 3: `ov.py` line 21 has hardcoded `/home/fade/` path
```python
WORKSPACE = os.path.expanduser("/home/fade/.openclaw/workspace")
```
Must be `~/.openclaw/workspace` so it works for any user.

## Fix

### Fix A — setup.sh (lines 168-177)
Replace the INI heredoc with unquoted JSON heredoc:
```bash
cat > "$HOME/.openviking/ov.conf" << OVCONF
{
  "storage": {
    "workspace": "$HOME/.openclaw/workspace/.openviking"
  },
  "embedding": {
    "dense": {
      "provider": "ollama",
      "api_base": "http://127.0.0.1:11434/v1",
      "model": "all-minilm",
      "dimension": 384
    },
    "max_concurrent": 2
  },
  "log": {
    "level": "ERROR",
    "output": "stdout"
  }
}
OVCONF
```

**Key:** No quotes around `OVCONF` — `$HOME` gets expanded to the real home path.

### Fix B — ov.py (line 21)
```python
# Before:
WORKSPACE = os.path.expanduser("/home/fade/.openclaw/workspace")
# After:
WORKSPACE = os.path.expanduser("~/.openclaw/workspace")
```

## Files changed
- `setup.sh` (replace heredoc, ~8 lines)
- `workspace/ov.py` (one line)

## Test
1. `cat ~/.openviking/ov.conf` → `/home/met/...` not `$HOME`
2. `python3 ov.py status` → no error, shows workspace path
