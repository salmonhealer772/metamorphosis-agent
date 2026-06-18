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

Interactive prompts will ask for agent name, LLM provider, and API key.
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
    cd "$orig_cwd"

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

# ---- DESC: Bootstrap pip (handles Ubuntu 24.04 PEP 668) ---------------------
function bootstrap_pip() {
    pretty_print "Python Package Management" "${fg_cyan}"

    PIP_CMD=""
    if python3 -m pip --version >/dev/null 2>&1; then
        PIP_CMD="python3 -m pip"
        pretty_print "pip already available ($(python3 -m pip --version | cut -d' ' -f2))"
        return
    fi

    pretty_print "pip not found — attempting to install…" "${fg_cyan}"

    # pip.pyz (no sudo, handles PEP 668 via --break-system-packages)
    pretty_print "Installing pip via pip.pyz…" "${fg_cyan}"
    pretty_print "Downloading pip.pyz…" "${fg_cyan}"
    if ! curl -sL --connect-timeout 10 https://bootstrap.pypa.io/pip/pip.pyz -o /tmp/pip.pyz 2>/dev/null; then
        pretty_print "pip.pyz download failed (network issue)" "${fg_yellow}"
    fi

    if python3 /tmp/pip.pyz install --user --break-system-packages pip -q 2>&1; then
        export PATH="$HOME/.local/bin:$PATH"
        if python3 -m pip --version >/dev/null 2>&1; then
            PIP_CMD="python3 -m pip"
            pretty_print "pip installed via pip.pyz ($(python3 -m pip --version | cut -d' ' -f2))"
            return
        fi
    fi

    # Final fallback: venv
    if python3 -m venv "$HOME/.openclaw/venv" 2>&1; then
        PIP_CMD="$HOME/.openclaw/venv/bin/pip"
        pretty_print "Created Python venv at ~/.openclaw/venv"
        return
    fi

    pretty_print "No pip available after trying: pip.pyz and venv." "${fg_red}"
    pretty_print "Install pip manually or use: python3 -m venv ~/.openclaw/venv" "${fg_red}"
    exit 1
}

# ---- DESC: Set up PIP_INSTALL helper variable --------------------------------
function setup_pip_install() {
    PIP_INSTALL="$PIP_CMD install --user --break-system-packages"
    if echo "$PIP_CMD" | grep -q "/venv/bin/pip"; then
        PIP_INSTALL="$PIP_CMD install"
    fi
}

# ---- DESC: Install openviking Python package ---------------------------------
function install_openviking_pkg() {
    pretty_print "OpenViking (Vector Memory)" "${fg_cyan}"
    
    if python3 -c "import openviking" 2>/dev/null; then
        pretty_print "openviking $(python3 -c 'import openviking; print(openviking.__version__)' 2>/dev/null) already installed"
        return
    fi

    pretty_print "Installing openviking (this may take a minute — 50+ dependencies)…" "${fg_cyan}"
    if $PIP_INSTALL openviking 2>&1; then
        pretty_print "openviking installed"
    else
        pretty_print "openviking install failed" "${fg_yellow}"
        pretty_print "  Try: $PIP_INSTALL openviking" "${fg_yellow}"
        pretty_print "  Continuing without vector memory." "${fg_yellow}"
    fi

    mkdir -p "$HOME/.openclaw/workspace/.openviking"
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
    if ! command -v openclaw >/dev/null 2>&1; then
        pretty_print "Installing OpenClaw…" "${fg_cyan}"
        npm install -g openclaw --prefix="$INSTALL_DIR/.local" --prefix="$INSTALL_DIR/.local"
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

# ---- DESC: Gather agent identity from user -----------------------------------
function gather_identity() {
    echo ""
    pretty_print "→ Agent identity" "${ta_bold}"
    read -rp "  Agent name (e.g. Fade): " AGENT_NAME

    echo ""
    pretty_print "→ LLM provider" "${ta_bold}"
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
    local env_key=""
    case "$PROVIDER_IDX" in
        1) AUTH_CHOICE="deepseek-api-key";    CLI_FLAG="--deepseek-api-key";    env_key="DEEPSEEK_API_KEY";;
        2) AUTH_CHOICE="openai-api-key";      CLI_FLAG="--openai-api-key";      env_key="OPENAI_API_KEY";;
        3) AUTH_CHOICE="apiKey";              CLI_FLAG="--anthropic-api-key";   env_key="ANTHROPIC_API_KEY";;
        4) AUTH_CHOICE="gemini-api-key";      CLI_FLAG="--gemini-api-key";      env_key="GEMINI_API_KEY";;
        5) AUTH_CHOICE="openrouter-api-key";  CLI_FLAG="--openrouter-api-key";  env_key="OPENROUTER_API_KEY";;
        6) AUTH_CHOICE="together-api-key";    CLI_FLAG="--together-api-key";    env_key="TOGETHER_API_KEY";;
        7) AUTH_CHOICE="xai-api-key";         CLI_FLAG="--xai-api-key";         env_key="XAI_API_KEY";;
        8) AUTH_CHOICE="mistral-api-key";     CLI_FLAG="--mistral-api-key";     env_key="MISTRAL_API_KEY";;
        9) AUTH_CHOICE="fireworks-api-key";   CLI_FLAG="--fireworks-api-key";   env_key="FIREWORKS_API_KEY";;
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

    if [[ -z "$API_KEY" ]]; then
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
    shopt -s dotglob
    cp -r "$REPO_DIR/workspace/"* "$workspace_target/"
    shopt -u dotglob
    cd "$workspace_target"
    sed -i "s/{{AGENT_NAME}}/$AGENT_NAME/g; s/{{AGENT_EMOJI}}/✨/g" IDENTITY.md
    sed -i "s/{{YOUR_NAME}}/friend/g; s/{{PREFERRED_NAME}}/friend/g; s/{{TIMEZONE}}/UTC/g" USER.md
    chmod +x ov.py
    pretty_print "Workspace ready"
}

# ---- DESC: Install Ollama locally (no sudo) ----------------------------------
function install_ollama_local() {
    local url="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.zst"
    local dest="$INSTALL_DIR/.local"

    mkdir -p "$dest/bin"
    export PATH="$dest/bin:$PATH"

    python3 -c "import zstandard" 2>/dev/null || {
        pretty_print "Installing zstandard for Ollama tarball…" "${fg_cyan}"
        $PIP_INSTALL zstandard -q 2>&1 || true
    }

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

# ---- DESC: Set up Ollama + OpenViking memory system --------------------------
function setup_vector_memory() {
    echo ""
    pretty_print "Core: Vector Memory (OpenViking)" "${ta_bold}"
    pretty_print "The agent needs this to remember you across sessions." "${fg_cyan}"

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

            # Pull model (service is up, so this works)
            pretty_print "Pulling embedding model (all-minilm)…" "${fg_cyan}"
            if ollama pull all-minilm 2>&1; then
                pretty_print "Embedding model ready"
            else
                pretty_print "First pull failed — retrying…" "${fg_yellow}"
                sleep 3
                if ollama pull all-minilm 2>&1; then
                    pretty_print "Embedding model ready (retry)"
                else
                    pretty_print "Pull failed — run ollama pull all-minilm later" "${fg_yellow}"
                fi
            fi
        else
            pretty_print "Ollama not reachable" "${fg_yellow}"
        fi
    else
        pretty_print "Ollama not found — install manually" "${fg_yellow}"
    fi

    # Configure OpenViking
    mkdir -p "$INSTALL_DIR/.openviking"
    local ov_data_dir="$WORKSPACE_TARGET/.openviking"
    mkdir -p "$ov_data_dir"
    cat > "$INSTALL_DIR/.openviking/ov.conf" << OVCONF
{
  "storage": {
    "workspace": "$ov_data_dir"
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
    pretty_print "OpenViking configured"

    # Verify
    if python3 -c "import openviking" 2>/dev/null; then
        if cd "$WORKSPACE_TARGET" 2>/dev/null; then
            if python3 ov.py status 2>&1 | grep -q "Semantic search: OK"; then
                pretty_print "OpenViking operational — semantic search online"
            else
                pretty_print "OpenViking package installed but status check had issues" "${fg_yellow}"
            fi
            cd "$orig_cwd"
        fi
    fi

    pretty_print "  python3 ov.py find \"query\"  — search" "${fg_cyan}"
    pretty_print "  python3 ov.py store \"fact\" — save" "${fg_cyan}"
    pretty_print "  python3 ov.py status       — health" "${fg_cyan}"
}

# ---- DESC: Deploy scripts and tools ------------------------------------------
function deploy_scripts() {
    # Agent tools (local to project)
    local tools_dir="$INSTALL_DIR/.openclaw/tools"
    mkdir -p "$tools_dir"
    cp "$REPO_DIR/scripts/repomap" "$tools_dir/repomap" 2>/dev/null || true
    chmod +x "$tools_dir/repomap" 2>/dev/null || true

    # Install aider-chat (repomap dependency)
    if python3 -c "import aider" 2>/dev/null; then
        pretty_print "aider-chat already installed"
    else
        pretty_print "Installing aider-chat (required by repomap)…" "${fg_cyan}"
        $PIP_INSTALL aider-chat -q 2>&1 || pretty_print "aider-chat install failed" "${fg_yellow}"
    fi
}


# ---- DESC: Bootstrap OpenClaw configuration ----------------------------------
function bootstrap_openclaw() {
    echo ""
    pretty_print "Configuring OpenClaw…" "${ta_bold}"
    export OPENCLAW_STATE_DIR="$INSTALL_DIR/.openclaw"
    export OPENCLAW_DIR="$WORKSPACE_TARGET"
    "$INSTALL_DIR/.local/bin/openclaw" onboard --non-interactive --flow quickstart --accept-risk --skip-health 2>&1 | tail -3 || true
    "$INSTALL_DIR/.local/bin/openclaw" onboard --non-interactive --accept-risk --auth-choice "$AUTH_CHOICE" "$CLI_FLAG" "$API_KEY" 2>&1 | tail -2 || \
        pretty_print "Provider setup had issues — run 'openclaw onboard' manually" "${fg_yellow}"
}

# ---- DESC: Main control flow --------------------------------------------------
# ---- DESC: Initialize health state ----------------------------------------
function init_health_state() {
    local health_file="$INSTALL_DIR/.openclaw/health-state.json"
    local ollama_status="down"
    local openviking_status="down"
    local model_status="down"
    local disk_pct

    curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1 && ollama_status="ok"
    if [[ "$ollama_status" = "ok" ]]; then
        cd "$WORKSPACE_TARGET" 2>/dev/null
        python3 "$WORKSPACE_TARGET/ov.py" status 2>&1 | grep -q "Semantic search: OK" && openviking_status="ok"
        ollama list 2>&1 | grep -q all-minilm && model_status="ok"
    fi
    disk_pct=$(df -h "$HOME" | awk 'NR==2 {print $5}' | sed 's/%//')

    mkdir -p "$(dirname "$health_file")"
    cat > "$health_file" << EOF
{
  "last_checked": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ollama": { "status": "$ollama_status" },
  "openviking": { "status": "$openviking_status" },
  "all_minilm": { "status": "$model_status" },
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
export PATH="$(pwd)/.local/bin:$PATH"
exec "$(pwd)/.local/bin/openclaw" "$@"
RUNEOF
    chmod +x "$INSTALL_DIR/run.sh"
    pretty_print "Run script: ./run.sh"
}

function main() {
    trap script_trap_err ERR
    trap script_trap_exit EXIT

    script_init "$@"
    parse_params "$@"
    colour_init

    REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
    INSTALL_DIR="$REPO_DIR"
    WORKSPACE_TARGET="$INSTALL_DIR/.openclaw/workspace"

    print_banner
    check_prerequisites
    detect_distro
    bootstrap_pip
    setup_pip_install
    install_openviking_pkg
    install_nodejs
    install_openclaw
    gather_identity
    deploy_workspace
    setup_vector_memory
    deploy_scripts
    bootstrap_openclaw
    init_health_state
    write_run_script

    echo ""
    pretty_print "✅ metamorphosis-agent is ready" "${fg_green}"
    echo ""
    pretty_print "Start with: ./run.sh" "${fg_cyan}"
}

if ! (return 0 2> /dev/null); then
    main "$@"
fi
