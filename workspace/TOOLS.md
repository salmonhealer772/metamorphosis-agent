# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Search Tools

### `search_advanced.py` — Multi-source deep search

**Location:** `search_advanced.py` (workspace root)

**Sources:** Wikipedia API, Wikidata API, DuckDuckGo Instant Answers API

**What each source provides:**
- `wikipedia` — Full-text search of Wikipedia articles. Encyclopedic depth.
- `wikidata` — Entity search (structured data: IDs, labels, descriptions, relationships).
- `ddg-abstracts` — DuckDuckGo Instant Answers API. Returns an abstract, related
  topics, and category info. **Not full web search** — poor recall for news,
  time-sensitive, or niche queries.
  (Legacy name `duckduckgo` still works with deprecation warning.)

**For full web results**, use the built-in `web_search` tool (DuckDuckGo HTML scrape).

**Usage:**
```bash
python3 search_advanced.py "<query>" [count] [sources]
```

- `count`: results per source (default: 5)
- `sources`: comma-separated — `wikipedia`, `wikidata`, `ddg-abstracts` (default: all three)

**Examples:**
```bash
# All sources, default 5 each
python3 search_advanced.py "2026 FIFA World Cup"

# Specific sources — Wikipedia + Wikidata for research depth
python3 search_advanced.py "machine learning" 3 wikipedia,wikidata

# Just DuckDuckGo Instant Answers (abstracts, not web results)
python3 search_advanced.py "theory of relativity" 5 ddg-abstracts
```

**When to use it:**
- **Research-heavy queries** needing Wikipedia + Wikidata depth
- **Fact verification** across multiple sources
- **Structured knowledge** from Wikidata (entities, IDs, descriptions)
- Pair with `web_fetch` to pull full articles from top results

**Tier system:**
- **Tier 1** — `web_search` (fast, live web results, good for news/current events)
- **Tier 2** — `search_advanced.py` (Wikipedia + Wikidata depth, DDG abstracts)
- **Tier 3** — `web_fetch` (full article content from specific URLs)
Use `search_advanced.py` when you need research depth, not just a quick link.

---

### Built-in `web_search`

- Default: DuckDuckGo HTML search (no API key needed)
- Fast, lightweight, single-source
- Good for quick questions, current events, news

---

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

## Mem0 (Memory Plugin)
Mem0 is installed as an OpenClaw plugin. All memory operations are automatic.
- `openclaw mem0 status` — health check
- `openclaw mem0 search "query"` — search memories
- `openclaw mem0 list` — list all memories


