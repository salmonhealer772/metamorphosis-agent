# metamorphosis-agent — Diagnostic Prompt

Paste this to the fresh agent to run a full health check:

---

Run a complete diagnostic of all my local services and tools. Test every single component and report pass/fail for each.

## Checks

### 1. Python dependencies
- `python3 -c "import openviking; print(openviking.__version__)"` — should print version

### 2. OpenViking (ov.py)
- `python3 ov.py status` — should show "Semantic search: OK"
- `python3 ov.py store "diagnostic test entry $(date)"` — should store without timeout
- `python3 ov.py find "diagnostic"` — should return at least 1 result

### 3. RepoMap tool
- `ls -la .openclaw/tools/repomap` — file should exist and be executable
- `.openclaw/tools/repomap scripts 256` — should generate a structure map

### 4. Ollama / embeddings
- `curl -s http://127.0.0.1:11434/api/tags | python3 -c "import sys,json; print([m['name'] for m in json.load(sys.stdin)['models']])"` — should include all-minilm

### 5. File structure
- `ls -d .openclaw/workspace/.openviking/vectordb 2>/dev/null && echo "EXISTS"` — should exist
- `ls .openclaw/tools/` — should list repomap

### 6. Git
- `git log --oneline -3` — should show recent commits

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
