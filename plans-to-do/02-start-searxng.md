# Plan: Start SearXNG after install

**Difficulty:** 🟢 Easy — 3 lines
**Code audit:** ✅ Clean. Module confirmed: `searx/webapp.py` exists in cloned repo.

## Target
`setup.sh` lines 186-197:
```bash
if [ ! -d "$HOME/searxng" ]; then
  info "Installing SearXNG…"
  git clone --depth 1 https://github.com/searxng/searxng.git "$HOME/searxng" 2>/dev/null || warn "Clone failed"
  cd "$HOME/searxng"
  python3 /tmp/pip.pyz install --user --break-system-packages -e . 2>/dev/null || warn "SearXNG install had issues"
  cd "$START_DIR" 2>/dev/null || true
fi
cd "$START_DIR" 2>/dev/null || true
ok "SearXNG at ~/searxng"
```

## Fix
After the SearXNG block ends (after `ok` line), add:
```bash
nohup python3 -m searx.webapp > /tmp/searxng_web.log 2>&1 &
ok "SearXNG running on http://127.0.0.1:8888"
```

## Why no start.sh?
The SearXNG repo doesn't ship a `start.sh`. The original machine had one created manually. The correct entry point is `python3 -m searx.webapp`.

## Test
After setup, `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8888` should return 200
