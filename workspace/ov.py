#!/usr/bin/env python3
"""
OpenViking Memory Helper — Fade's long-term memory interface.

Usage:
    python3 ov.py find "what I'm looking for"
    python3 ov.py store "something to remember"
    python3 ov.py ls [path]
    python3 ov.py read <uri>
    python3 ov.py index <path>
    python3 ov.py repomap <directory>  -- Aider-style structural code map
    python3 ov.py status
"""

import os, sys, json, tempfile, asyncio, signal, re, fcntl, subprocess, glob

try:
    import openviking as ov
    import openviking.async_client as ov_ac
except ImportError:
    print("[ov] OpenViking package not installed.", file=sys.stderr)
    print("[ov] Install with: pip install openviking", file=sys.stderr)
    print("[ov] Or ensure py-libs/ is on PYTHONPATH.", file=sys.stderr)
    sys.exit(1)
from pathlib import Path
from functools import wraps

# Determine OpenViking data directory and workspace root, respecting all env vars
WORKSPACE = os.environ.get("OPENCLAW_DIR", os.path.expanduser("~/.openclaw/workspace"))
_ov_config_file = os.environ.get("OPENVIKING_CONFIG_FILE", "")

# Auto-discover ov.conf: if not set via env, search relative to this script
if not _ov_config_file or not os.path.isfile(_ov_config_file):
    _script_dir = os.path.dirname(os.path.abspath(__file__))
    _candidates = [
        os.path.join(_script_dir, "..", ".openviking", "ov.conf"),
        os.path.join(_script_dir, "..", "..", ".openviking", "ov.conf"),
        os.path.join(WORKSPACE, "..", ".openviking", "ov.conf"),
        os.path.join(os.path.expanduser("~/.openclaw/workspace"), "..", ".openviking", "ov.conf"),
    ]
    for _cand in _candidates:
        _norm = os.path.normpath(_cand)
        if os.path.isfile(_norm):
            _ov_config_file = _norm
            break

if _ov_config_file and os.path.isfile(_ov_config_file):
    os.environ["OPENVIKING_CONFIG_FILE"] = _ov_config_file
    try:
        with open(_ov_config_file) as _f:
            _cfg = json.load(_f)
        _ws = _cfg.get("storage", {}).get("workspace", "")
        if _ws:
            OV_DATA = os.path.abspath(os.path.expanduser(_ws))
        else:
            OV_DATA = os.path.join(WORKSPACE, ".openviking")
    except (json.JSONDecodeError, OSError):
        OV_DATA = os.path.join(WORKSPACE, ".openviking")
else:
    OV_DATA = os.path.join(WORKSPACE, ".openviking")

_client = None

# Maximum size (in bytes) for files indexed via add_resource().
# Files larger than this will be skipped with a warning instead of
# being sent to the embedding model and triggering context-length errors.
# all-minilm handles ~512 tokens (~2KB), nomic-embed-text handles ~8192 tokens (~32KB).
# We use 16KB as a safe middle ground that works for both.
MAX_INDEX_FILE_SIZE = 16 * 1024  # 16 KB


def _clean_rocksdb_lock(data_dir):
    """
    Scan for stale RocksDB LOCK files under data_dir and remove them if
    no live process holds the lock.

    This mirrors OpenViking's own clean_stale_rocksdb_locks() but runs on
    ALL platforms (including WSL2, where the built-in check is disabled).

    Returns: number of stale LOCK files removed.
    """
    removed = 0
    data_root = os.path.abspath(os.path.expanduser(data_dir))
    for pattern in ["**/store/LOCK", "**/LOCK"]:
        for lock_path in glob.glob(os.path.join(data_root, pattern), recursive=True):
            if not os.path.isfile(lock_path):
                continue
            # Probe the lock with a non-blocking POSIX lock
            try:
                with open(lock_path, "r+b") as lock_file:
                    try:
                        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except (BlockingIOError, OSError):
                        # Lock is held by a live process — leave it
                        continue
                    # We got the lock — release it and delete the file
                    try:
                        fcntl.lockf(lock_file.fileno(), fcntl.LOCK_UN)
                    except OSError:
                        pass
                os.unlink(lock_path)
                removed += 1
                print(f"[ov] removed stale RocksDB LOCK: {lock_path}", file=sys.stderr)
            except (PermissionError, OSError) as e:
                print(f"[ov] cannot clean LOCK {lock_path}: {e}", file=sys.stderr)
    if removed:
        print(f"[ov] cleaned {removed} stale RocksDB LOCK file(s)", file=sys.stderr)
    return removed


def reset_singleton():
    """Kill the stuck singleton so next get_client() starts fresh."""
    global _client
    _client = None
    try:
        asyncio.run(ov_ac.AsyncOpenViking.reset())
    except Exception:
        pass

def _kill_stale_lock(data_dir):
    """
    Check for a stale OpenViking lock and clean it up.
    Returns True if a stale lock was cleaned up, False otherwise.
    """
    pid_path = os.path.join(data_dir, ".openviking.pid")
    if not os.path.isfile(pid_path):
        return False

    try:
        with open(pid_path) as f:
            pid_str = f.read().strip()
        pid = int(pid_str)
    except (ValueError, OSError):
        # Corrupted pid file — remove it
        os.unlink(pid_path)
        return True

    # Check if the process is alive
    try:
        os.kill(pid, 0)  # Signal 0 = existence check only
    except ProcessLookupError:
        # Process doesn't exist — stale lock, safe to clean
        print(f"[ov] stale lock: PID {pid} dead; cleaning up", file=sys.stderr)
        os.unlink(pid_path)
        return True
    except PermissionError:
        # Process exists but owned by another user — can't touch
        return False

    # Process is alive — check if it's a zombie
    try:
        with open(f"/proc/{pid}/status") as f:
            status = f.read()
        if "State:\tZ" in status:
            print(f"[ov] stale lock: PID {pid} is ZOMBIE; killing", file=sys.stderr)
            try:
                os.kill(pid, 9)
                os.unlink(pid_path)
                return True
            except Exception:
                return False
    except (FileNotFoundError, OSError):
        pass

    return False

def get_client():
    global _client
    if _client is None:
        # Before any OpenViking init, preemptively clean stale RocksDB LOCK
        # files. OpenViking's own clean_stale_rocksdb_locks() only runs on
        # win32/containerized — WSL2 (where this runs) needs manual cleanup.
        _clean_rocksdb_lock(OV_DATA)

        try:
            _client = ov.SyncOpenViking(path=OV_DATA)
            _client.initialize()
        except Exception as e:
            err_str = str(e)
            print(f"[ov] init failed: trying auto-recovery...", file=sys.stderr)
            reset_singleton()

            # Detect various lock conflict scenarios
            recovery_needed = (
                "Another OpenViking process" in err_str or
                "DataDirectoryLocked" in err_str or
                "IO error" in err_str or
                "LOCK" in err_str or
                "Resource temporarily unavailable" in err_str
            )

            if recovery_needed:
                # Try parsing PID from error message
                m = re.search(r'PID (\d+)', err_str)
                if m:
                    stale_pid = int(m.group(1))
                    try:
                        os.kill(stale_pid, 0)  # Check if alive
                        print(f"[ov] another process (PID {stale_pid}) holds the lock; sending SIGTERM", file=sys.stderr)
                        os.kill(stale_pid, 15)  # SIGTERM
                        import time
                        time.sleep(0.5)
                        try:
                            os.kill(stale_pid, 0)
                            os.kill(stale_pid, 9)  # SIGKILL if graceful didn't work
                        except ProcessLookupError:
                            pass
                    except ProcessLookupError:
                        pass  # Already dead, lock might still be stale

                # Clean up pid file and rocksdb locks
                _kill_stale_lock(OV_DATA)
                _clean_rocksdb_lock(OV_DATA)

            # Retry once after cleanup
            try:
                _client = ov.SyncOpenViking(path=OV_DATA)
                _client.initialize()
            except Exception as e2:
                print(f"[ov] recovery failed: {e2}", file=sys.stderr)
                raise
    return _client

def close():
    global _client
    if _client:
        _client.close()
        _client = None

def with_timeout(seconds=15):
    """Decorator: time out a function with a signal alarm."""
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            if hasattr(signal, 'SIGALRM'):
                def handler(_sig, _frame):
                    raise TimeoutError(f"Timed out after {seconds}s")
                old = signal.signal(signal.SIGALRM, handler)
                signal.alarm(seconds)
                try:
                    return fn(*args, **kwargs)
                finally:
                    signal.alarm(0)
                    signal.signal(signal.SIGALRM, old)
            else:
                return fn(*args, **kwargs)
        return wrapper
    return decorator

def safe_call(fn, *args, _label="operation", **kwargs):
    """Wrap an OpenViking call with timeout + auto-reset on failure."""
    try:
        return fn(*args, **kwargs)
    except (TimeoutError, Exception) as e:
        print(f"[ov] {_label} failed: {e}; resetting client", file=sys.stderr)
        reset_singleton()
        return None

@with_timeout(20)
def cmd_find(args):
    query = " ".join(args)
    if not query:
        print("Usage: ov.py find <query>")
        return
    c = get_client()
    results = safe_call(c.find, query, limit=5, _label="find")
    if results is None:
        return
    print(f"Found {len(results.resources)} results for: {query}\n")
    for r in results.resources:
        score = r.score
        uri = r.uri
        abstract = r.abstract or "(no abstract)"
        print(f"  [{score:.3f}] {uri}")
        print(f"           {abstract[:120]}")
        print()

def cmd_store(args):
    if not args:
        print("Usage: ov.py store <text>")
        return
    text = " ".join(args)
    tf = tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False, dir='/tmp')
    tf.write(text)
    tf.close()
    c = get_client()
    result = c.add_resource(path=tf.name)
    uri = result.get('root_uri', '?')
    # Wait for embedding to process (non-critical — data persists either way)
    try:
        c.wait_processed(timeout=60)
    except Exception as e:
        print(f"Stored: {uri} (embedding pending: {e})", file=sys.stderr)
    else:
        print(f"Stored: {uri}")
    os.unlink(tf.name)

@with_timeout(15)
def cmd_ls(args):
    path = args[0] if args else "viking://resources"
    if not path.startswith("viking://"):
        path = f"viking://resources/{path}"
    c = get_client()
    items = safe_call(c.ls, path, _label="ls")
    if items is None:
        return
    for item in items:
        icon = '📁' if item['isDir'] else '📄'
        size = item.get('size', 0)
        size_str = f"{size}B" if size < 1024 else f"{size//1024}KB"
        print(f"  {icon} {item['name']}  ({size_str})")

def cmd_read(args):
    if not args:
        print("Usage: ov.py read <uri>")
        return
    c = get_client()
    content = c.read(args[0])
    print(content)

def cmd_index(args):
    path = args[0] if args else WORKSPACE

    # Warn about files exceeding MAX_INDEX_FILE_SIZE before indexing.
    # These files will be indexed structurally (L0/L1 summaries) but
    # their full content (L2) will fail embedding if it exceeds the
    # model's context window.
    oversized = []
    if os.path.isdir(path):
        for root, _dirs, files in os.walk(path):
            for fname in files:
                fpath = os.path.join(root, fname)
                try:
                    fsize = os.path.getsize(fpath)
                    if fsize > MAX_INDEX_FILE_SIZE:
                        oversized.append((fpath, fsize))
                except OSError:
                    pass
    elif os.path.isfile(path):
        try:
            fsize = os.path.getsize(path)
            if fsize > MAX_INDEX_FILE_SIZE:
                oversized.append((path, fsize))
        except OSError:
            pass

    if oversized:
        print(f"Warning: {len(oversized)} file(s) exceed {MAX_INDEX_FILE_SIZE//1024}KB embedding limit:")
        for fpath, fsize in oversized[:5]:
            print(f"  {fsize//1024}KB  {fpath}")
        if len(oversized) > 5:
            print(f"  ... and {len(oversized) - 5} more")
        print("These files will be indexed structurally but may not get full embeddings.")
        print()

    c = get_client()
    result = c.add_resource(path=path)
    fc = result.get("meta", {}).get("file_count", "?")
    uri = result.get("root_uri", "?")
    print(f"Indexing {fc} files from {path}")
    print(f"Root: {uri}")
    try:
        c.wait_processed(timeout=120)
    except Exception as e:
        print(f"Partial: {e}", file=sys.stderr)
    print("Done.")

@with_timeout(20)
def cmd_status(args):
    c = get_client()
    items = safe_call(c.ls, "viking://resources", _label="status.ls")
    total = 0
    dirs = 0
    if items:
        for item in items:
            if item['isDir']:
                dirs += 1
            elif not item['name'].startswith('.'):
                total += 1
    print("--- OpenViking Status ---")
    print(f"  Workspace: {OV_DATA}")
    print(f"  Top-level items: {len(items) if items else 0}")
    print(f"  Directories: {dirs}")
    r = safe_call(c.find, "openviking memory", limit=1, _label="status.find")
    if r is not None:
        print(f"  Semantic search: OK ({len(r.resources)} hits)")
    else:
        print(f"  Semantic search: ERROR")
    print(f"  Index file size limit: {MAX_INDEX_FILE_SIZE//1024} KB")

def cmd_repomap(args):
    """Generate structural code map using built-in tree-sitter."""
    if not args:
        print("Usage: ov.py repomap <directory> [map_tokens]")
        return
    
    target = os.path.abspath(args[0])
    map_tokens = int(args[1]) if len(args) > 1 else 4096
    
    _repomap_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts", "repomap")
    _repomap_script = os.path.normpath(_repomap_script)
    
    if os.path.isfile(_repomap_script):
        result = subprocess.run(
            [sys.executable, _repomap_script, target, str(map_tokens)],
            capture_output=True, text=True, timeout=60
        )
        print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
    else:
        print(f"repomap tool not found at {_repomap_script}")

commands = {
    "find": cmd_find,
    "store": cmd_store,
    "ls": cmd_ls,
    "read": cmd_read,
    "index": cmd_index,
    "status": cmd_status,
    "repomap": cmd_repomap,
}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)
    
    cmd = sys.argv[1]
    args = sys.argv[2:]
    
    if cmd in commands:
        commands[cmd](args)
    else:
        print(f"Unknown command: {cmd}")
        print(__doc__)
    
    close()
