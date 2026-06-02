#!/usr/bin/env bash
# start-searxng.sh — Start SearXNG private search engine
# Usage: ./start-searxng.sh
# Returns 0 if successfully started or already running.

SEARXNG_PORT=8888
SEARXNG_CONF_DIR="$HOME/.config/searxng"
SEARXNG_LOG="/tmp/searxng_web.log"

# Already running?
if curl -sf "http://127.0.0.1:$SEARXNG_PORT" >/dev/null 2>&1; then
  echo "SearXNG already running on http://127.0.0.1:$SEARXNG_PORT"
  exit 0
fi

# Check if installed
if [ ! -d "$HOME/searxng" ]; then
  echo "SearXNG not installed. Run setup.sh first."
  exit 1
fi

# Check config exists
if [ ! -f "$SEARXNG_CONF_DIR/settings.yml" ]; then
  echo "SearXNG config not found at $SEARXNG_CONF_DIR/settings.yml"
  exit 1
fi

# Kill stale processes
pkill -f "searx.webapp" 2>/dev/null || true
sleep 1

# Clear old log
rm -f "$SEARXNG_LOG" 2>/dev/null || true

# Start
export SEARXNG_SETTINGS_PATH="$SEARXNG_CONF_DIR/settings.yml"
nohup python3 -m searx.webapp > "$SEARXNG_LOG" 2>&1 &

# Wait for port (up to 15s)
for i in 1 2 3 4 5 6 7 8; do
  sleep 2
  if curl -sf "http://127.0.0.1:$SEARXNG_PORT" >/dev/null 2>&1; then
    echo "SearXNG running on http://127.0.0.1:$SEARXNG_PORT"
    exit 0
  fi
done

echo "SearXNG failed to start. Check $SEARXNG_LOG"
tail -5 "$SEARXNG_LOG" 2>/dev/null
exit 1
