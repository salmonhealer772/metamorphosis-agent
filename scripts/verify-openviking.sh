#!/bin/bash
# OpenViking Verification Script
# Run: bash verify-openviking.sh
PASS=0
FAIL=0

check() {
    local desc="$1"
    local cmd="$2"
    if eval "$cmd" 2>/dev/null; then
        echo "  ✅ $desc"
        ((PASS++))
    else
        echo "  ❌ $desc"
        ((FAIL++))
    fi
}

echo "=== OpenViking Verification ==="
echo ""

echo "[1] Ollama Server"
check "ollama process running" "ps aux | grep -q '[o]llama serve'"
check "ollama API responds" "curl -sf http://127.0.0.1:11434/api/tags > /dev/null"
check "all-minilm model loaded" "curl -sf http://127.0.0.1:11434/api/tags | grep -q all-minilm"

echo -e "\n[2] Embedding API"
check "v1/embeddings endpoint works" "curl -sf http://127.0.0.1:11434/v1/embeddings -d '{\"model\":\"all-minilm\",\"input\":[\"hello\"]}' | grep -q 'embedding'"

echo -e "\n[3] OpenViking Config"
check "config file exists" "test -f ~/.openviking/ov.conf"
check "workspace dir exists" "test -d $HOME/.openclaw/workspace/.openviking"
check "openviking pip package" "python3 -c 'import openviking; print(openviking.__version__)' > /dev/null"

echo -e "\n[4] Knowledge Storage (E2E)"
E2E_JSON=$(python3 2>/dev/null << 'PYEOF'
import openviking as ov, tempfile, os, json

tf = tempfile.NamedTemporaryFile(mode='w', suffix='.md', delete=False, dir='/tmp')
tf.write("# Verification Doc\nThe answer to the verification question is 42.")
tf.close()

client = ov.SyncOpenViking(path="/tmp/ov_verify")
client.initialize()
client.add_resource(path=tf.name)
client.wait_processed(timeout=30)

results = client.find("verification question answer", limit=3)
found = any("42" in client.read(r.uri) for r in results.resources)
client.close()
os.unlink(tf.name)
import shutil; shutil.rmtree("/tmp/ov_verify", ignore_errors=True)
print(json.dumps({"found": found, "count": len(results.resources)}))
PYEOF
)

check "store and retrieve knowledge" "echo '$E2E_JSON' | grep -q '\"found\": true'"
check "semantic search returns results" "echo '$E2E_JSON' | python3 -c 'import sys,json; d=json.load(sys.stdin); assert d[\"count\"] > 0'"

echo -e "\n=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo -e "\n🎉 All systems operational!"
else
    echo -e "\n⚠️  Some checks failed"
fi
