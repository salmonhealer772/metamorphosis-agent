# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

## OpenViking (Vector Memory)

- **Config:** `~/.openviking/ov.conf`
- **Server:** Ollama (http://127.0.0.1:11434) — auto-starts on login via `~/.profile`
- **Model:** all-minilm (for embeddings)
- **CLI:** `ov.py` (on PATH — symlinked to `~/.local/bin/ov.py`)
- **Usage:** `ov.py find "query"` / `ov.py store "fact"` / `ov.py status`

---

## RepoMap (Codebase Understanding)

- **Location:** `~/.openclaw/tools/repomap`
- **Usage:** `repomap <directory> [map_tokens]`
- **Parses:** Python, TypeScript, JavaScript, Go, Rust, Java, C++, Shell, Markdown, and more
