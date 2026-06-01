# Plan: Verify all-minilm pull

**Difficulty:** 🟢 Easy — verification only
**Code audit:** ✅ Already in place. No changes to setup.sh needed.

## Target
`setup.sh` lines 137-141:
```bash
if command -v ollama >/dev/null 2>&1; then
  info "Pulling embedding model (all-minilm)…"
  ollama pull all-minilm 2>&1 && ok "Embedding model ready" || warn "Pull failed"
fi
```

## Status
✅ Already exists. pip.pyz fix (last night) should make Ollama install work, which unblocks this pull.

## Verification
After setup on fresh user:
1. `ollama list | grep all-minilm` — shows 45MB model
2. `python3 ov.py status` — shows embedding provider ready

## If it fails
- `which ollama` — is Ollama installed?
- `curl -I https://registry.ollama.ai` — internet connectivity
- `ollama pull all-minilm` — retry manually
