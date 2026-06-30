#!/usr/bin/env python3
"""E2E test for OpenViking real workspace: store → find → clean up."""
import sys
try:
    import openviking as ov
except ImportError:
    print("[e2e] OpenViking package not installed.", file=sys.stderr)
    sys.exit(1)

import tempfile, os, json, time, signal, re, subprocess

# Derive workspace dir: OPENCLAW_DIR env var > ~/.openclaw/workspace fallback
workspace_root = os.environ.get("OPENCLAW_DIR", os.path.expanduser("~/.openclaw/workspace"))
OV_DIR = os.path.join(workspace_root, ".openviking")
MARKER = os.environ.get("OV_VERIFY_MARKER", f"OV_VERIFY_{int(time.time())}")

# ── Timeout helper ──
class TimeoutError(Exception):
    pass

def timeout(seconds):
    """Decorator to timeout a function using SIGALRM."""
    def decorator(fn):
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

def kill_stale_lock(data_dir):
    """Clean up stale OpenViking process lock."""
    pid_path = os.path.join(data_dir, ".openviking.pid")
    if not os.path.isfile(pid_path):
        return False
    try:
        with open(pid_path) as f:
            pid_str = f.read().strip()
        pid = int(pid_str)
    except (ValueError, OSError):
        os.unlink(pid_path)
        return True
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        os.unlink(pid_path)
        return True
    except PermissionError:
        return False
    try:
        with open(f"/proc/{pid}/status") as f:
            if "State:\tZ" in f.read():
                os.kill(pid, 9)
                os.unlink(pid_path)
                return True
    except (FileNotFoundError, OSError):
        pass
    return False

@timeout(30)
def run_test():
    # Attempt to connect, handling stale locks
    client = None
    for attempt in range(3):
        try:
            client = ov.SyncOpenViking(path=OV_DIR)
            client.initialize()
            break
        except Exception as e:
            err = str(e)
            if "DataDirectoryLocked" in err or "Another OpenViking process" in err:
                m = re.search(r'PID (\d+)', err)
                if m:
                    stale_pid = int(m.group(1))
                    try:
                        os.kill(stale_pid, 0)
                        os.kill(stale_pid, 15)
                        time.sleep(0.5)
                        try:
                            os.kill(stale_pid, 0)
                            os.kill(stale_pid, 9)
                        except ProcessLookupError:
                            pass
                    except ProcessLookupError:
                        pass
                kill_stale_lock(OV_DIR)
                time.sleep(1)
                continue
            print(f"Connection error: {e}", file=sys.stderr)
            raise

    if client is None:
        print("Could not connect to OpenViking after retries", file=sys.stderr)
        sys.exit(1)

    # Store a test resource
    tf = tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False, dir='/tmp')
    tf.write(f"# Verification\nThis is a test resource for workspace verification.\nMarker: {MARKER}\nThe answer is 42.")
    tf.close()

    result = client.add_resource(path=tf.name)
    root_uri = result.get('root_uri', '')
    os.unlink(tf.name)

    # Wait and search
    found = False
    time.sleep(3)
    for retry in range(5):
        try:
            res = client.find(MARKER, limit=10)
        except Exception as e:
            print(f"find() error on retry {retry}: {e}", file=sys.stderr)
            time.sleep(2)
            continue
        for r in res.resources:
            try:
                content = client.read(r.uri)
                if MARKER in content and "42" in content:
                    found = True
                    break
            except Exception:
                continue
        if found:
            break
        time.sleep(2)

    # Cleanup: remove the directory root (recursive)
    if root_uri:
        try:
            client.rm(root_uri, recursive=True)
        except Exception as e:
            print(f"Cleanup warning: {e}", file=sys.stderr)

    try:
        client.close()
    except Exception:
        pass

    return found

try:
    found = run_test()
except TimeoutError:
    print("E2E test timed out (30s)", file=sys.stderr)
    found = False
except Exception as e:
    print(f"E2E test failed: {e}", file=sys.stderr)
    found = False

print(json.dumps({"found": found}))
sys.exit(0 if found else 1)
