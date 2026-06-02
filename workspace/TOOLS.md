# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

## SearXNG (Private Search Engine)

- **URL:** http://127.0.0.1:8888
- **Clone:** `~/searxng/`
- **Config:** `~/.config/searxng/settings.yml` (set via `SEARXNG_SETTINGS_PATH`)
- **Log:** `/tmp/searxng_web.log`
- **API:** `http://127.0.0.1:8888/search?q=<query>&format=json`
- **Setup:** Installed and configured by setup.sh
- **Restart:** `pkill -f searx.webapp; cd ~/searxng && SEARXNG_SETTINGS_PATH=~/.config/searxng/settings.yml nohup python3 -m searx.webapp > /tmp/searxng_web.log 2>&1 &`

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
