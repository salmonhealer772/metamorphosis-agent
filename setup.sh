#!/usr/bin/env bash
# setup.sh — Install metamorphosis-agent on any Linux/macOS/WSL machine
#
# A best-practices Bash script. Sources template functions from source.sh
# (ralish/bash-script-template). Handles clean-up via trap, supports
# --verbose and --no-colour, and exits cleanly on errors.
#
# Repository: https://github.com/salmonhealer772/metamorphosis-agent
# License: MIT

# Enable xtrace if the DEBUG environment variable is set
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    set -o xtrace
fi

# Only enable these shell behaviours if we're not being sourced
if ! (return 0 2> /dev/null); then
    set -o errexit
    set -o nounset
    set -o pipefail
fi

set -o errtrace

# ---- DESC: Usage help -------------------------------------------------------
function script_usage() {
    cat << EOF
Usage:
     -h|--help                  Displays this help
     -v|--verbose               Displays verbose output
    -nc|--no-colour             Disables colour output

Interactive prompts will ask for:
  - Install directory (where everything goes, defaults to current dir)
  - Agent name
  - LLM provider and API key
EOF
}

# ---- DESC: Parameter parser --------------------------------------------------
function parse_params() {
    local param
    while [[ $# -gt 0 ]]; do
        param="$1"
        shift
        case $param in
            -h | --help)
                script_usage
                exit 0
                ;;
            -v | --verbose)
                verbose=true
                ;;
            -nc | --no-colour)
                no_colour=true
                ;;
            -e | --env-file)
                if [[ $# -eq 0 ]]; then
                    script_exit "--env-file requires a file path argument" 1
                fi
                ENV_FILE="$1"
                shift
                ;;
            *)
                script_exit "Invalid parameter was provided: $param" 1
                ;;
        esac
    done
}

# ---- DESC: Handler for unexpected errors -------------------------------------
function script_trap_err() {
    local exit_code=1
    trap - ERR
    set +o errexit
    set +o pipefail

    if [[ ${1-} =~ ^[0-9]+$ ]]; then
        exit_code="$1"
    fi

    printf '%b\n' "$ta_none"
    printf '***** Abnormal termination of setup.sh *****\n'
    printf 'Exit Code:       %s\n' "$exit_code"
    exit "$exit_code"
}

# ---- DESC: Handler for exiting the script ------------------------------------
function script_trap_exit() {
    cd "$orig_cwd" 2>/dev/null || true

    # Kill any background processes we started
    if [[ -n ${ollama_pid-} ]]; then
        kill "$ollama_pid" 2>/dev/null || true
    fi

    # Clean up temp files
    rm -f /tmp/pip.pyz /tmp/_ollama_dl_*.py 2>/dev/null || true

    printf '%b' "$ta_none"
}

# ---- DESC: Exit script with the given message --------------------------------
function script_exit() {
    if [[ $# -eq 1 ]]; then
        printf '%s\n' "$1"
        exit 0
    fi

    if [[ ${2-} =~ ^[0-9]+$ ]]; then
        printf '%b\n' "$1"
        if [[ $2 -ne 0 ]]; then
            script_trap_err "$2"
        else
            exit 0
        fi
    fi

    script_exit 'Missing required argument to script_exit()!' 2
}

# ---- DESC: Generic script initialisation -------------------------------------
function script_init() {
    readonly orig_cwd="$PWD"
    readonly script_params="$*"
    readonly script_path="${BASH_SOURCE[0]}"
    script_dir="$(dirname "$script_path")"
    script_name="$(basename "$script_path")"
    readonly script_dir script_name
    readonly ta_none="$(tput sgr0 2>/dev/null || true)"
}

# ---- DESC: Initialise colour variables ---------------------------------------
function colour_init() {
    if [[ -z ${no_colour-} ]]; then
        readonly ta_bold="$(tput bold 2>/dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_cyan="$(tput setaf 6 2>/dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_green="$(tput setaf 2 2>/dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_yellow="$(tput setaf 3 2>/dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_red="$(tput setaf 1 2>/dev/null || true)"
        printf '%b' "$ta_none"

        readonly bg_green="$(tput setab 2 2>/dev/null || true)"
        printf '%b' "$ta_none"
    else
        readonly ta_bold='' fg_cyan='' fg_green='' fg_yellow='' fg_red='' bg_green=''
    fi
}

# ---- DESC: Pretty print ------------------------------------------------------
function pretty_print() {
    if [[ $# -lt 1 ]]; then
        script_exit 'Missing required argument to pretty_print()!' 2
    fi

    if [[ -z ${no_colour-} ]]; then
        if [[ -n ${2-} ]]; then
            printf '%b' "$2"
        else
            printf '%b' "$fg_green"
        fi
    fi

    if [[ -n ${3-} ]]; then
        printf '%s%b' "$1" "$ta_none"
    else
        printf '%s%b\n' "$1" "$ta_none"
    fi
}

# ---- DESC: Verbose print -----------------------------------------------------
function verbose_print() {
    if [[ -n ${verbose-} ]]; then
        pretty_print "$@"
    fi
}

# ---- DESC: Check a binary exists in the search path --------------------------
function check_binary() {
    if [[ $# -lt 1 ]]; then
        script_exit 'Missing required argument to check_binary()!' 2
    fi

    if ! command -v "$1" >/dev/null 2>&1; then
        if [[ -n ${2-} ]]; then
            script_exit "Missing dependency: Couldn't locate $1." 1
        else
            verbose_print "Missing dependency: $1" "${fg_red-}"
            return 1
        fi
    fi

    verbose_print "Found dependency: $1"
    return 0
}

# =============================================================================
#  metamorphosis-agent specific functions
# =============================================================================

# ---- DESC: Print the welcome banner -----------------------------------------
function print_banner() {
    echo ""
    echo -e "${ta_bold}╔══════════════════════════════════════════════════════════════╗${ta_none}"
    echo -e "${ta_bold}║         metamorphosis-agent — Local Setup                   ║${ta_none}"
    echo -e "${ta_bold}║         Claude Code, but actually local. 🐢               ║${ta_none}"
    echo -e "${ta_bold}╚══════════════════════════════════════════════════════════════╝${ta_none}"
    echo ""
}

# ---- DESC: Check system prerequisites ----------------------------------------
function check_prerequisites() {
    pretty_print "Checking system…" "${fg_cyan}"
    for cmd in git curl python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            pretty_print "$cmd not found — install it first" "${fg_red}"
            exit 1
        fi
    done
    pretty_print "Prerequisites: git, curl, python3"
}

# ---- DESC: Detect OS/distro --------------------------------------------------
function detect_distro() {
    DISTRO=""
    UBUNTU_NOBLE=false
    if [[ -f /etc/os-release ]]; then
        DISTRO=$(grep ^ID= /etc/os-release | cut -d= -f2 | tr -d '"')
        if [[ "$DISTRO" = "ubuntu" ]] && grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null; then
            UBUNTU_NOBLE=true
        fi
    fi
}

# ---- DESC: Install Node.js (if missing) -------------------------------------
function install_nodejs() {
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        return
    fi

    local arch
    case "$(uname -m)" in
        x86_64)  arch="x64" ;;
        aarch64) arch="arm64" ;;
        *)       pretty_print "Unsupported arch for auto Node.js install: $(uname -m)" "${fg_yellow}"
                 pretty_print "Install Node.js 18+ manually, then rerun setup" "${fg_yellow}"
                 exit 1 ;;
    esac

    pretty_print "Installing Node.js…" "${fg_cyan}"

    local node_version="v22.14.0"
    local url="https://nodejs.org/dist/${node_version}/node-${node_version}-linux-${arch}.tar.xz"
    local dest="$INSTALL_DIR/.local"

    mkdir -p "$dest"
    export PATH="$dest/bin:$PATH"

    local tmpdir
    tmpdir="$(mktemp -d)"
    local tarball="$tmpdir/node.tar.xz"

    curl -fsSL "$url" -o "$tarball" || {
        pretty_print "Node.js download failed" "${fg_red}"
        rm -rf "$tmpdir"
        exit 1
    }

    # Extract full Node.js tree into $INSTALL_DIR/.local/
    tar -xf "$tarball" -C "$tmpdir" --strip-components=1

    # Copy everything (bin/, lib/, include/, share/) into $INSTALL_DIR/.local/
    # This preserves npm's dependency on lib/node_modules/npm/
    cp -r "$tmpdir/"* "$dest/"

    rm -rf "$tmpdir"

    pretty_print "Node.js $(node --version) installed in $INSTALL_DIR/.local/"
}

# ---- DESC: Install or verify OpenClaw CLI ------------------------------------
function install_openclaw() {
    local oc_bin="$INSTALL_DIR/.local/bin/openclaw"

    if ! command -v openclaw >/dev/null 2>&1 && [[ ! -f "$oc_bin" ]]; then
        pretty_print "Installing OpenClaw…" "${fg_cyan}"
        # Override HOME so npm + openclaw postinstall write to tmp, not ~/
        HOME=/tmp npm install -g openclaw --prefix="$INSTALL_DIR/.local" 2>&1 || \
            npm install -g openclaw --prefix="$INSTALL_DIR/.local"
        # Move any stray ~/.openclaw/ into project dir
        if [[ -d "$HOME/.openclaw" ]]; then
            mkdir -p "$INSTALL_DIR/.leaks"
            mv "$HOME/.openclaw" "$INSTALL_DIR/.leaks/.openclaw-npm" 2>/dev/null || rm -rf "$HOME/.openclaw" 2>/dev/null || true
        fi
    fi

    # VERIFY the binary actually exists — either system-wide or local
    if ! command -v openclaw >/dev/null 2>&1 && [[ ! -f "$oc_bin" ]]; then
        pretty_print "OpenClaw install FAILED — binary not found at $oc_bin" "${fg_red}"
        pretty_print "  Try manually: npm install -g openclaw --prefix=\"$INSTALL_DIR/.local\"" "${fg_yellow}"
        pretty_print "  Or install system-wide: npm install -g openclaw" "${fg_yellow}"
        if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
            pretty_print "  node $(node --version) and npm $(npm --version) are available" "${fg_cyan}"
        else
            pretty_print "  node/npm not found — install Node.js 18+ first" "${fg_yellow}"
        fi
        exit 1
    fi
    pretty_print "OpenClaw ready"
}

# ---- DESC: Read a key from a .env file (export-style, no export needed) ------
function env_file_lookup() {
    local file="$1"
    local key="$2"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    # Match KEY=value or export KEY=value, with optional quotes around value
    local val
    val=$(grep -E "^(export[[:space:]]+)?${key}=" "$file" 2>/dev/null | head -1 | sed -E 's/^(export[[:space:]]+)?[^=]+=//' | sed -E 's/^["\x27]//;s/["\x27]$//')
    if [[ -n "$val" ]]; then
        printf '%s' "$val"
        return 0
    fi
    return 1
}

# ---- DESC: Prompt for install directory (before any installs) -----------------
function prompt_install_dir() {
    echo ""
    pretty_print "→ Install directory" "${ta_bold}"
    local _default="$(pwd)"
    echo "  Default: $_default"
    echo "  (All agent files — config, workspace, scripts — go here."
    echo "   Leave empty for the default above.)"
    read -rp "  Path: " TARGET_DIR
    if [[ -n "$TARGET_DIR" ]]; then
        TARGET_DIR="$(realpath -m "$TARGET_DIR" 2>/dev/null || echo "$TARGET_DIR")"
    fi
}

# ---- DESC: Gather agent identity from user -----------------------------------
function gather_identity() {
    echo ""
    pretty_print "→ Agent identity" "${ta_bold}"
    read -rp "  Agent name (e.g. Fade): " AGENT_NAME

    echo ""
    pretty_print "→ LLM provider" "${ta_bold}"
    echo "  0) Ollama (Local — no API key needed)"
    echo "  1) DeepSeek"
    echo "  2) OpenAI"
    echo "  3) Anthropic"
    echo "  4) Google Gemini"
    echo "  5) OpenRouter"
    echo "  6) Together AI"
    echo "  7) xAI (Grok)"
    echo "  8) Mistral"
    echo "  9) Fireworks"
    read -rp "  Pick (0-9): " PROVIDER_IDX

    AUTH_CHOICE=""
    CLI_FLAG=""
    local env_key=""
    case "$PROVIDER_IDX" in
        0) AUTH_CHOICE="";            CLI_FLAG="";               env_key="";;
        1) AUTH_CHOICE="deepseek-api-key";    CLI_FLAG="--deepseek-api-key";    env_key="DEEPSEEK_API_KEY";;
        2) AUTH_CHOICE="openai-api-key";      CLI_FLAG="--openai-api-key";      env_key="OPENAI_API_KEY";;
        3) AUTH_CHOICE="apiKey";              CLI_FLAG="--anthropic-api-key";   env_key="ANTHROPIC_API_KEY";;
        4) AUTH_CHOICE="gemini-api-key";      CLI_FLAG="--gemini-api-key";      env_key="GEMINI_API_KEY";;
        5) AUTH_CHOICE="openrouter-api-key";  CLI_FLAG="--openrouter-api-key";  env_key="OPENROUTER_API_KEY";;
        6) AUTH_CHOICE="together-api-key";    CLI_FLAG="--together-api-key";    env_key="TOGETHER_API_KEY";;
        7) AUTH_CHOICE="xai-api-key";         CLI_FLAG="--xai-api-key";         env_key="XAI_API_KEY";;
        8) AUTH_CHOICE="mistral-api-key";     CLI_FLAG="--mistral-api-key";     env_key="MISTRAL_API_KEY";;
        9) AUTH_CHOICE="fireworks-api-key";   CLI_FLAG="--fireworks-api-key";     env_key="FIREWORKS_API_KEY";;
        *) pretty_print "Invalid choice" "${fg_red}"; exit 1;;
    esac

    # Try to read API key from env file, then fall back to prompt
    API_KEY=""
    if [[ -n "${ENV_FILE:-}" ]]; then
        API_KEY=$(env_file_lookup "$ENV_FILE" "$env_key")
        if [[ -z "$API_KEY" ]]; then
            # Fallback: try generic names
            API_KEY=$(env_file_lookup "$ENV_FILE" "LLM_API_KEY")
        fi
        if [[ -z "$API_KEY" ]]; then
            API_KEY=$(env_file_lookup "$ENV_FILE" "API_KEY")
        fi
        if [[ -n "$API_KEY" ]]; then
            pretty_print "API key read from $ENV_FILE (${env_key})"
        else
            pretty_print "No API key found in $ENV_FILE — falling back to manual entry" "${fg_yellow}"
        fi
    fi

    if [[ "$PROVIDER_IDX" != "0" ]] && [[ -z "$API_KEY" ]]; then
        read -rp "  Paste your API key: " API_KEY
    fi
    echo ""
}

# ---- DESC: Deploy workspace files --------------------------------------------
function deploy_workspace() {
    local workspace_target="$WORKSPACE_TARGET"

    pretty_print "Deploying workspace…" "${fg_cyan}"
    if [[ -d "$workspace_target" ]] && [[ "$(ls -A "$workspace_target" 2>/dev/null)" ]]; then
        mv "$workspace_target" "$workspace_target.backup.$(date +%s)"
        pretty_print "Backed up existing workspace" "${fg_yellow}"
    fi
    mkdir -p "$workspace_target"
    if [[ -d "$INSTALL_DIR/workspace" ]]; then
        shopt -s dotglob
        cp -r "$INSTALL_DIR/workspace/"* "$workspace_target/" 2>/dev/null || true
        shopt -u dotglob
    else
        pretty_print "WARNING: workspace/ directory missing in source — deploying defaults" "${fg_yellow}"
    fi
    cd "$workspace_target"
    # Escape special sed chars and use | delimiter to avoid clashes
    local sn="${AGENT_NAME//\\/\\\\}"; sn="${sn//|/\|}"; sn="${sn//&/\\&}"
    sed -i "s|{{AGENT_NAME}}|$sn|g; s|{{AGENT_EMOJI}}|✨|g" IDENTITY.md
    sed -i "s|{{YOUR_NAME}}|friend|g; s|{{PREFERRED_NAME}}|friend|g; s|{{TIMEZONE}}|UTC|g" USER.md
    pretty_print "Workspace ready"
}

# ---- DESC: Install Ollama locally (no sudo) ----------------------------------
function install_ollama_local() {
    local url="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.zst"
    local dest="$INSTALL_DIR/.local"

    mkdir -p "$dest/bin"
    export PATH="$dest/bin:$PATH"

    # Try curl + tar with --zstd (modern tar supports this directly)
    pretty_print "Downloading Ollama…" "${fg_cyan}"
    if curl -fsL "$url" | tar --zstd -xC "$dest" 2>/dev/null; then
        pretty_print "Ollama extracted to $dest/bin/"
        return
    fi

    # Fall back to Python-based extraction
    pretty_print "tar --zstd not available, using Python…" "${fg_yellow}"
    pip install zstandard -q 2>/dev/null || true
    local dl_script="/tmp/_ollama_dl_$$.py"
    cat > "$dl_script" << 'PYEOF'
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

    OLLAMA_URL="$url" OLLAMA_DEST="$dest" python3 "$dl_script" || true
    rm -f "$dl_script"
}

# ---- DESC: Set up Ollama runtime (Mem0 uses it for embeddings) ---------------
function setup_ollama() {
    echo ""
    pretty_print "Core: Ollama (Embeddings)" "${ta_bold}"
    pretty_print "Mem0 uses Ollama for vector embeddings." "${fg_cyan}"

    if ! command -v ollama >/dev/null 2>&1; then
        pretty_print "Installing Ollama locally…" "${fg_cyan}"
        install_ollama_local || pretty_print "Ollama install had issues" "${fg_yellow}"
    fi

    if command -v ollama >/dev/null 2>&1; then
        pretty_print "Ollama ready"

        # Start Ollama service
        if ! curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
            pretty_print "Starting Ollama service…" "${fg_cyan}"
            ollama serve >/dev/null 2>&1 &
            ollama_pid=$!
            for i in 1 2 3 4 5; do
                sleep 2
                if curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
                    break
                fi
                if [[ $i -eq 5 ]]; then
                    pretty_print "Ollama starting slowly" "${fg_yellow}"
                fi
            done
        fi

        if curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
            pretty_print "Ollama running on localhost:11434"

            # Pull embedding model for Mem0: nomic-embed-text
            pretty_print "Pulling embedding model (nomic-embed-text)…" "${fg_cyan}"
            if ollama pull nomic-embed-text 2>&1; then
                pretty_print "Embedding model ready (8192 ctx, 768 dim)"
            else
                pretty_print "First pull failed — retrying…" "${fg_yellow}"
                sleep 3
                if ollama pull nomic-embed-text 2>&1; then
                    pretty_print "Embedding model ready (retry)"
                else
                    pretty_print "Pull failed — run ollama pull nomic-embed-text later" "${fg_yellow}"
                fi
            fi
        else
            pretty_print "Ollama not reachable" "${fg_yellow}"
        fi
    else
        pretty_print "Ollama not found — install manually" "${fg_yellow}"
    fi
}

# ---- DESC: Install Mem0 plugin for OpenClaw ----------------------------------
function install_mem0_plugin() {
    echo ""
    pretty_print "Mem0 (Automatic Memory)" "${ta_bold}"
    pretty_print "Installing @mem0/openclaw-mem0 plugin…" "${fg_cyan}"

    local oc_bin="$INSTALL_DIR/.local/bin/openclaw"
    if [[ ! -f "$oc_bin" ]]; then
        oc_bin="$(command -v openclaw || true)"
    fi
    if [[ -z "$oc_bin" ]]; then
        pretty_print "OpenClaw binary not found — can't install Mem0 plugin" "${fg_yellow}"
        return
    fi

    # Ensure OPENCLAW_STATE_DIR points to the test/install dir, not ~/.openclaw
    export OPENCLAW_STATE_DIR="$INSTALL_DIR/.openclaw"
    export OPENCLAW_DIR="$WORKSPACE_TARGET"

    local mem0_installed=false

    # Primary install path
    pretty_print "  Installing via openclaw plugins install…" "${fg_cyan}"
    if HOME=/tmp "$oc_bin" plugins install @mem0/openclaw-mem0 2>&1; then
        mem0_installed=true
    fi

    # Fallback: npm install -g, then register with OpenClaw
    if ! $mem0_installed; then
        pretty_print "  Primary install failed — trying npm fallback…" "${fg_yellow}"
        if HOME=/tmp npm install -g @mem0/openclaw-mem0 2>&1; then
            pretty_print "  Package downloaded — registering with OpenClaw…" "${fg_cyan}"
            if HOME=/tmp "$oc_bin" plugins install @mem0/openclaw-mem0 2>&1; then
                mem0_installed=true
            fi
        fi
    fi

    if $mem0_installed; then
        pretty_print "Mem0 plugin installed" "${fg_green}"
        # Install Mem0's OSS dependency (ollama npm package for embeddings)
        pretty_print "  Installing Mem0 OSS dependency (ollama npm)…" "${fg_cyan}"
        cd "$INSTALL_DIR/.openclaw/npm" 2>/dev/null && npm install ollama 2>&1 | tail -2 || true
        cd "$orig_cwd"

        # Patch recall timeout from 8s to 30s (default too short for Ollama inference)
        local plugin_file="$INSTALL_DIR/.openclaw/npm/node_modules/@mem0/openclaw-mem0/dist/index.js"
        if [[ -f "$plugin_file" ]]; then
            sed -i 's/RECALL_TIMEOUT_MS = 8e3/RECALL_TIMEOUT_MS = 30e3/' "$plugin_file" 2>/dev/null && \
                pretty_print "  Recall timeout patched to 30s" "${fg_cyan}"
        fi
    else
        pretty_print "⚠  Mem0 plugin install FAILED" "${fg_red}"
        pretty_print "  The agent won't have long-term memory until this is fixed." "${fg_red}"
        pretty_print "  Try manually: openclaw plugins install @mem0/openclaw-mem0" "${fg_yellow}"
        exit 1
    fi
}

# ---- DESC: Configure Mem0 in openclaw.json -----------------------------------
function configure_mem0() {
    local config_path="$INSTALL_DIR/.openclaw/openclaw.json"

    if [[ ! -f "$config_path" ]]; then
        pretty_print "openclaw.json not found at $config_path — Mem0 config skipped" "${fg_yellow}"
        return
    fi

    pretty_print "Configuring Mem0…" "${fg_cyan}"

    # Generate random 6-char suffix for user ID
    local rand_suffix="$(tr -dc a-z0-9 < /dev/urandom 2>/dev/null | head -c6 || echo "x$(date +%s | tail -c6)")"
    local mem0_user_id="${AGENT_NAME}-${rand_suffix}"

    # Determine LLM provider for Mem0 extraction
    # IMPORTANT: Use OpenAI-compatible endpoint for Ollama, NOT native ollama npm
    # The ollama npm package has compatibility issues with Ollama v0.24.0+
    # The OpenAI-compatible endpoint (/v1/chat/completions) works reliably.
    local mem0_llm_provider=""
    local mem0_llm_model=""
    local mem0_llm_key=""
    local mem0_llm_baseurl=""
    case "$PROVIDER_IDX" in
        0) mem0_llm_provider="openai";    mem0_llm_model="qwen2.5:7b";           mem0_llm_key=""; mem0_llm_baseurl="http://127.0.0.1:11434/v1";;
        1) mem0_llm_provider="deepseek";    mem0_llm_model="deepseek-chat";       mem0_llm_key="\${DEEPSEEK_API_KEY}"; mem0_llm_baseurl="";;
        2) mem0_llm_provider="openai";      mem0_llm_model="gpt-5-mini";          mem0_llm_key="\${OPENAI_API_KEY}"; mem0_llm_baseurl="";;
        3) mem0_llm_provider="anthropic";   mem0_llm_model="claude-sonnet-4-5-20250514"; mem0_llm_key="\${ANTHROPIC_API_KEY}"; mem0_llm_baseurl="";;
        4) mem0_llm_provider="gemini";      mem0_llm_model="gemini-2.5-flash";    mem0_llm_key="\${GEMINI_API_KEY}"; mem0_llm_baseurl="";;
        5) mem0_llm_provider="openrouter";  mem0_llm_model="openrouter/auto";     mem0_llm_key="\${OPENROUTER_API_KEY}"; mem0_llm_baseurl="";;
        6) mem0_llm_provider="together";    mem0_llm_model="mistralai/Mixtral-8x7B-Instruct-v0.1"; mem0_llm_key="\${TOGETHER_API_KEY}"; mem0_llm_baseurl="";;
        7) mem0_llm_provider="xai";         mem0_llm_model="grok-2";              mem0_llm_key="\${XAI_API_KEY}"; mem0_llm_baseurl="";;
        8) mem0_llm_provider="mistral";     mem0_llm_model="mistral-large-latest"; mem0_llm_key="\${MISTRAL_API_KEY}"; mem0_llm_baseurl="";;
        9) mem0_llm_provider="fireworks";   mem0_llm_model="accounts/fireworks/models/llama-v3p2-90b-vision-instruct"; mem0_llm_key="\${FIREWORKS_API_KEY}"; mem0_llm_baseurl="";;
        *) mem0_llm_provider="openai";      mem0_llm_model="qwen2.5:7b";          mem0_llm_key=""; mem0_llm_baseurl="http://127.0.0.1:11434/v1";;
    esac

    # For local Ollama (provider ID 0), the case statement above already sets
    # provider to 'openai' with baseURL pointing to Ollama's /v1 endpoint.
    # This handles the ollama npm package compatibility issue with Ollama v0.24.0.

    local db_path="$INSTALL_DIR/.mem0/vector_store.db"

    # Use Python to patch the JSON config — handles all sections cleanly
    python3 << PYEOF
import json, os

config_path = "$config_path"

with open(config_path, 'r') as f:
    config = json.load(f)

# 1. Disable the bundled session-memory hook
hooks = config.setdefault('hooks', {})
internal = hooks.setdefault('internal', {})
entries = internal.setdefault('entries', {})
sm = entries.setdefault('session-memory', {})
sm['enabled'] = False

# 2. Configure plugins section
plugins = config.setdefault('plugins', {})
plugins['allow'] = ['openclaw-mem0']
plugins['slots'] = {'memory': 'openclaw-mem0'}

# 3. Mem0 plugin entry with full config
plugin_entries = plugins.setdefault('entries', {})
plugin_entries['openclaw-mem0'] = {
    'enabled': True,
    'hooks': {
        'allowConversationAccess': True
    },
    'config': {
        'mode': 'open-source',
        'userId': '$mem0_user_id',
        'autoCapture': True,
        'autoRecall': True,
        'topK': 5,
        'skills': {
            'triage': {'enabled': True},
            'recall': {
                'enabled': True,
                'tokenBudget': 1500,
                'rerank': True,
                'keywordSearch': True,
                'identityAlwaysInclude': True
            },
            'dream': {'enabled': True},
            'domain': 'companion'
        },
        'oss': {
            'embedder': {
                'provider': 'ollama',
                'config': {'model': 'nomic-embed-text'}
            },
            'vectorStore': {
                'provider': 'memory',
                'config': {'dbPath': '$db_path'}
            },
            'llm': {
                'provider': '$mem0_llm_provider',
                'config': {
                    'model': '$mem0_llm_model',
                    'apiKey': '$mem0_llm_key','baseURL': '$mem0_llm_baseurl'
                }
            }
        }
    }
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print(f"Mem0 configured: user_id=$mem0_user_id, llm=$mem0_llm_provider/$mem0_llm_model")
PYEOF

    # Create Mem0 data directory
    mkdir -p "$INSTALL_DIR/.mem0"

    pretty_print "Mem0 configuration written" "${fg_green}"
}

# ---- DESC: Deploy scripts and tools ------------------------------------------
function deploy_scripts() {
    # Agent tools (local to project)
    local tools_dir="$INSTALL_DIR/.openclaw/tools"
    mkdir -p "$tools_dir"
    cp "$INSTALL_DIR/scripts/repomap" "$tools_dir/repomap" 2>/dev/null || true
    chmod +x "$tools_dir/repomap" 2>/dev/null || true

    # Install aider-chat (repomap dependency)
    if pip3 install aider-chat -q 2>/dev/null || pip install aider-chat -q 2>/dev/null; then
        pretty_print "aider-chat ready"
    else
        pretty_print "aider-chat install skipped (not critical)" "${fg_yellow}"
    fi
}

# ---- DESC: Bootstrap OpenClaw configuration ----------------------------------
function bootstrap_openclaw() {
    echo ""
    pretty_print "Configuring OpenClaw…" "${ta_bold}"
    export OPENCLAW_STATE_DIR="$INSTALL_DIR/.openclaw"
    export OPENCLAW_DIR="$WORKSPACE_TARGET"
    # Use a writable tmp HOME so openclaw doesn't touch ~/ or fail on /tmp
    local oc_home="$INSTALL_DIR/.tmp-oc-home"
    mkdir -p "$oc_home"
    # Find openclaw binary (local install or system-wide)
    local oc_bin="$INSTALL_DIR/.local/bin/openclaw"
    if [[ ! -f "$oc_bin" ]]; then
        oc_bin="$(command -v openclaw || true)"
    fi
    if [[ -z "$oc_bin" ]]; then
        pretty_print "OpenClaw binary not found — can't configure provider" "${fg_yellow}"
        pretty_print "  Re-run setup.sh after OpenClaw is installed" "${fg_yellow}"
        return
    fi
    HOME="$oc_home" "$oc_bin" onboard --non-interactive --flow quickstart --accept-risk --skip-health 2>&1 | tail -3 || true
    # For Ollama (local), skip the auth step
    if [[ -n "$AUTH_CHOICE" ]]; then
        HOME="$oc_home" "$oc_bin" onboard --non-interactive --accept-risk --auth-choice "$AUTH_CHOICE" "$CLI_FLAG" "$API_KEY" 2>&1 | tail -2 || \
            pretty_print "Provider setup had issues — run 'openclaw onboard' manually" "${fg_yellow}"
    else
        pretty_print "Skipping provider auth (local Ollama)" "${fg_cyan}"
    fi
    # Clean up temp home
    rm -rf "$oc_home" 2>/dev/null || true
    # Move any stray ~/.openclaw/ into project dir
    if [[ -d "$HOME/.openclaw" ]]; then
        mv "$HOME/.openclaw" "$INSTALL_DIR/.leaks/.openclaw-onboard" 2>/dev/null || rm -rf "$HOME/.openclaw" 2>/dev/null || true
    fi

    # Fix workspace path in config: onboard may have written a path based on
    # the overridden HOME (.tmp-oc-home), which is now deleted. Point it to
    # the actual deployed workspace at .openclaw/workspace/.
    OPENCLAW_CONFIG_JSON="$INSTALL_DIR/.openclaw/openclaw.json" \
    CORRECT_WORKSPACE="$WORKSPACE_TARGET" \
    python3 << 'PYEOF' || pretty_print "Config fix skipped" "${fg_yellow}"
import json, os

config_path = os.environ['OPENCLAW_CONFIG_JSON']
correct_path = os.environ['CORRECT_WORKSPACE']

with open(config_path, 'r') as f:
    config = json.load(f)

# 1. Fix workspace path (onboard writes stale .tmp-oc-home path)
agents = config.setdefault('agents', {})
defaults = agents.setdefault('defaults', {})
old_path = defaults.get('workspace')
changed = False
if old_path and old_path != correct_path:
    changed = True
defaults['workspace'] = correct_path

# 2. Pin web search provider to DuckDuckGo (no API key needed, works out of box)
#    Avoids broken providers like kimi that get enabled during onboard
search_cfg = config.setdefault('tools', {}).setdefault('web', {}).setdefault('search', {})
if not search_cfg.get('provider'):
    search_cfg['provider'] = 'duckduckgo'
    changed = True

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

if changed:
    print(f'Config updated: workspace={correct_path}, search_provider=duckduckgo')
PYEOF
}

# ---- DESC: Main control flow --------------------------------------------------
# ---- DESC: Initialize health state ----------------------------------------
function init_health_state() {
    local health_file="$INSTALL_DIR/.openclaw/health-state.json"
    local ollama_status="down"
    local mem0_status="down"
    local disk_pct

    curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1 && ollama_status="ok"

    # Check Mem0 status via OpenClaw CLI
    local oc_bin="$INSTALL_DIR/.local/bin/openclaw"
    if [[ ! -f "$oc_bin" ]]; then
        oc_bin="$(command -v openclaw || true)"
    fi
    if [[ -n "$oc_bin" ]]; then
        if "$oc_bin" mem0 status >/dev/null 2>&1; then
            mem0_status="ok"
        fi
    fi

    disk_pct=$(df -h "$HOME" | awk 'NR==2 {print $5}' | sed 's/%//')

    mkdir -p "$(dirname "$health_file")"
    cat > "$health_file" << EOF
{
  "last_checked": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ollama": { "status": "$ollama_status" },
  "mem0": { "status": "$mem0_status" },
  "disk": { "status": "ok", "usage_pct": $disk_pct }
}
EOF
    pretty_print "Health state initialized"
}


# ---- DESC: Write run.sh wrapper ----------------------------------------------
function write_run_script() {
    cat > "$INSTALL_DIR/run.sh" << 'RUNEOF'
#!/usr/bin/env bash
# run.sh — Start metamorphosis-agent (portable)
# Source env vars and launch OpenClaw from the local install.
cd "$(dirname "$0")"
export OPENCLAW_STATE_DIR="$(pwd)/.openclaw"
export OPENCLAW_DIR="$(pwd)/.openclaw/workspace"
export OPENCLAW_WORKSPACE_DIR="$(pwd)/.openclaw/workspace"
export PATH="$(pwd)/.local/bin:$PATH"
export npm_config_cache="$(pwd)/.npm-cache"

# Mem0 data directory
export MEM0_DIR="$(pwd)/.mem0"

# Look for openclaw in local install dir, then system PATH
OPENCLAW_BIN="$(pwd)/.local/bin/openclaw"
if [[ ! -f "$OPENCLAW_BIN" ]]; then
    if command -v openclaw >/dev/null 2>&1; then
        OPENCLAW_BIN="$(command -v openclaw)"
    else
        echo "" >&2
        echo "ERROR: OpenClaw binary not found." >&2
        echo "  Tried: $OPENCLAW_BIN" >&2
        echo "  Re-run setup.sh, or install manually:" >&2
        echo "    npm install -g openclaw" >&2
        echo "" >&2
        exit 1
    fi
fi

exec "$OPENCLAW_BIN" "$@"
RUNEOF
    chmod +x "$INSTALL_DIR/run.sh"
    pretty_print "Run script: ./run.sh"
}

# ---- DESC: Clean up stray user-level files from setup ------------------------
function cleanup_portable() {
    local backup_dir="$INSTALL_DIR/.leaks"
    mkdir -p "$backup_dir"

    # Move any stray files from ~/ into the project dir instead of deleting
    for dir in .npm .openclaw .openclaw-metamorphosis .local .openviking; do
        if [[ -d "$HOME/$dir" ]]; then
            mv "$HOME/$dir" "$backup_dir/$dir" 2>/dev/null || rm -rf "$HOME/$dir" 2>/dev/null || true
        fi
    done

    pretty_print "Portable setup complete — no files left in ~/"
}

# ---- DESC: Create HOME symlinks for library compat (post-cleanup) -------------


function main() {
    trap script_trap_err ERR
    trap script_trap_exit EXIT

    script_init "$@"
    parse_params "$@"
    colour_init

    REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
    INSTALL_DIR="$REPO_DIR"
    WORKSPACE_TARGET="$INSTALL_DIR/.openclaw/workspace"
    # Redirect npm cache to local dir before any npm command runs
    export npm_config_cache="$INSTALL_DIR/.npm-cache"

    print_banner
    prompt_install_dir

    # If user specified a different target dir, copy repo there and switch
    if [[ -n "${TARGET_DIR:-}" && "$TARGET_DIR" != "$INSTALL_DIR" ]]; then
        mkdir -p "$TARGET_DIR"
        pretty_print "Copying setup files to $TARGET_DIR…" "${fg_cyan}"
        shopt -s dotglob
        for _item in "$REPO_DIR/"*; do
            local _name
            _name="$(basename "$_item")"
            [[ "$_name" == ".git" ]] && continue
            cp -r "$_item" "$TARGET_DIR/" 2>/dev/null || true
        done
        shopt -u dotglob
        INSTALL_DIR="$TARGET_DIR"
        WORKSPACE_TARGET="$INSTALL_DIR/.openclaw/workspace"
        npm_config_cache="$INSTALL_DIR/.npm-cache"
        cd "$INSTALL_DIR"
        pretty_print "Installing to: $INSTALL_DIR" "${fg_cyan}"
    fi

    check_prerequisites
    install_nodejs
    install_openclaw
    gather_identity
    deploy_workspace
    setup_ollama
    install_mem0_plugin
    deploy_scripts
    bootstrap_openclaw
    configure_mem0
    init_health_state
    write_run_script
    cleanup_portable

    # Mark setup as complete
    touch "$INSTALL_DIR/.setup-complete"

    echo ""
    cd "$INSTALL_DIR"
    if [[ -n "${TARGET_DIR:-}" && "$TARGET_DIR" != "$REPO_DIR" ]]; then
        rm -rf "$REPO_DIR" 2>/dev/null || true
    fi

    echo ""
    pretty_print "✅ Metamorphosis ready in: $INSTALL_DIR" "${fg_green}"
    pretty_print "   cd $INSTALL_DIR && ./run.sh" "${fg_cyan}"
}

if ! (return 0 2> /dev/null); then
    main "$@"
fi
