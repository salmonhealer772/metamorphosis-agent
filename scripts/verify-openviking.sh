#!/bin/bash
# OpenViking Verification Script — tests the REAL workspace, not a sandbox
# Run: bash verify-openviking.sh

# ── Derive workspace path, with smart detection ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Priority: 1) OPENCLAW_DIR env var, 2) sibling workspace/ dir,
#            3) script's own dir (if ov.py lives there),
#            4) parent dir, 5) fallback to HOME
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
if [ -n "${OPENCLAW_DIR:-}" ] && [ -f "$OPENCLAW_DIR/ov.py" ]; then
    WORKSPACE_DIR="$OPENCLAW_DIR"
elif [ -f "$PROJECT_ROOT/workspace/ov.py" ]; then
    WORKSPACE_DIR="$PROJECT_ROOT/workspace"
elif [ -f "$SCRIPT_DIR/ov.py" ]; then
    WORKSPACE_DIR="$SCRIPT_DIR"
elif [ -f "$PROJECT_ROOT/ov.py" ]; then
    WORKSPACE_DIR="$PROJECT_ROOT"
else
    WORKSPACE_DIR="$HOME/.openclaw/workspace"
fi

OV_DIR="${WORKSPACE_DIR}/.openviking"
OV_PY="${WORKSPACE_DIR}/ov.py"
# e2e script: same dir as this script, or fallback to workspace
if [ -f "$SCRIPT_DIR/verify-e2e.py" ]; then
    OV_E2E="$SCRIPT_DIR/verify-e2e.py"
else
    OV_E2E="${WORKSPACE_DIR}/verify-e2e.py"
fi

# Detect venv python for openviking operations (Bug: was using bare system python3)
OV_PYTHON="python3"
for _venv in "$(dirname "$PROJECT_ROOT")/.openclaw/venv/bin/python3" \
            "$PROJECT_ROOT/.openclaw/venv/bin/python3"; do
    if [[ -f "$_venv" ]] && "$_venv" -c "import openviking" 2>/dev/null; then
        OV_PYTHON="$_venv"
        break
    fi
done

PASS=0
FAIL=0

check() {
    local desc="$1"
    local cmd="$2"
    if eval "$cmd" 2>/dev/null; then
        echo "  ✅ $desc"
        ((PASS++))
    else
        echo "  ❌ $desc"
        ((FAIL++))
    fi
}

echo "=== OpenViking Verification (Real Workspace) ==="
echo "  Script dir: $SCRIPT_DIR"
echo "  Workspace:  $WORKSPACE_DIR"
echo ""

# ── Layer 1: Infrastructure ──
echo "[1] Infrastructure"
check "ollama process running" "ps aux | grep -q '[o]llama serve'"
check "ollama API responds"     "curl -sf http://127.0.0.1:11434/api/tags > /dev/null"
check "all-minilm model loaded" "curl -sf http://127.0.0.1:11434/api/tags | grep -q all-minilm"
check "embedding API works"     "curl -sf http://127.0.0.1:11434/v1/embeddings -d '{\"model\":\"all-minilm\",\"input\":[\"hello\"]}' | grep -q 'embedding'"

# ── Layer 2: Workspace files ──
echo -e "\n[2] Workspace Integrity"
# Check both project-local and HOME configs
if [ -f "$PROJECT_ROOT/.openviking/ov.conf" ]; then
    check "openviking config exists" "test -f '$PROJECT_ROOT/.openviking/ov.conf'"
elif [ -f "$WORKSPACE_DIR/../.openviking/ov.conf" ]; then
    check "openviking config exists" "test -f '$WORKSPACE_DIR/../.openviking/ov.conf'"
else
    check "openviking config exists" "test -f ~/.openviking/ov.conf"
fi
check "workspace dir exists" "test -d '$OV_DIR'"
check "ov.py script exists" "test -f '$OV_PY'"
check "openviking pip package" "$OV_PYTHON -c 'import openviking; v=openviking.__version__; assert len(v) > 0'"

# Detect OpenViking config file for CLI commands
OV_CONF="$WORKSPACE_DIR/../.openviking/ov.conf"
if [[ ! -f "$OV_CONF" ]]; then
    OV_CONF="$HOME/.openviking/ov.conf"
fi

# ── Layer 3: ov.py CLI checks ──
echo -e "\n[3] CLI Sanity"
check "ov.py status works"      "cd '$WORKSPACE_DIR' && OPENVIKING_CONFIG_FILE='$OV_CONF' $OV_PYTHON '$OV_PY' status 2>&1 | grep -q 'Semantic search: OK'"
check "ov.py ls returns items"  "cd '$WORKSPACE_DIR' && OPENVIKING_CONFIG_FILE='$OV_CONF' $OV_PYTHON '$OV_PY' ls 2>&1 | grep -qE '📁|📄'"
check "ov.py find returns hits" "cd '$WORKSPACE_DIR' && OPENVIKING_CONFIG_FILE='$OV_CONF' $OV_PYTHON '$OV_PY' find 'openviking memory' 2>&1 | grep -q 'Found'"

# ── Layer 4: E2E Store → Find → Delete ──
echo -e "\n[4] End-to-End (Real Workspace)"
MARKER="OV_VERIFY_$(date +%s)"
if [ -f "$OV_E2E" ] && OV_VERIFY_MARKER="$MARKER" OPENVIKING_CONFIG_FILE="$OV_CONF" $OV_PYTHON "$OV_E2E" 2>/dev/null; then
    echo "  ✅ store+find+delete cycle"
    ((PASS++))
else
    echo "  ❌ store+find+delete cycle"
    ((FAIL++))
fi

echo -e "\n=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo -e "\n🎉 All systems operational!"
else
    echo -e "\n⚠️  $FAIL check(s) failed"
    exit 1
fi
