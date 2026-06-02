#!/usr/bin/env bash
# setup.sh — Install metamorphosis-agent on any Linux/macOS/WSL machine
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_TARGET="${OPENCLAW_DIR:-$HOME/.openclaw/workspace}"

BOLD='\033[1m' DIM='\033[2m' GREEN='\033[0;32m'
YELLOW='\033[1;33m' CYAN='\033[0;36m' RED='\033[0;31m' NC='\033[0m'
info()  { echo -e "  ${CYAN}→${NC} $*"; }
ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         metamorphosis-agent — Local Setup                   ║${NC}"
echo -e "${BOLD}║         Claude Code, but actually local. 🦋               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

START_DIR="$(pwd)"

# ── Prerequisites ──────────────────────────────────────────────────
echo -e "${DIM}→ Checking system…${NC}"
for cmd in git curl python3 node npm; do
  command -v "$cmd" >/dev/null 2>&1 || { fail "$cmd not found"; exit 1; }
done
ok "Prerequisites: git, curl, python3, node, npm"

# ── Bootstrap pip (needed for openviking + zstandard) ────────────
echo -e "${DIM}→ Setting up Python package management…${NC}"
PIP_BOOTSTRAPPED=false
if python3 -m pip --version >/dev/null 2>&1; then
  PIP_BOOTSTRAPPED=true
  ok "pip already available"
elif python3 -c "import ensurepip; print('ok')" >/dev/null 2>&1; then
  python3 -m ensurepip --upgrade --user 2>&1 | tail -1
  PIP_BOOTSTRAPPED=true
  ok "pip installed via ensurepip"
else
  # No pip at all — bootstrap via pip.pyz
  info "Bootstrapping pip via pip.pyz…"
  curl -sL https://bootstrap.pypa.io/pip/pip.pyz -o /tmp/pip.pyz && \
    python3 /tmp/pip.pyz install --user pip -q 2>/dev/null && \
    PIP_BOOTSTRAPPED=true
  if [ "$PIP_BOOTSTRAPPED" = true ]; then
    ok "pip bootstrapped"
  else
    warn "pip bootstrap failed — openviking won't be usable"
  fi
fi

# ── Install openviking Python package ────────────────────────────
echo -e "${DIM}→ Installing OpenViking…${NC}"
if python3 -c "import openviking" 2>/dev/null; then
  ok "openviking already installed"
else
  if [ "$PIP_BOOTSTRAPPED" = true ]; then
    info "Installing openviking…"
    if [ -f /tmp/pip.pyz ]; then
      python3 /tmp/pip.pyz install --user --break-system-packages openviking -q 2>/dev/null && \
        ok "openviking installed" || warn "openviking install failed"
    else
      python3 -m pip install --user --break-system-packages openviking -q 2>/dev/null && \
        ok "openviking installed" || warn "openviking install failed"
    fi
  fi
fi

# Ensure storage directory exists
mkdir -p "$HOME/.openclaw/workspace/.openviking"

# ── OpenClaw ──────────────────────────────────────────────────────
if ! command -v openclaw >/dev/null 2>&1; then
  info "Installing OpenClaw…"
  npm install -g openclaw
fi
ok "OpenClaw ready"

# ── Gather Info ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}→ Agent identity${NC}"
read -rp "  Agent name (e.g. Fade): " AGENT_NAME

# Provider menu
echo ""
echo -e "${BOLD}→ LLM provider${NC}"
echo "  1) DeepSeek"
echo "  2) OpenAI"
echo "  3) Anthropic"
echo "  4) Google Gemini"
echo "  5) OpenRouter"
echo "  6) Together AI"
echo "  7) xAI (Grok)"
echo "  8) Mistral"
echo "  9) Fireworks"
read -rp "  Pick (1-9): " PROVIDER_IDX

# Map selection to onboard params
AUTH_CHOICE=""
CLI_FLAG=""
case "$PROVIDER_IDX" in
  1) AUTH_CHOICE="deepseek-api-key";    CLI_FLAG="--deepseek-api-key";;
  2) AUTH_CHOICE="openai-api-key";      CLI_FLAG="--openai-api-key";;
  3) AUTH_CHOICE="apiKey";              CLI_FLAG="--anthropic-api-key";;
  4) AUTH_CHOICE="gemini-api-key";      CLI_FLAG="--gemini-api-key";;
  5) AUTH_CHOICE="openrouter-api-key";  CLI_FLAG="--openrouter-api-key";;
  6) AUTH_CHOICE="together-api-key";    CLI_FLAG="--together-api-key";;
  7) AUTH_CHOICE="xai-api-key";         CLI_FLAG="--xai-api-key";;
  8) AUTH_CHOICE="mistral-api-key";     CLI_FLAG="--mistral-api-key";;
  9) AUTH_CHOICE="fireworks-api-key";   CLI_FLAG="--fireworks-api-key";;
  *) echo "  Invalid choice"; exit 1;;
esac

read -rp "  Paste your API key: " API_KEY
echo ""

# ── Deploy workspace ───────────────────────────────────────────────
echo -e "${BOLD}→ Deploying workspace…${NC}"
if [ -d "$WORKSPACE_TARGET" ]; then
  mv "$WORKSPACE_TARGET" "$WORKSPACE_TARGET.backup.$(date +%s)"
  echo -e "  ${DIM}Backed up existing workspace${NC}"
fi
mkdir -p "$WORKSPACE_TARGET"
cp -r "$REPO_DIR/workspace/"* "$WORKSPACE_TARGET/"
cd "$WORKSPACE_TARGET"
sed -i "s/{{AGENT_NAME}}/$AGENT_NAME/g; s/{{AGENT_EMOJI}}/✨/g" IDENTITY.md
sed -i "s/{{YOUR_NAME}}/friend/g; s/{{PREFERRED_NAME}}/friend/g; s/{{TIMEZONE}}/UTC/g" USER.md
ok "Workspace ready"

# ── Ollama install helper (no sudo) ───────────────────────────────
install_ollama_local() {
  local URL="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.zst"
  local DEST="$HOME/.local"

  mkdir -p "$DEST/bin"
  export PATH="$DEST/bin:$PATH"

  # Ensure zstandard is available for decompressing the Ollama tarball
  python3 -c "import zstandard" 2>/dev/null || {
    if [ -f /tmp/pip.pyz ]; then
      python3 /tmp/pip.pyz install --user --break-system-packages zstandard -q 2>/dev/null
    else
      python3 -m pip install --user --break-system-packages zstandard -q 2>/dev/null
    fi
  }

  OLLAMA_DL_SCRIPT="/tmp/_ollama_dl_$$.py"
  cat > "$OLLAMA_DL_SCRIPT" << 'PYEOF'
import urllib.request, tarfile, zstandard, os, sys, stat

url = os.environ['OLLAMA_URL']
dest = os.environ['OLLAMA_DEST']
os.makedirs(dest, exist_ok=True)

sys.stderr.write("  Downloading...\n")
resp = urllib.request.urlopen(url)
dctx = zstandard.ZstdDecompressor()
reader = dctx.stream_reader(resp)
with tarfile.open(fileobj=reader, mode='r|') as tar:
    tar.extractall(path=dest)

# Ensure binary is executable
binpath = os.path.join(dest, 'bin', 'ollama')
if os.path.exists(binpath):
    os.chmod(binpath, os.stat(binpath).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f"  Ollama binary at {binpath}")
PYEOF

  OLLAMA_URL="$URL" OLLAMA_DEST="$DEST" python3 "$OLLAMA_DL_SCRIPT" && rm -f "$OLLAMA_DL_SCRIPT"

  # Persist PATH
  grep -q '.local/bin' "$HOME/.profile" 2>/dev/null || \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
}

# ── Vector Memory ────────────────────────────────────────────────
echo ""
echo -e "${BOLD}→ Core: Vector Memory (OpenViking)${NC}"
echo -e "  ${DIM}The agent needs this to remember you across sessions.${NC}"

if ! command -v ollama >/dev/null 2>&1; then
  info "Installing Ollama locally…"
  install_ollama_local || warn "Ollama install had issues"
fi

command -v ollama >/dev/null 2>&1 && ok "Ollama ready" || warn "Ollama not found — install manually"

# Pull model
if command -v ollama >/dev/null 2>&1; then
  info "Pulling embedding model (all-minilm)…"
  ollama pull all-minilm 2>&1 && ok "Embedding model ready" || warn "Pull failed — run 'ollama pull all-minilm' later"
fi

# Start service
if command -v ollama >/dev/null 2>&1; then
  if ! curl -s http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
    info "Starting Ollama service…"
    ollama serve >/dev/null 2>&1 &
    for i in 1 2 3 4 5; do
      sleep 2
      curl -s http://127.0.0.1:11434/api/version >/dev/null 2>&1 && break
      [ "$i" -eq 5 ] && warn "Ollama starting slowly"
    done
  fi
  curl -s http://127.0.0.1:11434/api/version >/dev/null 2>&1 \
    && ok "Ollama running on localhost:11434" \
    || warn "Ollama not reachable"
fi

# Configure OpenViking
mkdir -p "$HOME/.openviking"
cat > "$HOME/.openviking/ov.conf" << OVCONF
{
  "storage": {
    "workspace": "$HOME/.openclaw/workspace/.openviking"
  },
  "embedding": {
    "dense": {
      "provider": "ollama",
      "api_base": "http://127.0.0.1:11434/v1",
      "model": "all-minilm",
      "dimension": 384
    },
    "max_concurrent": 2
  },
  "log": {
    "level": "ERROR",
    "output": "stdout"
  }
}
OVCONF
ok "OpenViking configured"
echo -e "  ${DIM}  ${CYAN}python3 ov.py find \"query\"${NC}  — search"
echo -e "  ${DIM}  ${CYAN}python3 ov.py store \"fact\"${NC} — save"
echo -e "  ${DIM}  ${CYAN}python3 ov.py status${NC}       — health"

# ── SearXNG ───────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}→ Private Search (SearXNG)${NC}"
echo -e "  ${DIM}Self-hosted search engine. No Google tracking.${NC}"

SEARXNG_PORT=8888
SEARXNG_CONF_DIR="$HOME/.config/searxng"

# Check if already running
if curl -sf "http://127.0.0.1:$SEARXNG_PORT/search?q=health" >/dev/null 2>&1; then
  ok "SearXNG already running on http://127.0.0.1:$SEARXNG_PORT"
else
  if [ ! -d "$HOME/searxng" ]; then
    info "Installing SearXNG…"
    git clone --depth 1 https://github.com/searxng/searxng.git "$HOME/searxng" 2>/dev/null || {
      warn "SearXNG clone failed — skipping"
      cd "$START_DIR" 2>/dev/null || true
      warn "SearXNG not available — agent will use web_search instead"
    }
  fi

  if [ -d "$HOME/searxng" ]; then
    cd "$HOME/searxng"
    if python3 -c "import searx" 2>/dev/null; then
      ok "SearXNG already installed"
    else
      info "Installing SearXNG Python package…"
      if [ -f /tmp/pip.pyz ]; then
        python3 /tmp/pip.pyz install --user --break-system-packages -e . 2>/dev/null || warn "SearXNG install had issues"
      else
        python3 -m pip install --user --break-system-packages -e . 2>/dev/null || warn "SearXNG install had issues"
      fi
    fi

    # Create config with proper bind_address and port
    mkdir -p "$SEARXNG_CONF_DIR"
    SEARXNG_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || echo "change-me-$(date +%s)")
    cat > "$SEARXNG_CONF_DIR/settings.yml" << SEARXNG_CONF
use_default_settings: true
server:
  secret_key: "$SEARXNG_SECRET"
  bind_address: "127.0.0.1"
  port: $SEARXNG_PORT
SEARXNG_CONF

    # Kill any stale SearXNG from previous runs
    pkill -f "searx.webapp" 2>/dev/null || true
    sleep 1

    # Start SearXNG with our config
    info "Starting SearXNG…"
    export SEARXNG_SETTINGS_PATH="$SEARXNG_CONF_DIR/settings.yml"
    nohup python3 -m searx.webapp > /tmp/searxng_web.log 2>&1 &
    cd "$START_DIR" 2>/dev/null || true

    # Wait for port to actually be listening (up to 20s)
    for i in 1 2 3 4 5 6 7 8 9 10; do
      sleep 2
      if curl -sf "http://127.0.0.1:$SEARXNG_PORT" >/dev/null 2>&1; then
        ok "SearXNG running on http://127.0.0.1:$SEARXNG_PORT"
        break
      fi
      [ "$i" -eq 10 ] && warn "SearXNG failed to start — check /tmp/searxng_web.log"
    done
  fi
fi

# ── Copy scripts ──────────────────────────────────────────────────
mkdir -p "$HOME/scripts"
cp -r "$REPO_DIR/scripts/"* "$HOME/scripts/" 2>/dev/null || true
chmod +x "$HOME/scripts/"*.sh 2>/dev/null || true

# ── Agent tools (referenced from AGENTS.md) ───────────────────────
mkdir -p "$HOME/.openclaw/tools"
cp "$REPO_DIR/scripts/repomap" "$HOME/.openclaw/tools/repomap" 2>/dev/null || true
chmod +x "$HOME/.openclaw/tools/repomap" 2>/dev/null || true

# Copy plans
mkdir -p "$HOME/plans"
cp -r "$REPO_DIR/plans/"* "$HOME/plans/" 2>/dev/null || true
cd "$START_DIR" 2>/dev/null || true

# Bootstrap OpenClaw config (workspace, gateway, sessions)
echo ""
echo -e "${BOLD}→ Configuring OpenClaw…${NC}"
openclaw onboard --non-interactive --flow quickstart --accept-risk --skip-health 2>&1 | tail -3 || warn "Bootstrap had issues"

# Register the API key with OpenClaw's auth store
openclaw onboard --non-interactive --accept-risk --auth-choice "$AUTH_CHOICE" "$CLI_FLAG" "$API_KEY" 2>&1 | tail -2 || \
  warn "Provider setup had issues — run 'openclaw onboard' manually"

echo ""
echo -e "${GREEN}${BOLD}  ✅ metamorphosis-agent is ready${NC}"
echo ""
echo -e "  ${DIM}Starting your agent…${NC}"
echo ""

# Launch openclaw — first run intro is handled by the agent itself
openclaw
