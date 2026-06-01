# Plan: Copy plans/ to ~/plans/

**Difficulty:** 🟢 Trivial — 3 lines
**Code audit:** ✅ Clean

## Target
`setup.sh` lines 198-204:
```bash
# ── Copy scripts ──────────────────────────────────────────────────
mkdir -p "$HOME/scripts"
cp -r "$REPO_DIR/scripts/"* "$HOME/scripts/" 2>/dev/null || true
chmod +x "$HOME/scripts/"*.sh 2>/dev/null || true
cd "$START_DIR" 2>/dev/null || true
```

## Fix
Add after the scripts block (after line 201):
```bash
mkdir -p "$HOME/plans"
cp -r "$REPO_DIR/plans/"* "$HOME/plans/" 2>/dev/null || true
```

## Test
Run setup → `ls ~/plans/` contains .md files
