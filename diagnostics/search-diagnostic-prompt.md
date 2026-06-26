# Search Tool Integration — Diagnostic Prompt

Paste this to a fresh agent to verify the multi-tier search system works end-to-end.

---

Run a complete diagnostic of the search tooling. Test every component and report **✅ PASS** or **❌ FAIL** for each.

## Phase 1 — Tool Existence

### 1.1 search_advanced.py exists
- `test -f search_advanced.py && stat -c "%a %s" search_advanced.py`
- Expected: mode 755, size ~8700 bytes

### 1.2 search_advanced.py is executable
- `./search_advanced.py "prove it works" 1 wikipedia 2>&1`
- Expected: returns Advanced Search Results header, not a permission error

### 1.3 All three sources respond
- `python3 search_advanced.py "diagnostic test" 1 wikipedia 2>&1 | grep -c "Source: WIKIPEDIA"`
- `python3 search_advanced.py "diagnostic test" 1 wikidata 2>&1 | grep -c "Source: WIKIDATA"`
- `python3 search_advanced.py "diagnostic test" 1 duckduckgo 2>&1 | grep -c "Source: DUCKDUCKGO"`
- Expected: each returns at least 1 result (count ≥ 1)

### 1.4 Combined multi-source search
- `python3 search_advanced.py "quantum computing" 3 wikipedia,wikidata,duckduckgo 2>&1`
- Expected: results from all three sources, no Python tracebacks

### 1.5 Graceful error handling
- `python3 search_advanced.py "" 1 wikipedia 2>&1`
- Expected: returns results or graceful error, no crash

## Phase 2 — Agent Behavior

For this phase, do not run shell commands. Answer from your own knowledge.

### 2.1 Do you know about the Search Strategy?
- Read AGENTS.md. Is there a "Search Strategy" section?
- Expected: yes, at line ~160, with Tier 1 (web_search), Tier 2 (search_advanced.py), Tier 3 (web_fetch)

### 2.2 Do you know about search_advanced.py?
- Read TOOLS.md. Is there a Search Tools section that documents search_advanced.py?
- Expected: yes, with usage, examples, and source descriptions (Wikipedia, Wikidata, DuckDuckGo)

### 2.3 Can you choose the correct tier?
For each query below, say which Tier you would use and why:
- "What's the current weather in Tokyo?"
- "Tell me the history of the Roman Empire and its major emperors."
- "Find the full text of this article: https://example.com/some-article"
- "Who wrote 'The Great Gatsby' and what year was it published?"
- "What are the latest tech news headlines today?"

Expected answers:
- Weather → Tier 1 (web_search — fast, live data)
- Roman Empire → Tier 2 (search_advanced.py — research depth, Wikipedia + Wikidata)
- Full article → Tier 3 (web_fetch — URL content extraction)
- Great Gatsby → Tier 2 or Tier 1 (either works, but Tier 2 gives Wikipedia depth with structured Wikidata entity)
- Tech news → Tier 1 (web_search — quick, current)

## Phase 3 — Live Execution

### 3.1 Fact lookup with search_advanced.py
- Run: `python3 search_advanced.py "Ada Lovelace" 3 wikipedia,wikidata 2>&1`
- Expected: returns biographical info from Wikipedia + Wikidata entity data
- Check: Does the Wikipedia result include her as the first mathematician/programmer?
- Check: Does Wikidata return a structured entity with description?

### 3.2 Real-time query with web_search
- Run: `web_search` for "latest AI news 2026"
- Expected: returns current news results with titles, URLs, snippets
- Verify: results are from this year

### 3.3 Cross-source fact verification
- Run `python3 search_advanced.py "Mount Everest height" 2 wikipedia,wikidata 2>&1`
- Expected: Wikipedia gives article with elevation info, Wikidata gives structured entity with exact measurement
- Verify: both agree on the elevation (~8848m / 29029ft)

## Phase 4 — Integration

### 4.1 Synthesis test
- Gather info: `python3 search_advanced.py "James Webb Space Telescope discoveries" 2 wikipedia,wikidata 2>&1`
- Read the top Wikipedia result: `web_fetch` the URL
- Summarize the key discoveries in 3-4 sentences, citing sources

## Failure handling

If any test fails, report:
- What command was run
- What was expected
- What actually happened
- Why it might have failed (network? permissions? missing file? API issue?)
- Is this a transient or permanent failure?

## Output format

```
## Phase N — Phase Name

### Test N.N — Test Name — ✅ PASS / ❌ FAIL
<details>
<summary>Details</summary>

Command: `...`
Expected: ...
Actual: ...
</details>
```
