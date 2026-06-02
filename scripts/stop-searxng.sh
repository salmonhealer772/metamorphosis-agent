#!/usr/bin/env bash
# stop-searxng.sh — Stop SearXNG private search engine
# Usage: ./stop-searxng.sh

pkill -f "searx.webapp" 2>/dev/null

# Verify it's gone
sleep 1
if pgrep -f "searx.webapp" >/dev/null 2>&1; then
  echo "Failed to stop SearXNG"
  exit 1
fi

echo "SearXNG stopped"
