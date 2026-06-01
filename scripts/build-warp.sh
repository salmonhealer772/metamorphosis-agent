#!/usr/bin/env bash
# build-warp.sh — Build Warp OSS locally. No SSH. No tmux required.
#
# Usage:  ./build-warp.sh
# Logs:   ~/Warp/build.log
#         /tmp/warp-build.log (world-readable, for AI)

set -euo pipefail

LOGDIR="$HOME/Warp"
BIN="$LOGDIR/target/release/warp"
LOG="$LOGDIR/build.log"
SHARED_LOG="/tmp/warp-build.log"

# Copy whatever log exists on any exit (even Ctrl+C / crash)
exit_hook() {
  [ -f "$LOG" ] && cp "$LOG" "$SHARED_LOG" 2>/dev/null && chmod 644 "$SHARED_LOG" 2>/dev/null
}
trap exit_hook EXIT

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Warp OSS — Local Build                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Install Rust (if missing) ──────────────────────────────
if command -v cargo &>/dev/null; then
  echo "  ✓ Rust:     $(cargo --version)"
else
  echo "  → Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain stable
  . "$HOME/.cargo/env"
  echo "  ✓ Rust:     $(cargo --version)"
fi

# ── Step 2: Install build deps (needs sudo, will prompt) ──────────
echo "  → Installing build dependencies (sudo needed)..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
  git curl build-essential pkg-config libssl-dev \
  libx11-dev libxext-dev libxft-dev libxinerama-dev \
  libxcursor-dev libxrandr-dev libxi-dev \
  libgl1-mesa-dev libegl1-mesa-dev \
  libwayland-dev wayland-protocols \
  cmake ninja-build \
  libasound2-dev libpulse-dev \
  dbus-x11
echo "  ✓ Dependencies installed"

# ── Step 3: Clone Warp ──────────────────────────────────────────────
echo "  → Cloning warpdotdev/Warp..."
mkdir -p "$LOGDIR"
if [ -d "$LOGDIR/.git" ]; then
  echo "  ✓ Repo exists, pulling latest..."
  cd "$LOGDIR"
  git pull --ff-only
else
  git clone --depth 1 https://github.com/warpdotdev/Warp.git "$LOGDIR"
  echo "  ✓ Cloned"
fi

# ── Step 4: Build ───────────────────────────────────────────────────
echo "  → Building (cargo build --release)..."
echo "    Log: $LOG"
echo ""

cd "$LOGDIR"
cargo build --release 2>&1 | tee "$LOG"
EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ] && [ -f "$BIN" ]; then
  echo "  ✅ BUILD COMPLETE"
  echo "  Binary: $BIN"
  echo "  Run:    $BIN"
else
  echo "  ❌ BUILD FAILED (exit $EXIT_CODE)"
  echo "  Log: $LOG"
fi
echo "  AI log: $SHARED_LOG"
