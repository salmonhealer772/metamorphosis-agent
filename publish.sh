#!/usr/bin/env bash
# publish.sh — Push to salmonhealer772/metamorphosis-agent

echo "Get a classic PAT at: https://github.com/settings/tokens (scope: repo)"
read -srp "token: " T
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUSH_DIR="/tmp/push-metamorphosis-agent-$(date +%s)"
mkdir -p "$PUSH_DIR" || { echo "❌ Can't create $PUSH_DIR"; exit 1; }

# Copy repo files from the script's own directory
cd "$SCRIPT_DIR"
for f in * .gitignore; do
  [ -e "$f" ] && cp -r "$f" "$PUSH_DIR/" 2>/dev/null || true
done

cd "$PUSH_DIR"
rm -rf .git 2>/dev/null
git init -q 2>/dev/null
git add -A 2>/dev/null
git commit -q -m "Update" 2>/dev/null
git branch -m main 2>/dev/null

echo "Pushing..."
git push -f "https://oauth2:$T@github.com/salmonhealer772/metamorphosis-agent.git" main 2>&1
PUSH_OK=$?

rm -rf "$PUSH_DIR" 2>/dev/null

if [ $PUSH_OK -eq 0 ]; then
  echo ""
  echo "✅ https://github.com/salmonhealer772/metamorphosis-agent"
else
  echo "❌ Push failed. Your token might be wrong or expired."
fi
