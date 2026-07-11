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

# ---- DESC: Bootstrap pip (handles Ubuntu 24.04 PEP 668) ---------------------
function bootstrap_pip() {
    pretty_print "Python Package Management" "${fg_cyan}"

    local ov_venv="$INSTALL_DIR/.openclaw/venv"

    # Always try to create a venv first — isolates all pip packages and
    # sidesteps PEP 668 (externally-managed-environment) completely.
    pretty_print "Creating isolated Python venv…" "${fg_cyan}"
    if python3 -m venv "$ov_venv" 2>&1; then
        PIP_CMD="$ov_venv/bin/pip"
        pretty_print "Created Python venv at $ov_venv"
        return
    fi
    pretty_print "python3 -m venv failed — trying alternatives…" "${fg_yellow}"

    # If pip is not available at all, download it
    PIP_CMD=""
    if ! python3 -m pip --version >/dev/null 2>&1; then
        pretty_print "pip not found — installing via pip.pyz…" "${fg_cyan}"
        if ! curl -sL --connect-timeout 10 https://bootstrap.pypa.io/pip/pip.pyz -o /tmp/pip.pyz 2>/dev/null; then
            pretty_print "pip.pyz download failed (network issue)" "${fg_yellow}"
        fi
        python3 /tmp/pip.pyz install --break-system-packages pip -q 2>&1 || true
    fi

    # Try virtualenv as fallback (can create venvs without the venv module)
    if ! python3 -c "import virtualenv" 2>/dev/null; then
        python3 -m pip install --break-system-packages virtualenv -q 2>/dev/null || true
    fi
    if python3 -c "import virtualenv" 2>/dev/null; then
        python3 -m virtualenv "$ov_venv" 2>&1 && {
            PIP_CMD="$ov_venv/bin/pip"
            pretty_print "Created Python venv via virtualenv"
            return
        }
    fi

    # Last resort: use system pip with --target+--break-system-packages
    if python3 -m pip --version >/dev/null 2>&1; then
        PIP_CMD="python3 -m pip"
        pretty_print "Falling back to system pip (will use --break-system-packages)" "${fg_yellow}"
        return
    fi

    pretty_print "No pip available — install pip manually" "${fg_red}"
    exit 1
}

# ---- DESC: Set up PIP_INSTALL helper variable --------------------------------
function setup_pip_install() {
    PIP_INSTALL="$PIP_CMD install"
    # When using system pip (no venv), redirect to local target dir
    if ! echo "$PIP_CMD" | grep -q "/venv/bin/pip"; then
        local py_libs="$INSTALL_DIR/.openclaw/py-libs"
        PIP_INSTALL="$PIP_CMD install --target=$py_libs --break-system-packages"
        # Add target to Python path so imports work
        export PYTHONPATH="$py_libs:${PYTHONPATH:-}"
    fi
}

# ---- DESC: Install openviking Python package ---------------------------------
function install_openviking_pkg() {
    pretty_print "OpenViking (Vector Memory)" "${fg_cyan}"
    
    # Ensure data dirs exist even if install fails (configs come later)
    mkdir -p "$WORKSPACE_TARGET/.openviking"
    
    if $OV_PYTHON -c "import openviking" 2>/dev/null; then
        pretty_print "openviking $($OV_PYTHON -c 'import openviking; print(openviking.__version__)' 2>/dev/null) already installed"
        return
    fi

    pretty_print "Installing openviking (50+ dependencies, may take a minute)…" "${fg_cyan}"

    # Try 5 strategies in order. First one that succeeds wins.
    local _installed=false
    local _pip_base="$PIP_INSTALL --retries 3 --timeout 120"

    # Strategy 1: Primary — test PyPI directly first (avoids mirror lag)
    pretty_print "  Strategy 1/5: pip install (PyPI)…" "${fg_cyan}"
    if PIP_INDEX_URL="https://pypi.org/simple/" $_pip_base openviking 2>&1; then
        _installed=true
    fi

    # Strategy 2: Retry with default mirror (works when PyPI is up but slow)
    if ! $_installed; then
        pretty_print "  Strategy 2/5: pip install (default mirror)…" "${fg_cyan}"
        if $_pip_base openviking 2>&1; then
            _installed=true
        fi
    fi

    # Strategy 3: Install build deps + retry with --no-build-isolation
    if ! $_installed; then
        pretty_print "  Strategy 3/5: installing build deps & retrying…" "${fg_cyan}"
        command -v gcc >/dev/null 2>&1 || apt-get install -y build-essential python3-dev 2>/dev/null || true
        if $_pip_base --no-build-isolation openviking 2>&1; then
            _installed=true
        fi
    fi

    # Strategy 4: Install without deps first, then let pip resolve deps
    if ! $_installed; then
        pretty_print "  Strategy 4/5: pip install (no-deps + resolve)…" "${fg_cyan}"
        if $_pip_base --no-deps openviking 2>&1 && $_pip_base openviking 2>&1; then
            _installed=true
        fi
    fi

    # Strategy 5: Try uv (faster pip alternative, handles PEP 668 natively)
    if ! $_installed; then
        pretty_print "  Strategy 5/5: trying uv…" "${fg_cyan}"
        if command -v uv >/dev/null 2>&1 || pip install uv -q 2>/dev/null || curl -fsSL https://astral.sh/uv/install.sh | sh 2>/dev/null; then
            if uv pip install --system openviking 2>&1; then
                _installed=true
            fi
        fi
    fi

    if $_installed; then
        pretty_print "openviking installed"
        # Validate: confirm the import actually works with OV_PYTHON
        if $OV_PYTHON -c "import openviking; print(openviking.__version__)" 2>/dev/null; then
            local _ov_ver
            _ov_ver=$($OV_PYTHON -c "import openviking; print(openviking.__version__)" 2>/dev/null)
            pretty_print "OpenViking $_ov_ver verified — import OK" "${fg_green}"
        else
            pretty_print "⚠  openviking pip install claimed success but import failed" "${fg_red}"
            pretty_print "  Run manually: $_pip_base --force-reinstall openviking" "${fg_yellow}"
        fi
    else
        pretty_print "⚠  openviking install FAILED (all 5 strategies)" "${fg_red}"
        pretty_print "  The agent won't have long-term memory until this is fixed." "${fg_red}"
        pretty_print "  Try manually: $_pip_base openviking" "${fg_yellow}"
        pretty_print "  Or: PIP_INDEX_URL=https://pypi.org/simple/ $_pip_base openviking" "${fg_yellow}"
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
    chmod +x ov.py
    pretty_print "Workspace ready"
}

# ---- DESC: Install Ollama locally (no sudo) ----------------------------------
function install_ollama_local() {
    local url="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.zst"
    local dest="$INSTALL_DIR/.local"

    mkdir -p "$dest/bin"
    export PATH="$dest/bin:$PATH"

    $OV_PYTHON -c "import zstandard" 2>/dev/null || {
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

    OLLAMA_URL="$url" OLLAMA_DEST="$dest" $OV_PYTHON "$dl_script" || true
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

            # Pull primary embedding model: nomic-embed-text (8192 token context, 768 dim)
            # This handles large files that all-minilm (512 ctx) can't process.
            pretty_print "Pulling embedding model (nomic-embed-text)…" "${fg_cyan}"
            if ollama pull nomic-embed-text 2>&1; then
                pretty_print "Primary embedding model ready (8192 ctx, 768 dim)"
            else
                pretty_print "First pull failed — retrying…" "${fg_yellow}"
                sleep 3
                if ollama pull nomic-embed-text 2>&1; then
                    pretty_print "Primary embedding model ready (retry)"
                else
                    pretty_print "Pull failed — run ollama pull nomic-embed-text later" "${fg_yellow}"
                fi
            fi

            # Pull legacy all-minilm for backward compatibility
            pretty_print "Pulling legacy model (all-minilm)…" "${fg_cyan}"
            ollama pull all-minilm 2>&1 || true
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
      "model": "nomic-embed-text",
      "dimension": 768
    },
    "max_input_tokens": 4096,
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
    if $OV_PYTHON -c "import openviking; print(openviking.__version__)" 2>/dev/null; then
        local ov_ver
        ov_ver=$($OV_PYTHON -c "import openviking; print(openviking.__version__)" 2>/dev/null)
        if [[ -f "$INSTALL_DIR/.openviking/ov.conf" ]]; then
            pretty_print "OpenViking $ov_ver installed and configured"
        else
            pretty_print "OpenViking $ov_ver installed (config pending)" "${fg_yellow}"
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
    cp "$INSTALL_DIR/scripts/repomap" "$tools_dir/repomap" 2>/dev/null || true
    chmod +x "$tools_dir/repomap" 2>/dev/null || true

    # Deploy verify scripts to workspace (Bug #4 fix)
    cp "$INSTALL_DIR/scripts/verify-openviking.sh" "$WORKSPACE_TARGET/" 2>/dev/null || true
    cp "$INSTALL_DIR/scripts/verify-e2e.py" "$WORKSPACE_TARGET/" 2>/dev/null || true
    chmod +x "$WORKSPACE_TARGET/verify-openviking.sh" 2>/dev/null || true

    # repomap no longer needs aider-chat — uses built-in tree-sitter from openviking
}


# ---- DESC: Deploy auto-capture hook for passive OpenViking memory ------------
function deploy_auto_capture_hook() {
    pretty_print "Auto-Capture Hook" "${fg_cyan}"

    local hook_src="$INSTALL_DIR/hooks/auto-capture-openviking"
    local managed_hooks="$INSTALL_DIR/.openclaw/hooks"

    if [[ ! -d "$hook_src" ]]; then
        pretty_print "Hook source not found at $hook_src — clone the full repo with hooks/ directory" "${fg_red}"
        exit 1
    fi

    mkdir -p "$managed_hooks"
    # Copy hook files to managed directory.
    # Use cp -rL to follow symlinks, then fix permissions:
    # - Directories: 0755 (need +x to be searchable)
    # - Files: 0644 (world-readable)
    # chmod -R 0644 on a directory strips the +x bit, making it
    # unsearchable, so we MUST do files and dirs separately.
    cp -rL "$hook_src" "$managed_hooks/"
    find "$managed_hooks/auto-capture-openviking/" -type d -exec chmod 0755 {} + 2>/dev/null || true
    find "$managed_hooks/auto-capture-openviking/" -type f -exec chmod 0644 {} + 2>/dev/null || true

    pretty_print "Auto-capture hook deployed to $managed_hooks/auto-capture-openviking/"
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
    HOME="$oc_home" "$oc_bin" onboard --non-interactive --accept-risk --auth-choice "$AUTH_CHOICE" "$CLI_FLAG" "$API_KEY" 2>&1 | tail -2 || \
        pretty_print "Provider setup had issues — run 'openclaw onboard' manually" "${fg_yellow}"
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
    local openviking_status="down"
    local model_status="down"
    local disk_pct

    curl -sf http://127.0.0.1:11434/api/version >/dev/null 2>&1 && ollama_status="ok"

    local openviking_reason=""
    if [[ "$ollama_status" = "ok" ]]; then
        cd "$WORKSPACE_TARGET" 2>/dev/null
        if $OV_PYTHON -c "import openviking" 2>/dev/null; then
            if [[ -f "$INSTALL_DIR/.openviking/ov.conf" ]]; then
                openviking_status="ok"
            else
                openviking_reason="missing_config"
            fi
        else
            openviking_reason="package_not_installed"
        fi
        if [[ ! -d "$WORKSPACE_TARGET/.openviking" ]]; then
            openviking_reason="missing_data_dir"
        fi
        ollama list 2>&1 | grep -q nomic-embed-text && model_status="ok"
    else
        openviking_reason="ollama_down"
    fi
    disk_pct=$(df -h "$HOME" | awk 'NR==2 {print $5}' | sed 's/%//')

    mkdir -p "$(dirname "$health_file")"
    cat > "$health_file" << EOF
{
  "last_checked": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "ollama": { "status": "$ollama_status" },
  "openviking": { "status": "$openviking_status", "reason": "$openviking_reason" },
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
export OPENCLAW_WORKSPACE_DIR="$(pwd)/.openclaw/workspace"
export PATH="$(pwd)/.local/bin:$PATH"
export npm_config_cache="$(pwd)/.npm-cache"
# Add venv python to PATH if it exists (so python3 uses the venv interpreter)
if [[ -d "$(pwd)/.openclaw/venv/bin" ]]; then
    export PATH="$(pwd)/.openclaw/venv/bin:$PATH"
fi
# OpenViking: make py-libs importable + point config file to project-local copy
export PYTHONPATH="$(pwd)/.openclaw/py-libs:${PYTHONPATH:-}"
export OPENVIKING_CONFIG_FILE="$(pwd)/.openviking/ov.conf"

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
function setup_home_symlinks() {
    # (HOME symlinks removed — everything stays in INSTALL_DIR)

    # Patch ov.py shebang to use venv python (Bug: was using system python3)
    if [[ -f "$WORKSPACE_TARGET/ov.py" ]] && [[ "$OV_PYTHON" != "python3" ]]; then
        sed -i "1s|.*|#!$OV_PYTHON|" "$WORKSPACE_TARGET/ov.py"
        pretty_print "ov.py shebang patched to venv python" "${fg_cyan}"
    fi

    # Symlink ov.py onto PATH so users can run it from anywhere
    local ov_symlink="$INSTALL_DIR/.local/bin/ov.py"
    if [[ -f "$WORKSPACE_TARGET/ov.py" ]]; then
        ln -sf "$WORKSPACE_TARGET/ov.py" "$ov_symlink"
        chmod +x "$ov_symlink"
        pretty_print "ov.py symlinked to PATH: $ov_symlink" "${fg_cyan}"
    fi

    # Index memory if empty (Bug #5 fix)
    local ov_data="$WORKSPACE_TARGET/.openviking"
    if [[ -d "$ov_data" && -z "$(ls -A "$ov_data" 2>/dev/null)" ]]; then
        if "$OV_PYTHON" -c "import openviking" 2>/dev/null; then
            pretty_print "Indexing initial workspace memory…" "${fg_cyan}"
            cd "$WORKSPACE_TARGET" 2>/dev/null && OPENVIKING_CONFIG_FILE="$INSTALL_DIR/.openviking/ov.conf" "$OV_PYTHON" ov.py index 2>&1 || true
            cd "$orig_cwd"
            pretty_print "Initial memory index complete"
        fi
    fi
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
    detect_distro
    bootstrap_pip
    setup_pip_install

    # Pick the right python (venv if bootstrap_pip created one, system otherwise)
    OV_PYTHON="python3"
    local ov_venv_detect="$INSTALL_DIR/.openclaw/venv"
    if [[ -f "$ov_venv_detect/bin/python3" ]]; then
        OV_PYTHON="$ov_venv_detect/bin/python3"
        pretty_print "Using venv python for OpenViking" "${fg_cyan}"
    fi

    install_openviking_pkg
    install_nodejs
    install_openclaw
    gather_identity
    deploy_workspace
    setup_vector_memory
    deploy_scripts
    deploy_auto_capture_hook
    bootstrap_openclaw
    # Auto-enable the auto-capture hook
    export OPENCLAW_STATE_DIR="$INSTALL_DIR/.openclaw"
    export OPENCLAW_DIR="$WORKSPACE_TARGET"
    if "$INSTALL_DIR/.local/bin/openclaw" hooks enable auto-capture-openviking 2>&1; then
        pretty_print "Auto-capture hook enabled"
    else
        pretty_print "Could not auto-enable hook — run manually: openclaw hooks enable auto-capture-openviking" "${fg_yellow}"
    fi
    init_health_state
    write_run_script
    cleanup_portable
    setup_home_symlinks

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
