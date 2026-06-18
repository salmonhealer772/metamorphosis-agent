# metamorphosis-agent — Improvement Plan

Based on the audit of what worked vs what didn't out of the box.

## Quick Wins (Easy — blast these)

### 1. Copy plans/ to ~/plans/
- **File:** `setup.sh`
- **Status:** Already copies scripts but not plans
- **Fix:** Add `cp -r "$REPO_DIR/plans/"* "$HOME/plans/" 2>/dev/null || true` next to the scripts copy
- **EFFORT:** 🟢 1 line

### 2. Fix OpenViking config format
- **File:** `setup.sh`
- **Status:** Writes INI-format config but OpenViking v0.3.22 expects JSON with specific fields (`api_base` needs `/v1` suffix)
- **Fix:** Replace the heredoc with a JSON config file matching what v0.3.22 expects
- **EFFORT:** 🟢 Easy, just needs right template

### 4. Install openviking pip package
- **File:** `setup.sh` (after pip.pyz download)
- **Status:** Not currently installed — ov.py fails without it
- **Fix:** Add `python3 /tmp/pip.pyz install --user openviking -q` after the zstandard install
- **EFFORT:** 🟢 1 line

### 5. Pull all-minilm in setup
- **File:** `setup.sh`
- **Status:** Already in setup.sh — was broken by pip issue (now fixed with pip.pyz)
- **Fix:** Should work now. Test on met_6 to confirm
- **EFFORT:** ✅ Already done, verify

### 6. Build RepoMap wrapper
- **File:** New file: `setup.sh` section or separate script
- **Status:** RepoMap doesn't exist at `~/.openclaw/tools/repomap`
- **Fix:** Write a Python wrapper script that uses aider-chat's repomap engine. Install `aider-chat` via pip.pyz. Create the wrapper at the right path.
- **EFFORT:** 🟡 10-20 lines of Python

## Medium (Need Investigation)

### 7. Knowledge tool
- **Status:** Missing. Need to check what OpenClaw's `~/.openclaw/tools/knowledge` expects
- **Effort:** 🟡 Unknown — depends on schema

### 8. Wiki tool
- **Status:** Missing. Same deal
- **Effort:** 🟡 Unknown

## Deferred (Ask User First)

---

## Version history

- 2026-06-01: Initial plan based on audit session
