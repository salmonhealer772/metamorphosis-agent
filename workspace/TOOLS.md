# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

## SearXNG (Private Search Engine)

- **URL:** http://127.0.0.1:8888
- **Location:** `~/searxng/`
- **Start:** `~/searxng/start.sh`
- **Stop:** `~/searxng/stop.sh`
- **Log:** `/tmp/searxng.log`
- **Config:** `~/searxng/searx/settings.yml`
- **API:** `http://127.0.0.1:8888/search?q=<query>&format=json`
- **Setup:** Git clone from github.com/searxng/searxng, pip install --user
- **Status:** Configured in setup.sh

---

## OpenViking (Vector Memory)

- **Location:** `~/.openviking/`
- **Server:** Ollama (http://127.0.0.1:11434)
- **Model:** all-minilm (for embeddings)
- **CLI:** `ov.py` (in workspace root)
- **Usage:** `python3 ov.py find "query"` / `python3 ov.py store "fact"`

---

## RepoMap (Codebase Understanding)

- **Location:** `~/.openclaw/tools/repomap`
- **Usage:** `repomap <directory> [map_tokens]`
- **Parses:** Python, TypeScript, JavaScript, Go, Rust, Java, C++, and more
