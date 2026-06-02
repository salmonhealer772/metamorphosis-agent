# metamorphosis-agent — Diagnostic Prompt

Paste this to the fresh agent to run a full health check:

---

Run a complete diagnostic of all my local services and tools. Test every single component and report pass/fail for each.

## Checks

### 1. Python dependencies
- `python3 -c "import openviking; print(openviking.__version__)"` — should print version
- `python3 -c "import searx"` — should not error

### 2. OpenViking (ov.py)
- `cd ~/.openclaw/workspace && python3 ov.py status` — should show "Semantic search: OK"
- `python3 ov.py store "diagnostic test entry $(date)"` — should store without timeout
- `python3 ov.py find "diagnostic"` — should return at least 1 result

### 3. RepoMap tool
- `ls -la ~/.openclaw/tools/repomap` — file should exist and be executable
- `~/.openclaw/tools/repomap ~/.openclaw/workspace/scripts 256` — should generate a structure map

### 4. SearXNG (private search)
- `curl -sf http://127.0.0.1:8888 > /dev/null && echo "LISTENING"` — port should be up
- `curl -s http://127.0.0.1:8888/search?q=test\&format=json | python3 -m json.tool` — should return JSON search results
- Check: `SEARXNG_SETTINGS_PATH` env var points to `~/.config/searxng/settings.yml`

### 5. Ollama / embeddings
- `curl -s http://127.0.0.1:11434/api/tags | python3 -c "import sys,json; print([m['name'] for m in json.load(sys.stdin)['models']])"` — should include all-minilm

### 6. File structure
- `ls -d ~/.openclaw/workspace/.openviking/vectordb 2>/dev/null && echo "EXISTS"` — should exist
- `ls ~/.openclaw/tools/` — should list repomap

### 7. Git
- `cd ~/.openclaw/workspace/metamorphosis-agent && git log --oneline -3` — should show the 4 fix commits

## Output format

For each component print:
```
### <Component Name> — ✅ PASS / ❌ FAIL
<details>
<summary>Details</summary>

```
<command output>
```
</details>
```
