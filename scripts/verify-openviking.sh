#!/bin/bash
# OpenViking Verification Script — tests the REAL workspace, not a sandbox
# Run: bash verify-openviking.sh

PASS=0
FAIL=0
OV_DIR="/home/fade/.openclaw/workspace/.openviking"
OV_PY="/home/fade/.openclaw/workspace/ov.py"

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
echo ""

# ── Layer 1: Infrastructure ──
echo "[1] Infrastructure"
check "ollama process running" "ps aux | grep -q '[o]llama serve'"
check "ollama API responds"     "curl -sf http://127.0.0.1:11434/api/tags > /dev/null"
check "all-minilm model loaded" "curl -sf http://127.0.0.1:11434/api/tags | grep -q all-minilm"
check "embedding API works"     "curl -sf http://127.0.0.1:11434/v1/embeddings -d '{\"model\":\"all-minilm\",\"input\":[\"hello\"]}' | grep -q 'embedding'"

# ── Layer 2: Real Workspace files ──
echo -e "\n[2] Workspace Integrity"
check "openviking config exists" "test -f ~/.openviking/ov.conf"
check "real workspace dir exists" "test -d '$OV_DIR'"
check "ov.py script exists" "test -f '$OV_PY'"
check "openviking pip package" "python3 -c 'import openviking; v=openviking.__version__; assert len(v) > 0'"

# ── Layer 3: ov.py CLI checks ──
echo -e "\n[3] CLI Sanity"
check "ov.py status works"      "cd /home/fade/.openclaw/workspace && python3 '$OV_PY' status 2>&1 | grep -q 'Semantic search: OK'"
check "ov.py ls returns items"  "cd /home/fade/.openclaw/workspace && python3 '$OV_PY' ls 2>&1 | grep -qE '📁|📄'"
check "ov.py find returns hits" "cd /home/fade/.openclaw/workspace && python3 '$OV_PY' find 'openviking memory' 2>&1 | grep -q 'Found'"

# ── Layer 4: E2E Store → Find → Delete on real workspace ──
echo -e "\n[4] End-to-End (Real Workspace)"
MARKER="OV_VERIFY_$(date +%s)"
if OV_VERIFY_MARKER="$MARKER" python3 /home/fade/.openclaw/workspace/verify-e2e.py 2>/dev/null; then
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
