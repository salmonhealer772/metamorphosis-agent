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

**Sources:** Wikipedia API, Wikidata API, DuckDuckGo API

**Usage:**
```bash
python3 search_advanced.py "<query>" [count] [sources]
```

- `count`: results per source (default: 5)
- `sources`: comma-separated — `wikipedia`, `wikidata`, `duckduckgo` (default: all three)

**Examples:**
```bash
# All sources, default 5 each
python3 search_advanced.py "2026 FIFA World Cup"

# Specific sources
python3 search_advanced.py "machine learning" 3 wikipedia,wikidata

# Just web results
python3 search_advanced.py "latest technology news" 5 duckduckgo
```

**When to use it:**
- **Research-heavy queries** needing Wikipedia + Wikidata depth
- **Fact verification** across multiple sources
- **Structured knowledge** from Wikidata (entities, IDs, descriptions)
- Pair with `web_fetch` to pull full articles from top results

**For quick web lookups**, the built-in `web_search` tool (DuckDuckGo HTML scrape) is faster and lighter. Use `search_advanced.py` when you want breadth + depth.

---

### Built-in `web_search`

- Default: DuckDuckGo HTML search (no API key needed)
- Fast, lightweight, single-source
- Good for quick questions, current events, news

---

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

## OpenViking (Vector Memory)

- **Config:** `.openviking/ov.conf` (local to install dir)
- **Server:** Ollama (http://127.0.0.1:11434) — auto-starts on login via `~/.profile`
- **Model:** all-minilm (for embeddings)
- **CLI:** `ov.py` (on PATH — symlinked to `~/.local/bin/ov.py`)
- **Usage:** `ov.py find "query"` / `ov.py store "fact"` / `ov.py status`

---

## RepoMap (Codebase Understanding)

- **Location:** `.openclaw/tools/repomap` (local to install dir)
- **Usage:** `repomap <directory> [map_tokens]`
- **Parses:** Python, TypeScript, JavaScript, Go, Rust, Java, C++, Shell, Markdown, and more
