# Plan: Install openviking pip package

**Difficulty:** 🟢 Easy — 1 line
**Code audit:** ✅ Clean. pip.pyz confirmed working. OpenViking pip package has ~40 deps, ~100MB.

## Target
`setup.sh` lines 98-101:
```bash
  # Ensure zstandard is available (no sudo — use pip.pyz to bootstrap)
  python3 -c "import zstandard" 2>/dev/null || {
    curl -sL https://bootstrap.pypa.io/pip/pip.pyz -o /tmp/pip.pyz 2>/dev/null
    python3 /tmp/pip.pyz install --user --break-system-packages zstandard -q 2>/dev/null
  }
```

## Fix
Add after line 100 (the zstandard pip install), inside the curly braces:
```bash
    python3 /tmp/pip.pyz install --user openviking -q 2>/dev/null
```

## Full block after fix
```bash
  python3 -c "import zstandard" 2>/dev/null || {
    curl -sL https://bootstrap.pypa.io/pip/pip.pyz -o /tmp/pip.pyz 2>/dev/null
    python3 /tmp/pip.pyz install --user --break-system-packages zstandard -q 2>/dev/null
    python3 /tmp/pip.pyz install --user openviking -q 2>/dev/null
  }
```

## Why inside the `||` block?
This ensures openviking is only installed if zstandard wasn't already available — meaning this is a fresh setup that will download pip.pyz anyway. If zstandard was already cached, pip.pyz was never downloaded and openviking might also already be there. A more reliable approach would be to add a separate `||` block for openviking, but for simplicity, nesting inside zstandard's block works.

## Test
Run `python3 -c "import openviking; print('ok')"` → no ModuleNotFoundError
