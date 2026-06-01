#!/usr/bin/env bash
# publish.sh — Push to salmonhealer772/metamorphosis-agent

echo "Get a classic PAT at: https://github.com/settings/tokens (scope: repo)"
read -srp "token: " T
echo ""

WORK="/tmp/push-$(date +%s)"
mkdir -p "$WORK" || { echo "❌ Can't create $WORK"; exit 1; }

# Copy repo files
cd /tmp/fade-agent-template
for f in * .gitignore; do
  [ -e "$f" ] && cp -r "$f" "$WORK/" 2>/dev/null || true
done

cd "$WORK"
rm -rf .git 2>/dev/null
git init -q 2>/dev/null
git add -A 2>/dev/null
git commit -q -m "Update" 2>/dev/null
git branch -m main 2>/dev/null

echo "Pushing..."
git push -f "https://oauth2:$T@github.com/salmonhealer772/metamorphosis-agent.git" main 2>&1
PUSH_OK=$?

rm -rf "$WORK" 2>/dev/null

if [ $PUSH_OK -eq 0 ]; then
  echo ""
  echo "✅ https://github.com/salmonhealer772/metamorphosis-agent"
else
  echo "❌ Push failed. Your token might be wrong or expired."
fi
