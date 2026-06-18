#!/usr/bin/env python3
"""E2E test for OpenViking real workspace: store → find → clean up."""
import openviking as ov
import tempfile, os, json, time, sys, shutil

OV_DIR = os.environ.get("OPENCLAW_DIR", os.path.expanduser("~/.openclaw/workspace")) + "/.openviking"
MARKER = os.environ.get("OV_VERIFY_MARKER", f"OV_VERIFY_{int(time.time())}")

client = ov.SyncOpenViking(path=OV_DIR)
client.initialize()

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
    res = client.find(MARKER, limit=10)
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

client.close()

print(json.dumps({"found": found}))
sys.exit(0 if found else 1)
