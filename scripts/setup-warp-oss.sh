#!/usr/bin/env bash
# setup-warp-oss.sh — SSH into a server, download & build Warp OSS, ready to run
#
# Usage:
#   ./setup-warp-oss.sh user@server                         # full build
#   ./setup-warp-oss.sh user@server /custom/path             # custom work dir
#   ./setup-warp-oss.sh --logs user@server [/path]           # fetch build log
#   ./setup-warp-oss.sh --status user@server [/path]         # check build status
#   ./setup-warp-oss.sh --clean user@server [/path]          # delete Warp source
#
# What it does:
#   1. SSHes into the target machine — confirms connectivity + sudo
#   2. Installs Rust via rustup (if missing)
#   3. Installs system build deps (detects apt/dnf/pacman)
#   4. Clones warpdotdev/Warp (shallow — no history)
#   5. Launches build inside tmux (or nohup if tmux unavailable)
#   6. Reports where the binary lives and how to launch
#
# All build output is logged to: <work-dir>/Warp/build.log (on the remote)
#
# === CAVEATS ===
# - Warp is a GPU-accelerated GUI app. It needs a display server (X11/Wayland)
#   and GPU drivers on the target machine. Won't work on a headless VPS.
# - First build takes a LONG time (hours on modest hardware, 10+ GB disk).
# - The build runs in tmux/nohup — you can safely close this terminal.
# - sudo must be available (for package installs) without a password prompt,
#   OR the sudo session must already be warm. The -t flag allocates a TTY
#   but if sudo asks for a password and no one's there, it hangs.
#
# === ENVIRONMENT ===
#   WARP_BRANCH=master     branch to clone (default: master)
#   RUSTUP_TOOLCHAIN=stable rustup channel (default: stable)
# ====================================================================

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────
MODE="${1:-build}"           # build | logs | status | clean
# Determine if a flag was given — shift positional args accordingly
case "$MODE" in
  --logs|logs|--status|status|--clean|clean)
    SSH_TARGET="${2:-}"
    WORK_DIR="${3:-$HOME}"
    ;;
  *)
    SSH_TARGET="${1:-}"
    WORK_DIR="${2:-$HOME}"
    ;;
esac
WARP_BRANCH="${WARP_BRANCH:-master}"
RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-stable}"

# ── Help ─────────────────────────────────────────────────────────────
show_help() {
  cat <<'HELP'
Usage: setup-warp-oss.sh <mode> user@hostname [work-dir]

Modes:
  build              (default) Full setup: Rust → deps → clone → build
  --logs             Fetch build.log from remote to stdout
  --status           Check build status on remote
  --clean            Remove Warp source tree (keeps cargo registry)

Examples:
  setup-warp-oss.sh build user@myserver
  setup-warp-oss.sh user@myserver /opt/warp
  setup-warp-oss.sh --logs user@myserver
  setup-warp-oss.sh --status user@myserver

Env overrides:  WARP_BRANCH   RUSTUP_TOOLCHAIN
HELP
  exit 0
}

if [ -z "${2:-${1:-}}" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  show_help
fi

# ── SSH helper ──────────────────────────────────────────────────────
remote() {
  ssh "$SSH_TARGET" bash -s "$@"
}

remote_tty() {
  # Use -t flag only when we might need sudo prompts
  ssh -t "$SSH_TARGET" bash -s "$@"
}

# ── Flags mode ──────────────────────────────────────────────────────
case "$MODE" in
  --logs|logs)
    echo "==> Fetching build log from $SSH_TARGET..."
    echo "(file: $WORK_DIR/Warp/build.log)"
    echo "────────────────────────────────────────"
    remote << SCRIPT
      cat "$WORK_DIR/Warp/build.log" 2>/dev/null \
        || echo "[no build.log found]"
SCRIPT
    exit 0
    ;;
  --status|status)
    echo "==> Build status on $SSH_TARGET"
    echo ""
    remote << SCRIPT
      BIN="$WORK_DIR/Warp/target/release/warp"
      LOG="$WORK_DIR/Warp/build.log"
      DIR="$WORK_DIR/Warp"

      echo "  Repo exists:  \$(test -d \$DIR && echo yes || echo no)"
      echo "  Binary ready: \$(test -f \$BIN && echo yes || echo no)"
      if [ -f "\$BIN" ]; then
        echo "  Binary size:  \$(du -sh "\$BIN" | cut -f1)"
        echo "  Build date:   \$(stat -c '%y' "\$BIN" 2>/dev/null || stat -f '%Sm' "\$BIN" 2>/dev/null)"
      fi
      echo "  Log exists:   \$(test -f \$LOG && echo yes || echo no)"
      if [ -f \$LOG ]; then
        echo "  Log ends with: \$(tail -3 \$LOG)"
      fi
      echo ""
      echo "  Disk used by Warp: \$(du -sh \$DIR 2>/dev/null | cut -f1 || echo 'N/A')"
      echo "  Cargo/pkg cache:   \$(du -sh \$HOME/.cargo 2>/dev/null | cut -f1 || echo 'N/A')"
SCRIPT
    exit 0
    ;;
  --clean|clean)
    echo "==> Cleaning Warp source from $SSH_TARGET:$WORK_DIR/Warp"
    echo "    (cargo registry in ~/.cargo is kept — avoids re-downloading deps)"
    remote << SCRIPT
      if [ -d "$WORK_DIR/Warp" ]; then
        rm -rf "$WORK_DIR/Warp"
        echo "  ✓ Removed $WORK_DIR/Warp"
      else
        echo "  (nothing to clean)"
      fi
SCRIPT
    exit 0
    ;;
esac

# ====================================================================
#  MODE: BUILD
# ====================================================================

# ── Preflight: connectivity + sudo + disk ────────────────────────────
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Warp OSS — Remote Build & Setup                   ║"
echo "║   Target:  $SSH_TARGET"
echo "║   WorkDir: $WORK_DIR"
echo "║   Branch:  $WARP_BRANCH"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "==> [preflight] Checking connectivity + sudo..."
remote_tty << 'PREFLIGHT'
  set -euo pipefail
  echo "  ✓ connected to $(hostname)"

  # Check sudo
  if sudo -n true 2>/dev/null; then
    echo "  ✓ sudo available (passwordless)"
  else
    echo "  ! sudo requires a password. Attempting to get a warm session…"
    sudo -v
    echo "  ✓ sudo warmed up"
  fi

  # Check disk space (need ~15 GB free for the build)
  AVAIL_KB=$(df "$HOME" --output=avail 2>/dev/null | tail -1 || df -k "$HOME" | tail -1 | awk '{print $4}')
  if [ "$AVAIL_KB" -lt 15728640 ] 2>/dev/null; then
    echo "  ⚠  Low disk space: ~$(( AVAIL_KB / 1024 )) MB free on $HOME"
    echo "     Warp build needs ~15 GB. Consider a different WORK_DIR."
    echo "     Continuing anyway — may fail."
  else
    echo "  ✓ disk space OK (~$(( AVAIL_KB / 1024 )) MB free)"
  fi
PREFLIGHT

echo ""

# ── Step 1: Install Rust ─────────────────────────────────────────────
echo "==> [1/5] Installing Rust toolchain..."
remote_tty << 'REMOTE_RUST'
  set -euo pipefail
  if command -v cargo &>/dev/null; then
    echo "  ✓ Rust already installed ($(cargo --version))"
  else
    echo "  Installing rustup (stable, adds cargo to .profile)…"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable
    # Source it for the rest of this session
    set +u
    . "$HOME/.cargo/env"
    set -u
    echo "  ✓ Rust installed ($(cargo --version))"
  fi
REMOTE_RUST

echo ""

# ── Step 2: System build deps ────────────────────────────────────────
echo "==> [2/5] Installing system build dependencies..."
remote_tty << 'REMOTE_DEPS'
  set -euo pipefail

  # Work out package manager once
  PM=""
  INSTALL_CMD=""
  if command -v apt-get &>/dev/null; then
    PM=apt
    PKGS=(git curl build-essential pkg-config libssl-dev
          libx11-dev libxext-dev libxft-dev libxinerama-dev
          libxcursor-dev libxrandr-dev libxi-dev
          libgl1-mesa-dev libegl1-mesa-dev
          libwayland-dev wayland-protocols
          cmake ninja-build
          libasound2-dev libpulse-dev
          dbus-x11)
    INSTALL_CMD="sudo apt-get update -qq && sudo apt-get install -y -qq"
  elif command -v dnf &>/dev/null; then
    PM=dnf
    PKGS=(git curl pkg-config openssl-devel
          libX11-devel libXext-devel libXft-devel libXinerama-devel
          libXcursor-devel libXrandr-devel libXi-devel
          mesa-libGL-devel mesa-libEGL-devel
          wayland-devel wayland-protocols-devel
          cmake ninja-build
          alsa-lib-devel pulseaudio-libs-devel
          dbus-x11)
    INSTALL_CMD="sudo dnf groupinstall -y 'Development Tools' && sudo dnf install -y"
  elif command -v pacman &>/dev/null; then
    PM=pacman
    PKGS=(git curl base-devel pkg-config openssl
          libx11 libxext libxft libxinerama
          libxcursor libxrandr libxi
          mesa wayland wayland-protocols
          cmake ninja
          alsa-lib pulseaudio
          dbus)
    INSTALL_CMD="sudo pacman -Syu --noconfirm --needed"
  fi

  if [ -z "$PM" ]; then
    echo "  ⚠ Unknown package manager. Install these manually:"
    echo "     git curl pkg-config openssl-dev"
    echo "     X11/Wayland dev libs (libx11-dev, wayland-dev, etc.)"
    echo "     cmake ninja-build alsa pulseaudio"
    echo "  Proceeding — cargo build will fail if anything is missing."
  else
    echo "  Detected: $PM"
    eval "$INSTALL_CMD ${PKGS[*]}"
    echo "  ✓ Build dependencies installed"
  fi
REMOTE_DEPS

echo ""

# ── Step 3: Clone ────────────────────────────────────────────────────
echo "==> [3/5] Cloning warpdotdev/Warp (branch: $WARP_BRANCH)..."
remote << REMOTE_CLONE
  set -euo pipefail
  cd "$WORK_DIR"
  if [ -d "Warp/.git" ]; then
    echo "  ✓ Repo already exists, updating…"
    cd Warp
    git fetch origin --depth 1
    git checkout "$WARP_BRANCH" || {
      echo "  Branch '$WARP_BRANCH' not found — falling back to master"
      git checkout master
    }
    git pull --ff-only
  else
    git clone --depth 1 --branch "$WARP_BRANCH" \
      https://github.com/warpdotdev/Warp.git
    echo "  ✓ Cloned"
  fi
REMOTE_CLONE

echo ""

# ── Step 4: Build (async — survives disconnect) ─────────────────────
echo "==> [4/5] Launching build…"
echo "     Command: cargo build --release"
echo "     Log:     $WORK_DIR/Warp/build.log"
echo ""

remote_tty << REMOTE_BUILD
  set -euo pipefail
  cd "$WORK_DIR/Warp"

  # Source cargo in case rustup was just installed
  set +u
  [ -f "\$HOME/.cargo/env" ] && . "\$HOME/.cargo/env"
  set -u

  BUILD_CMD="cargo build --release 2>&1 | tee build.log; echo ''; echo '========== BUILD EXIT CODE: \$? ==========' >> build.log"

  if command -v tmux &>/dev/null; then
    # Tmux — safe to detach, build keeps going
    TMUX_SESSION="warp-build"

    # Don't create duplicate sessions
    if tmux has-session -t "\$TMUX_SESSION" 2>/dev/null; then
      echo "  ℹ  tmux session 'warp-build' already exists."
      echo "     Attach: ssh $SSH_TARGET -t tmux attach -t \$TMUX_SESSION"
      echo ""
      echo "     Kill and restart:"
      echo "       tmux kill-session -t \$TMUX_SESSION"
      echo "       then re-run this script."
    else
      tmux new-session -d -s "\$TMUX_SESSION" "\$BUILD_CMD"
      echo "  ✅ Build launched in tmux session 'warp-build'"
      echo "     This terminal can close safely."
      echo ""
      echo "  Commands:"
      echo "    Attach:   ssh $SSH_TARGET -t tmux attach -t \$TMUX_SESSION"
      echo "    Detach:   Ctrl+B then D"
      echo "    Tail log: ssh $SSH_TARGET tail -f $WORK_DIR/Warp/build.log"
      echo "    Fetch:    $0 --logs $SSH_TARGET"
    fi
  elif command -v nohup &>/dev/null; then
    # nohup fallback — not as good as tmux but survives disconnect
    nohup sh -c "\$BUILD_CMD" > /dev/null 2>&1 &
    echo "  ✅ Build launched via nohup (PID: \$!)"
    echo "     This terminal can close safely."
    echo ""
    echo "  Commands:"
    echo "    Tail log: ssh $SSH_TARGET tail -f $WORK_DIR/Warp/build.log"
    echo "    Fetch:    $0 --logs $SSH_TARGET"
  else
    # Nothing available — build inline (dangerous, but warn)
    echo "  ⚠  No tmux or nohup available."
    echo "     Build will run inline — KEEP THIS SSH SESSION OPEN."
    echo "     Install tmux next time: sudo apt install tmux"
    echo ""
    eval "\$BUILD_CMD"
  fi
REMOTE_BUILD

echo ""

# ── Step 5: Wait for build & return logs ────────────────────────────
echo "==> [5/5] Waiting for build to finish (polling every 30s)…"
echo "     Press Ctrl+C to stop waiting — build continues on remote."
echo ""

LOGPATH="$WORK_DIR/Warp/build.log"
BINPATH="$WORK_DIR/Warp/target/release/warp"

# Poll until the build finishes (exit code logged, or tmux gone + binary exists)
while true; do
  BUILD_DONE=$(ssh "$SSH_TARGET" "grep -q 'BUILD EXIT CODE:' \"$LOGPATH\" 2>/dev/null && echo yes || echo no" 2>/dev/null || echo no)
  TMUX_GONE=$(ssh "$SSH_TARGET" "! command -v tmux >/dev/null 2>&1 || ! tmux has-session -t warp-build 2>/dev/null; echo yes" 2>/dev/null || echo no)
  BINARY_EXISTS=$(ssh "$SSH_TARGET" "test -f \"$BINPATH\" && echo yes || echo no" 2>/dev/null || echo no)

  if [ "$BUILD_DONE" = "yes" ]; then
    echo "  ⏹  Build finished. Fetching log…"
    echo ""
    echo "══════════════════ BUILD LOG ══════════════════"
    ssh "$SSH_TARGET" "cat \"$LOGPATH\"" 2>/dev/null || echo "[could not read log]"
    echo "══════════════════ END LOG ═════════════════════"
    echo ""
    break
  elif [ "$TMUX_GONE" = "yes" ] && [ "$BINARY_EXISTS" = "yes" ]; then
    # Binary exists but no BUILD EXIT CODE line — log might have been cut
    echo "  ⏹  Build appears complete (tmux gone, binary exists). Fetching log…"
    echo ""
    echo "══════════════════ BUILD LOG ══════════════════"
    ssh "$SSH_TARGET" "cat \"$LOGPATH\"" 2>/dev/null || echo "[could not read log]"
    echo "══════════════════ END LOG ═════════════════════"
    echo ""
    break
  elif [ "$TMUX_GONE" = "yes" ] && [ "$BUILD_DONE" = "no" ]; then
    # tmux gone, no exit code logged — crashed or was killed
    echo "  ❌ tmux session gone and build didn't finish. Fetching partial log…"
    echo ""
    echo "══════════════ PARTIAL BUILD LOG ═══════════════"
    ssh "$SSH_TARGET" "cat \"$LOGPATH\"" 2>/dev/null || echo "[no log found]"
    echo "══════════════════ END LOG ═════════════════════"
    echo ""
    break
  else
    printf "  ."
    sleep 30
  fi
done

# ── Copy log to world-readable location for AI assistant ────────────
echo ""
echo "==> Copying build log to /tmp/warp-build.log for AI access..."
ssh "$SSH_TARGET" "cp \"$LOGPATH\" /tmp/warp-build.log 2>/dev/null; chmod 644 /tmp/warp-build.log 2>/dev/null; echo '  ✓ ready at /tmp/warp-build.log'" 2>/dev/null || echo "  (could not copy log)"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"

EXIT_CODE=$(ssh "$SSH_TARGET" "grep 'BUILD EXIT CODE:' \"$LOGPATH\" 2>/dev/null | tail -1 | grep -o '[0-9]*'" 2>/dev/null || echo "unknown")
BINARY_EXISTS=$(ssh "$SSH_TARGET" "test -f \"$BINPATH\" && echo yes || echo no" 2>/dev/null || echo no)

if [ "$EXIT_CODE" = "0" ] || [ "$BINARY_EXISTS" = "yes" ]; then
  echo "║  ✅ BUILD COMPLETE                                          ║"
  echo "║                                                              ║"
  echo "║  Binary: $WORK_DIR/Warp/target/release/warp"
  echo "║                                                              ║"
  echo "║  To launch (requires a display):                             ║"
  echo "║    ssh $SSH_TARGET -t '$WORK_DIR/Warp/target/release/warp'"
  echo "║                                                              ║"
  echo "║  Or:  ssh $SSH_TARGET -t 'cd $WORK_DIR/Warp && cargo run'   ║"
  echo "║                                                              ║"
  echo "║  Warp walks you through onboarding on first launch.          ║"
else
  echo "║  ❌ BUILD FAILED (exit $EXIT_CODE)                           ║"
  echo "║                                                              ║"
  echo "║  Full log is shown above. Scroll up.                         ║"
  echo "║  Fetch again:  $0 --logs $SSH_TARGET"
fi

echo "╚══════════════════════════════════════════════════════════════╝"
