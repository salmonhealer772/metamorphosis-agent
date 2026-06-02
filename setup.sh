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
echo -e "${BOLD}║         Claude Code, but actually local. 🐢               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

START_DIR="$(pwd)"

# ── Prerequisites ──────────────────────────────────────────────────
echo -e "${DIM}→ Checking system…${NC}"
for cmd in git curl python3 node npm; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "$cmd not found — install it first"
    exit 1
  fi
done
ok "Prerequisites: git, curl, python3, node, npm"

# Detect distro
DISTRO=""
if [ -f /etc/os-release ]; then
  DISTRO=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
fi
UBUNTU_NOBLE=false
[ "$DISTRO" = "ubuntu" ] && grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null && UBUNTU_NOBLE=true

# ── Python / Pip Bootstrap ───────────────────────────────────────
# Ubuntu 24.04 ships python3 without pip or ensurepip, and marks the
# environment as externally managed (PEP 668). We need real pip.
echo ""
echo -e "${BOLD}→ Python Package Management${NC}"

# Try apt first (Ubuntu/Debian) — this is the only reliable way to get pip
PIP_CMD=""
if python3 -m pip --version >/dev/null 2>&1; then
  PIP_CMD="python3 -m pip"
  ok "pip already available ($(python3 -m pip --version | cut -d' ' -f2))"
else
  info "pip not found — attempting to install…"
  # Try apt for Ubuntu/Debian
  if [ "$UBUNTU_NOBLE" = true ] || [ "$DISTRO" = "debian" ]; then
    if command -v sudo >/dev/null 2>&1; then
      info "Installing python3-pip via apt (sudo required)…"
      sudo apt update -qq && sudo apt install -y -qq python3-pip python3-pip-whl 2>&1 | tail -1
      if python3 -m pip --version >/dev/null 2>&1; then
        PIP_CMD="python3 -m pip"
        ok "pip installed via apt ($(python3 -m pip --version | cut -d' ' -f2))"
      else
        warn "apt install failed — falling back to venv"
      fi
    else
      warn "sudo not available — falling back to venv"
    fi
  fi

  # Fallback: pip.pyz bootstrap + --break-system-packages
  if [ -z "$PIP_CMD" ] && [ ! -f /tmp/pip.pyz ]; then
    info "Downloading pip.pyz…"
    curl -sL https://bootstrap.pypa.io/pip/pip.pyz -o /tmp/pip.pyz
    if [ -f /tmp/pip.pyz ]; then
      ok "pip.pyz downloaded ($(stat -c%s /tmp/pip.pyz 2>/dev/null) bytes)"
    else
      warn "pip.pyz download failed"
    fi
  fi

  if [ -z "$PIP_CMD" ] && [ -f /tmp/pip.pyz ]; then
    if python3 /tmp/pip.pyz install --user --break-system-packages pip -q 2>&1; then
      export PATH="$HOME/.local/bin:$PATH"
      if python3 -m pip --version >/dev/null 2>&1; then
        PIP_CMD="python3 -m pip"
        ok "pip installed via pip.pyz ($(python3 -m pip --version | cut -d' ' -f2))"
      fi
    else
      warn "pip.pyz pip install failed (PEP 668)"
    fi
  fi

  # Final fallback: create a venv to sidestep PEP 668 entirely
  if [ -z "$PIP_CMD" ]; then
    if python3 -m venv "$HOME/.openclaw/venv" 2>&1; then
      PIP_CMD="$HOME/.openclaw/venv/bin/pip"
      ok "Created Python venv at ~/.openclaw/venv (no sudo, no PEP 668 issues)"
    else
      warn "venv creation failed — need python3-venv package"
      warn "Run: sudo apt install python3-venv python3-pip"
      warn "Then re-run this script"
    fi
  fi
fi

# Verify we have something
if [ -z "$PIP_CMD" ]; then
  fail "No pip available. Install python3-pip manually and re-run."
  exit 1
fi

PIP_INSTALL="$PIP_CMD install --user --break-system-packages"
# If using venv pip, --user doesn't make sense
if echo "$PIP_CMD" | grep -q "/venv/bin/pip"; then
  PIP_INSTALL="$PIP_CMD install"
fi

# ── Install openviking ────────────────────────────────────────────
echo ""
echo -e "${BOLD}→ OpenViking (Vector Memory)${NC}"
if python3 -c "import openviking" 2>/dev/null; then
  ok "openviking $(python3 -c 'import openviking; print(openviking.__version__)' 2>/dev/null) already installed"
else
  info "Installing openviking (this may take a minute — 50+ dependencies)…"
  if $PIP_INSTALL openviking 2>&1; then
    ok "openviking installed"
  else
    warn "openviking install failed"
    warn "  Try: $PIP_INSTALL openviking"
  fi
fi

# Ensure storage directory (created now so it exists before ov.py runs)
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
chmod +x ov.py
mkdir -p "$HOME/.local/bin"
ln -sf "$WORKSPACE_TARGET/ov.py" "$HOME/.local/bin/ov.py"
ok "Workspace ready"

# ── Ollama install helper (no sudo) ───────────────────────────────
install_ollama_local() {
  local URL="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.zst"
  local DEST="$HOME/.local"

  mkdir -p "$DEST/bin"
  export PATH="$DEST/bin:$PATH"

  # Ensure zstandard is available for decompressing the Ollama tarball
  python3 -c "import zstandard" 2>/dev/null || {
    info "Installing zstandard for Ollama tarball decompression…"
    $PIP_INSTALL zstandard -q 2>&1 || warn "zstandard install failed"
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

binpath = os.path.join(dest, 'bin', 'ollama')
if os.path.exists(binpath):
    os.chmod(binpath, os.stat(binpath).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f"  Ollama binary at {binpath}")
PYEOF

  OLLAMA_URL="$URL" OLLAMA_DEST="$DEST" python3 "$OLLAMA_DL_SCRIPT" && rm -f "$OLLAMA_DL_SCRIPT"

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

# Start Ollama service BEFORE pulling model (pull needs the API running)
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

  # Now pull the embedding model (service is up so this will work)
  info "Pulling embedding model (all-minilm)…"
  if ollama pull all-minilm 2>&1; then
    ok "Embedding model ready"
  else
    warn "Pull failed — run 'ollama pull all-minilm' later"
  fi
fi

# Auto-start Ollama on login (so it works without agent self-healing)
if command -v ollama >/dev/null 2>&1; then
  if ! grep -q "ollama serve" "$HOME/.profile" 2>/dev/null; then
    echo "" >> "$HOME/.profile"
    echo "# Start Ollama for agent memory" >> "$HOME/.profile"
    echo "ollama serve >/dev/null 2>&1 &" >> "$HOME/.profile"
    ok "Ollama auto-start added to ~/.profile"
  else
    ok "Ollama auto-start already in ~/.profile"
  fi
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

# Verify openviking actually works now
if python3 -c "import openviking" 2>/dev/null; then
  if cd "$WORKSPACE_TARGET" 2>/dev/null; then
    if python3 ov.py status 2>&1 | grep -q "Semantic search: OK"; then
      ok "OpenViking operational — semantic search online"
    else
      warn "OpenViking package installed but status check had issues"
    fi
    cd "$START_DIR" 2>/dev/null || true
  fi
fi

echo -e "  ${DIM}  ${CYAN}python3 ov.py find \"query\"${NC}  — search"
echo -e "  ${DIM}  ${CYAN}python3 ov.py store \"fact\"${NC} — save"
echo -e "  ${DIM}  ${CYAN}python3 ov.py status${NC}       — health"

# ── SearXNG ───────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}→ Private Search (SearXNG)${NC}"
echo -e "  ${DIM}Self-hosted search engine. No Google tracking.${NC}"
echo -e "  ${DIM}Installed on demand — start with ~/scripts/start-searxng.sh${NC}"

SEARXNG_PORT=8888
SEARXNG_CONF_DIR="$HOME/.config/searxng"

if [ ! -d "$HOME/searxng" ]; then
  info "Cloning SearXNG…"
  git clone --depth 1 https://github.com/searxng/searxng.git "$HOME/searxng" 2>&1 || {
    warn "SearXNG clone failed — skipping"
    cd "$START_DIR" 2>/dev/null || true
  }
fi

if [ -d "$HOME/searxng" ]; then
  cd "$HOME/searxng"

  # Install msgspec FIRST — SearXNG imports it at module level,
  # so pip needs it to build the editable install.
  if python3 -c "import msgspec" 2>/dev/null; then
    ok "msgspec already installed"
  else
    info "Installing msgspec (required by SearXNG build)…"
    $PIP_INSTALL msgspec -q 2>&1 || warn "msgspec install failed"
  fi

  if python3 -c "import searx" 2>/dev/null; then
    ok "SearXNG already installed"
  else
    info "Installing SearXNG Python package…"
    $PIP_INSTALL -e . 2>&1 || warn "SearXNG install had issues"
  fi

  # Write config (does not start the service)
  mkdir -p "$SEARXNG_CONF_DIR"
  SEARXNG_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || echo "change-me-$(date +%s)")
  cat > "$SEARXNG_CONF_DIR/settings.yml" << SEARXNG_CONF
use_default_settings: true
server:
  secret_key: "$SEARXNG_SECRET"
  bind_address: "127.0.0.1"
  port: $SEARXNG_PORT
SEARXNG_CONF

  ok "SearXNG configured at $SEARXNG_CONF_DIR/settings.yml"
  info "Start: ~/scripts/start-searxng.sh"
  info "Stop:  ~/scripts/stop-searxng.sh"
  cd "$START_DIR" 2>/dev/null || true
fi

# ── Copy scripts ──────────────────────────────────────────────────
mkdir -p "$HOME/scripts"
cp -r "$REPO_DIR/scripts/"* "$HOME/scripts/" 2>/dev/null || true
chmod +x "$HOME/scripts/"*.sh 2>/dev/null || true

# ── Agent tools (referenced from AGENTS.md) ───────────────────────
mkdir -p "$HOME/.openclaw/tools"
cp "$REPO_DIR/scripts/repomap" "$HOME/.openclaw/tools/repomap" 2>/dev/null || true
chmod +x "$HOME/.openclaw/tools/repomap" 2>/dev/null || true

# Install aider-chat (repomap dependency)
if python3 -c "import aider" 2>/dev/null; then
  ok "aider-chat already installed"
else
  info "Installing aider-chat (required by repomap tool)…"
  $PIP_INSTALL aider-chat -q 2>&1 || warn "aider-chat install failed — repomap won't work"
fi

# Copy plans
mkdir -p "$HOME/plans"
cp -r "$REPO_DIR/plans/"* "$HOME/plans/" 2>/dev/null || true
cd "$START_DIR" 2>/dev/null || true

# ── Clone repo into workspace ─────────────────────────────────────
echo ""
echo -e "${BOLD}→ Agent Repository${NC}"
if [ -d "$WORKSPACE_TARGET/metamorphosis-agent/.git" ]; then
  ok "Repo already cloned"
else
  info "Cloning agent repo into workspace…"
  git clone --depth 1 https://github.com/salmonhealer772/metamorphosis-agent.git \
    "$WORKSPACE_TARGET/metamorphosis-agent" 2>&1 && \
    ok "Repo cloned" || \
    warn "Repo clone failed — agent can still function without it"
fi

# ── Bootstrap OpenClaw ────────────────────────────────────────────
echo ""
echo -e "${BOLD}→ Configuring OpenClaw…${NC}"
openclaw onboard --non-interactive --flow quickstart --accept-risk --skip-health 2>&1 | tail -3 || warn "Bootstrap had issues"

openclaw onboard --non-interactive --accept-risk --auth-choice "$AUTH_CHOICE" "$CLI_FLAG" "$API_KEY" 2>&1 | tail -2 || \
  warn "Provider setup had issues — run 'openclaw onboard' manually"

echo ""
echo -e "${GREEN}${BOLD}  ✅ metamorphosis-agent is ready${NC}"
echo ""
echo -e "  ${DIM}Starting your agent…${NC}"
echo ""

openclaw
