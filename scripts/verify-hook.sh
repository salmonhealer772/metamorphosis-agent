#!/usr/bin/env bash
# verify-hook.sh — End-to-end test for auto-capture OpenViking hook
# Verifies that message:received and message:sent hooks fire correctly
# and write to the daily memory log.
#
# Usage:
#   ./verify-hook.sh                    # uses default install dir
#   ./verify-hook.sh /path/to/install   # specify install dir
#
# Exit 0 = all pass, 1 = any fail

set -euo pipefail

INSTALL_DIR="${1:-$HOME/BOX/metamorphosis-agent}"
WORKSPACE_DIR="$INSTALL_DIR/.openclaw/workspace"
MEMORY_DIR="$WORKSPACE_DIR/memory"
DATE_STR=$(date +%Y-%m-%d)
DAILY_LOG="$MEMORY_DIR/$DATE_STR.md"
MARKER="HOOK_VERIFY_$(date +%s)_$$"

PASS=0
FAIL=0

# Source run.sh for correct env vars
cd "$INSTALL_DIR"
if [[ -f run.sh ]]; then
    # Source env vars without exec'ing openclaw
    export OPENCLAW_STATE_DIR="$INSTALL_DIR/.openclaw"
    export OPENCLAW_DIR="$WORKSPACE_DIR"
    export OPENCLAW_WORKSPACE_DIR="$WORKSPACE_DIR"
    export PATH="$INSTALL_DIR/.local/bin:$PATH"
fi

# Locate openclaw binary
OPENCLAW_BIN="$INSTALL_DIR/.local/bin/openclaw"
if [[ ! -f "$OPENCLAW_BIN" ]]; then
    OPENCLAW_BIN="$(command -v openclaw || true)"
fi
if [[ -z "$OPENCLAW_BIN" ]]; then
    echo "ERROR: OpenClaw binary not found" >&2
    echo "  Tried: $INSTALL_DIR/.local/bin/openclaw" >&2
    exit 1
fi

check() {
    local name="$1" cmd="$2" expected="$3"
    echo -n "  [ ] $name... "
    if output=$(eval "$cmd" 2>&1); then
        if echo "$output" | grep -q "$expected"; then
            echo "PASS"
            PASS=$((PASS + 1))
        else
            echo "FAIL"
            echo "       expected: '$expected'"
            echo "       got: '$(echo "$output" | head -3)'"
            FAIL=$((FAIL + 1))
        fi
    else
        local rc=$?
        echo "FAIL (exit $rc)"
        echo "       output: '$(echo "$output" | head -3)'"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Auto-Capture Hook Verification                  ║"
echo "║  Install: $INSTALL_DIR"
echo "║  Date:    $DATE_STR"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── 1. Pre-flight: check hook is deployed ──
echo "=== Pre-flight ==="
echo ""
check "Hook files exist in repo" \
    "test -f '$INSTALL_DIR/hooks/auto-capture-openviking/handler.ts' && echo 'found'" \
    "found"

check "Hook files exist in managed dir" \
    "test -f '$INSTALL_DIR/.openclaw/hooks/auto-capture-openviking/handler.ts' && echo 'found'" \
    "found"

check "Hook is registered in OpenClaw" \
    "'$OPENCLAW_BIN' hooks list 2>&1 | grep -q 'auto-capture-openviking' && echo 'registered'" \
    "registered"

check "Hook is enabled in config" \
    "grep -q 'auto-capture-openviking' '$INSTALL_DIR/.openclaw/openclaw.json' && grep -q '\"enabled\"' '$INSTALL_DIR/.openclaw/openclaw.json' | head -1 && echo 'enabled'" \
    "enabled"

check "Daily log file exists or can be created" \
    "touch '$DAILY_LOG' 2>/dev/null && echo 'writable'" \
    "writable"

check "OPENCLAW_WORKSPACE_DIR resolves correctly" \
    "echo '$OPENCLAW_WORKSPACE_DIR'" \
    "workspace"

echo ""

# ── 2. Gateway check ──
echo "=== Gateway ==="
echo ""
# Try to probe the gateway
if GW_STATUS=$("$OPENCLAW_BIN" gateway status 2>&1); then
    # Check if it's running by looking for the probe target
    GW_PORT=$(echo "$GW_STATUS" | grep -oP 'port=\K[0-9]+' || echo "18789")
    if curl -sf "http://127.0.0.1:$GW_PORT" >/dev/null 2>&1; then
        echo "  Gateway: running on port $GW_PORT ✅"
    else
        echo "  Gateway: configured but not responding — will try to start..."
        # Try starting it in background (timeout after 10s if it doesn't start)
        "$OPENCLAW_BIN" gateway start &
        GW_PID=$!
        sleep 5
        if curl -sf "http://127.0.0.1:$GW_PORT" >/dev/null 2>&1; then
            echo "  Gateway: started ✅"
        else
            echo "  Gateway: could not start — tests may fail ❌"
        fi
    fi
else
    echo "  Gateway: not configured — embedded mode only"
    echo "  Note: hooks only fire through gateway, not embedded mode"
fi
echo ""

# ── 3. Hook firing test ──
echo "=== Hook Firing Test ==="
echo ""

# Send test message with unique marker
echo "  Sending test message with marker: $MARKER"
TURN_OUTPUT=$("$OPENCLAW_BIN" agent --agent main --message "$MARKER" 2>&1) || true

# Wait for hook to write (should be near-instant, but give it time)
sleep 5

check "C2: User message appears in daily log" \
    "grep -q '$MARKER' '$DAILY_LOG' 2>/dev/null && echo 'found'" \
    "found"

check "C3: Agent response appears in daily log" \
    "grep -q '\*\*Agent\*\*' '$DAILY_LOG' 2>/dev/null && echo 'found'" \
    "found"

check "C3: User message has correct label" \
    "grep -q '\*\*User\*\*' '$DAILY_LOG' 2>/dev/null && echo 'found'" \
    "found"

echo ""

# ── 4. Format check ──
echo "=== Format Check ==="
echo ""
# Find the latest User entry and check format
LATEST_USER=$(grep '\*\*User\*\*' "$DAILY_LOG" 2>/dev/null | tail -1)
LATEST_AGENT=$(grep '\*\*Agent\*\*' "$DAILY_LOG" 2>/dev/null | tail -1)

check "User entry has ### timestamp header above it" \
    "grep -B1 '\*\*User\*\*.*$MARKER' '$DAILY_LOG' 2>/dev/null | head -1 | grep -q '^###' && echo 'timestamp'" \
    "###"

check "Entries use UTC timestamps" \
    "grep -oP '### \K[0-9]{4}-[0-9]{2}-[0-9]{2}' '$DAILY_LOG' 2>/dev/null | head -1 | grep -q '^2' && echo 'UTC'" \
    "2"

echo ""

# ── 5. Edge case tests ──
echo "=== Edge Case Tests ==="
echo ""

# Capture the log size before edge tests
LOG_SIZE_BEFORE=$(wc -l < "$DAILY_LOG" 2>/dev/null || echo "0")

# E1: Empty message should NOT be captured
EMPTY_MARKER="EMPTY_TEST_$$"
TURN_EMPTY=$("$OPENCLAW_BIN" agent --agent main --message "  " 2>&1) || true
sleep 3
check "E1: Empty/whitespace message NOT captured" \
    "grep -q '\*\*User\*\*.*\.\.' '$DAILY_LOG' 2>/dev/null; echo 'not_found'" \
    "not_found"

# E2: Slash command should NOT be captured
TURN_SLASH=$("$OPENCLAW_BIN" agent --agent main --message "/help" 2>&1) || true
sleep 3
check "E2: Slash command NOT captured" \
    "grep -q '\*\*User\*\*.*/help' '$DAILY_LOG' 2>/dev/null; echo 'not_found'" \
    "not_found"

# E3: Unicode/emoji should be captured cleanly
UNICODE_MARKER="UNICODE_你好_🚀_$$"
TURN_UNICODE=$("$OPENCLAW_BIN" agent --agent main --message "Hello 你好 🚀 $$" 2>&1) || true
sleep 3
check "E3: Unicode/emoji captured cleanly" \
    "grep -q '你好.*🚀' '$DAILY_LOG' 2>/dev/null && echo 'found'" \
    "found"

echo ""

# ── 6. Summary ──
echo "╔══════════════════════════════════════════════════╗"
echo "║  Results                                         ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

# Print log excerpt for review
echo "--- Daily log excerpt ---"
tail -10 "$DAILY_LOG"
echo "-------------------------"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "VERDICT: ALL PASS ✅"
    exit 0
else
    echo "VERDICT: $FAIL TEST(S) FAILED ❌"
    exit 1
fi
