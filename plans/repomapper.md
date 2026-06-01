# PLAN: RepoMapper Integration

## Goal
Give Fade instant codebase understanding — when code is mentioned, Fade auto-generates a structural repo map without being told.

## The Problem
Right now, if I say "look at this project" or start talking about code, Fade has to be explicitly told to run `ov.py repomap`. That's friction. The goal is: code comes up → repo map happens automatically.

## Why RepoMapper (the real reason)
Aider's repo map is already installed and works, but it's buried inside the aider-chat package — importing internal classes, instantiating a full Model object, passing an InputOutput handler. It works, but it's fragile. RepoMapper is the exact same algorithm (tree-sitter + PageRank) extracted as a clean standalone CLI tool and MCP server. Cleaner, more maintainable, MCP-native.

## Execution Log

### Step 0: Python 3.13 ✅
User ran `sudo apt install python3.13 python3.13-venv` via deadsnakes PPA. Python 3.13.13 installed at `/usr/bin/python3.13`.

### Step 1: RepoMapper Install ✅
Installed in `~/venv/repomapper/`. CLI works but has a bug: crashes with `TypeError: expected string or buffer` when the generated map is empty (tries to `token_count(None)`). Upstream issue, not worth fixing now.

### Step 2: Tool Wrapper ✅
`/home/{{USERNAME}}/.openclaw/tools/repomap` — uses Aider's proven RepoMap engine (stable, handles edge cases). RepoMapper and Python 3.13 are available for future use if the bug gets fixed upstream.

### Step 3: AGENTS.md ✅
Auto-trigger rule added: when code is mentioned, run repomap before answering.

### Step 4: Test ✅
Works on real codebases (OpenClaw source, 1.6k files).

## Current Status
- [x] Step 0: Install Python 3.13
- [x] Step 1: Install RepoMapper (has bug, not in active use)
- [x] Step 2: Create tool wrapper at `/home/{{USERNAME}}/.openclaw/tools/repomap`
- [x] Step 3: Update AGENTS.md with auto-trigger rule
- [x] Step 4: Test and verify

## Result
Fade now has:
- A `repomap` CLI tool that works on any codebase (backed by Aider's engine)
- Python 3.13 + RepoMapper installed if upstream fixes come
- Instructions to auto-use it when code is mentioned
- OpenViking for memory + RepoMap for code understanding = full stack
