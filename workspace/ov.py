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

import openviking as ov
import openviking.async_client as ov_ac
import os, sys, json, tempfile, asyncio, signal
from pathlib import Path
from functools import wraps

WORKSPACE = os.environ.get("OPENCLAW_DIR", os.path.expanduser("~/.openclaw/workspace"))
OV_DATA = os.path.join(WORKSPACE, ".openviking")

_client = None

def reset_singleton():
    """Kill the stuck singleton so next get_client() starts fresh."""
    global _client
    _client = None
    try:
        asyncio.run(ov_ac.AsyncOpenViking.reset())
    except Exception:
        pass

def get_client():
    global _client
    if _client is None:
        try:
            _client = ov.SyncOpenViking(path=OV_DATA)
            _client.initialize()
        except Exception as e:
            print(f"[ov] init failed: {e}; resetting singleton", file=sys.stderr)
            reset_singleton()
            _client = ov.SyncOpenViking(path=OV_DATA)
            _client.initialize()
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
    c = get_client()
    result = c.add_resource(path=path)
    fc = result.get("meta", {}).get("file_count", "?")
    uri = result.get("root_uri", "?")
    print(f"Indexing {fc} files from {path}")
    print(f"Root: {uri}")
    c.wait_processed(timeout=60)
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

def cmd_repomap(args):
    """Generate Aider-style structural code map."""
    if not args:
        print("Usage: ov.py repomap <directory> [map_tokens]")
        return
    
    target = os.path.abspath(args[0])
    map_tokens = int(args[1]) if len(args) > 1 else 4096
    
    if not os.path.isdir(target):
        print(f"Directory not found: {target}")
        return
    
    try:
        from aider.repomap import RepoMap
        from aider.io import InputOutput
        from aider.models import Model
    except ImportError:
        print("Aider not installed. Run: pip install --break-system-packages aider-chat")
        return
    
    # Find git root for proper path resolution
    git_root = None
    check = target
    while check and check != '/':
        if os.path.isdir(os.path.join(check, '.git')):
            git_root = check
            break
        check = os.path.dirname(check)
    
    effective_root = git_root or target
    exts = {'.py', '.ts', '.js', '.tsx', '.jsx', '.go', '.rs', '.java', '.c', '.cpp', '.h', '.hpp', '.rb', '.php', '.swift', '.kt', '.scala', '.cs'}
    all_files = []
    
    for root, dirs, files in os.walk(target):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ('node_modules', 'venv', '__pycache__', '.git', 'target', 'build', 'dist')]
        for f in files:
            if any(f.endswith(e) for e in exts):
                rel = os.path.relpath(os.path.join(root, f), effective_root)
                all_files.append(rel)
    
    if not all_files:
        print("No recognized code files found")
        return
    
    all_files = sorted(all_files)
    print(f"Scanning {len(all_files)} code files at {effective_root} (git={'yes' if git_root else 'no'})", flush=True)
    
    orig_cwd = os.getcwd()
    os.chdir(effective_root)
    
    rm = RepoMap(root=effective_root, map_tokens=map_tokens, main_model=Model("deepseek/deepseek-chat"), io=InputOutput())
    mid = min(len(all_files) // 2, 80)
    rmap = rm.get_repo_map(chat_files=all_files[:mid], other_files=all_files[mid:mid+80], force_refresh=True)
    os.chdir(orig_cwd)
    
    if rmap and rmap.strip():
        print(f"\n{'='*60}", flush=True)
        print(f"REPO MAP: {target}")
        print(f"{'='*60}\n", flush=True)
        print(rmap, flush=True)
    else:
        print("No generated map")

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
