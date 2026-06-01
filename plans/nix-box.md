# Plan: Nix Box — Nuerpeel Minion Fleet

## ⚡ Spec Card — 48 Nuerpeel Minions

| Resource | Per Minion | Fleet Total (48) | Leftover |
|----------|-----------|-------------------|----------|
| **RAM** | **512 MB** | **24 GB** | 30 GB (infra + headroom) |
| **CPU** | **0.25 core** (hard cap) | 12 logical threads | 4 threads (OS + services) |
| **Disk** | **5 GB** | **240 GB** | ~500 GB |

- **Server:** {{SERVER_NAME}} — AMD Ryzen 7 9700X (8P/16T), 60 GB RAM, 46 GB A6000 GPU
- **GPU is separate:** vLLM serves the LLM API on the A6000, not part of this budget
- **LLM routing:** vLLM (local) → LiteLLM (router with DeepSeek API fallback)
- **Each box contains:** Luna agent + BASH_ENV_SCELLS market tooling (ccxt, web3, polymarket, hyperliquid, manifold), DNA-driven personality
- **Guard:** Fabean service authenticates per-minion creds + scans for protected paths
- **Orchestration:** Docker containers managed by a spawner (DNA in → container out)

---

## The Vision

A fleet of Nix-based Docker containers on **{{SERVER_NAME}}** — each one is a **nuerpeel minion** (a Luna agent). Each minion gets its own DNA blueprint (tone, role, tool-pack, risk-posture, etc.), compiled at spawn time by a spawner service. They talk to each other, trade markets via BASH_ENV_SCELLS, and call LLMs through a layered stack.

### Full Stack

```
                  ┌──────────────────────────┐
                  │   Selector (writes DNAs)  │
                  └────────────┬─────────────┘
                               │ DNA files on disk
                  ┌────────────▼─────────────┐
                  │   Spawner (on its own box)│
                  │   DNA in → container out │
                  └────────────┬─────────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
  ┌─────▼─────┐      ┌────────▼───────┐     ┌────────▼───────┐
  │ Nix Box 1 │      │  Nix Box 2     │     │  Nix Box 64    │
  │ minion    │      │  minion        │     │  minion        │
  │ Luna      │      │  Luna          │     │  Luna          │
  │ + SCEL LS  │      │  + SCEL LS      │     │  + SCEL LS      │
  │ 512MB RAM │      │  512MB RAM     │     │  512MB RAM     │
  └─────┬─────┘      └────────┬───────┘     └────────┬───────┘
        │                      │                      │
        │    All LLM calls go through {{SERVER_NAME}}          │
        └──────────────────────┼──────────────────────┘
                               │
                  ┌────────────▼─────────────┐
                  │  Fabean (auth guard)      │
                  │  validates Authenticator  │
                  │  scans for protected paths│
                  └────────────┬─────────────┘
                               │
                  ┌────────────▼─────────────┐
                  │  LiteLLM (modded router)  │
                  │  inspects → routes →      │
                  │  cache/queue → dispatch   │
                  └────┬──────────────┬──────┘
                       │              │
              ┌────────▼──┐    ┌──────▼──────┐
              │  vLLM     │    │ DeepSeek    │
              │ A6000 46GB│    │ API (paid)  │
              │ local     │    │ (fallback)  │
              └───────────┘    └─────────────┘
```

## Resources Available ({{SERVER_NAME}})

| Resource | Total | For minion fleet | Notes |
|----------|-------|-----------------|-------|
| **RAM** | 54 GB available | 32 GB | 22 GB left for infra + headroom |
| **CPU** | 16 cores | 16 cores (shared) | Minions are I/O bound waiting on LLM |
| **Disk** | 737 GB free | 320 GB | 417 GB left for logs, models, swap |
| **GPU** | A6000 46GB | vLLM serves it | Separate — not part of this budget |

## Per-Minion Sizing (Decided)

| Resource | Per Minion | Fleet Total (48) |
|----------|-----------|-------------------|
| **RAM** | **512 MB** | **24 GB** |
| **CPU** | **0.25 core** (hard capped) | 12 logical threads |
| **Disk** | **5 GB** | **240 GB** |

**48 minions × 512 MB RAM = 24 GB.** Leaves **30 GB** for Fabean, LiteLLM, spawner, OS, and headroom.

**48 minions × 0.25 CPU = 12 logical threads.** Leaves **4 logical threads** for the OS and services. This is comfortable — Ryzen 9700X (8P/16T) with 4 threads free means the system won't choke.

## Key Architecture Details

### Selector (separate process, not Docker)
- Writes DNA files to disk (random, curated, cross-bred, or mutated)
- Each DNA picks one gene per slot from the gene library
- Slots: name, tone, role, specialty, risk-posture, approach, tool-pack, memory-profile, llm-profile, patience, context-window, MCP-pack, social

### Spawner (separate box/process)
- Reads DNA → produces a running container
- Steps: validate DNA → allocate identity → clone DNA → compile artifacts → provision volumes → start container → register → health check
- Companion verbs: stop, kill, respawn, clone, mutate, damn

### Fabean (guard service)
- Every LLM call from minions passes through it
- Validates per-minion Authenticator (issued by spawner)
- Scans tool calls for protected path references (DNA, core scripts, credentials)
- Blocks dangerous paths, passes clean requests to LiteLLM
- JSONL audit log

### LiteLLM (modded)
- Routing brain + provider dispatch
- Inspects request content, routes intelligently (vLLM / DeepSeek / other)
- Cache/queue layer smooths bursty minion traffic
- Pluggable routing protocol: cheap rules first, small classifier LLM as fallback

### AV/MI Agent Runtime (mi by @avcodes/mi)

Each minion has access to the **mi** agentic coding runtime (`@avcodes/mi`) as a tool/service:

- **What it is:** A minimal agent loop (LLM → bash/delegate/skill → result → repeat) that gives the minion full system access: running commands, writing files, git, curl, compilers
- **How it's exposed:** As an API endpoint that nuerpeel minions can call to delegate coding/shell tasks
- **Tool set:** `bash` (full shell access), `skill` (loaded playbooks), `delegate` (sub-agents), `goal` (goal-pursuit with verify loops)
- **LLM routing:** mi calls go through the same path — Fabean → LiteLLM → vLLM/DeepSeek
- **Integration:** Wrapped in a small HTTP server so minions call it via HTTP rather than spawning a process
- **Docker image:** Available at `ghcr.io/av/mi` — can be used as sandbox or base layer

### Market Tooling (BASH_ENV_SCELLS)
- Each minion has the market-env venv baked in
- ccxt, web3, polymarket, hyperliquid, manifold, kalshi
- Agents trade autonomously based on their DNA role/specialty

## Current Status

- [ ] Get Docker daemon running on {{SERVER_NAME}}
- [x] Decide per-minion resource budget (512 MB RAM, 5 GB disk)
- [x] Fleet size decided (64 minions)
- [ ] Move BASH_ENV_SCELLS to {{SERVER_NAME}}, run setup.sh
- [ ] Build Nix-based Docker image with Luna + market-env baked in
- [ ] Set up the gene library directory structure on disk
- [ ] Test single minion container (manual, no spawner)
- [ ] Configure Fabean guard service
- [ ] Configure LiteLLM routing (vLLM primary, DeepSeek fallback)
- [ ] Build the spawner (or weave into orchestration)
- [ ] Spin up 64 minions with random DNA
- [ ] Set up centralized JSONL logging
- [ ] Health monitoring + auto-restart

## Questions to Settle

- **Orchestration:** raw Docker, Docker Compose, or Nomad?
- **Spawner box:** {{SERVER_NAME}} itself, or a separate machine?
- **Live registry:** where do running minions register? (sqlite, redis, flat file?)
