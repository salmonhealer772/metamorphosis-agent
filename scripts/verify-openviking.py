#!/usr/bin/env python3
"""Verify OpenViking is working correctly — run this anytime."""
import subprocess, json, sys, os, tempfile

PASS = 0
FAIL = 0

def check(desc, ok):
    global PASS, FAIL
    if ok:
        print(f"  ✅ {desc}")
        PASS += 1
    else:
        print(f"  ❌ {desc}")
        FAIL += 1

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).returncode == 0

print("=== OpenViking Verification ===\n")

print("[1] Ollama Server")
check("ollama process running", sh("ps aux | grep -q '[o]llama serve'"))
check("ollama API responds", sh("curl -sf http://127.0.0.1:11434/api/tags > /dev/null"))
check("all-minilm model loaded", sh("curl -sf http://127.0.0.1:11434/api/tags | grep -q all-minilm"))

print("\n[2] Embedding API")
check("v1/embeddings works", sh("""curl -sf http://127.0.0.1:11434/v1/embeddings -d '{"model":"all-minilm","input":["hello"]}' | grep -q 'embedding'"""))

print("\n[3] OpenViking Package")
check("config file exists", os.path.isfile(os.path.expanduser("~/.openviking/ov.conf")))
check("workspace exists", os.path.isdir(os.path.expanduser("~/.openclaw/workspace/.openviking")))
try:
    import openviking
    v = openviking.__version__
    check(f"openviking v{v} installed", True)
except:
    check("openviking imported", False)

print("\n[4] Knowledge Storage (E2E)")
try:
    import openviking as ov
    tf = tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False, dir='/tmp')
    tf.write("# Verification Doc\nThe answer is 42.")
    tf.close()

    client = ov.SyncOpenViking(path="/tmp/ov_e2e_check")
    client.initialize()
    client.add_resource(path=tf.name)
    client.wait_processed(timeout=30)

    results = client.find("answer to verification question", limit=3)
    found = any("42" in client.read(r.uri) for r in results.resources)
    client.close()
    os.unlink(tf.name)
    import shutil; shutil.rmtree("/tmp/ov_e2e_check", ignore_errors=True)

    check(f"stored & retrieved (found={found}, count={len(results.resources)})", found and len(results.resources) > 0)
except Exception as e:
    check(f"E2E failed: {e}", False)

print(f"\n=== Results: {PASS} passed, {FAIL} failed ===")
if FAIL == 0:
    print("🎉 All systems operational!")
    sys.exit(0)
else:
    print("⚠️  Some checks failed")
    sys.exit(1)
