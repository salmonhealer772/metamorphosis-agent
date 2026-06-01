# 🚀 Server Setup — RTX A6000 + Huihui-Qwen3.5-27B

**Server:** `{{SERVER_NAME}}`
**GPU:** NVIDIA RTX A6000 (48GB VRAM)
**Model:** Huihui-Qwen3.5-27B-abliterated (Q8_0 quant, ~27GB)
**Backend:** Ollama (vLLM had architecture compat issue — see notes)

---

## 🔌 Quick Start (from fresh SSH)

```bash
# 1. SSH in
ssh who@{{SERVER_NAME}}

# 2. Launch the model
ollama run huihui_ai/qwen3.5-abliterated:27b
```

That's it. You're chatting. Type `/bye` to exit.

---

## 🧠 What You've Got

| Item | Status |
|---|---|
| Ollama installed | ✅ |
| Qwen3.5-27B-abliterated pulled | ✅ |
| vLLM + venv (`~/vllm-env`) | ✅ installed (model loading failed) |
| GGUF file downloaded (~27GB) | ✅ `./Huihui-Qwen3.5-27B-abliterated.Q8_0.gguf` |

### Why vLLM didn't work
The GGUF file has architecture tag `qwen35` which the `transformers` library hasn't learned yet. Ollama uses `llama.cpp` under the hood which reads GGUF at the C level and doesn't care about the tag — works fine.

---

## 🧰 Useful Commands

### Run interactively
```bash
ollama run huihui_ai/qwen3.5-abliterated:27b
```

### One-shot prompt (no chat mode)
```bash
ollama run huihui_ai/qwen3.5-abliterated:27b "What is the capital of France?"
```

### Check the model is loaded
```bash
ollama ps
```

### List available models
```bash
ollama list
```

### Use from API (OpenAI-compatible — for apps/scripts)
```bash
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "huihui_ai/qwen3.5-abliterated:27b",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

---

## 📊 Server Health

```bash
# GPU status
nvidia-smi

# Disk space
df -h

# Memory free
free -h

# CPU load
top
```

---

## 💾 The 27GB GGUF File (still there)

If vLLM ever adds Qwen3.5 support, you can use it:

```bash
source ~/vllm-env/bin/activate
vllm serve ./Huihui-Qwen3.5-27B-abliterated.Q8_0.gguf \
  --load-format gguf \
  --dtype auto \
  --max-model-len 32768 \
  --gpu-memory-utilization 0.95
```

---

## 🔮 Next Ideas

- **Matcha** — TUI email client with AI rewrite (point it at Ollama)
- **OpenWebUI** — web UI for chatting with the model
- **AutoRAG** — automated RAG pipeline optimization
- **Obsidian vault** — keep notes as markdown files, same format as this doc

---

## 🐛 Troubleshooting

**Model says "not found":**
```bash
ollama pull huihui_ai/qwen3.5-abliterated:27b
```

**Ollama not running:**
```bash
ollama serve
```

**Out of VRAM / OOM:**
Kill existing model first: `ollama stop huihui_ai/qwen3.5-abliterated:27b`
Then restart with lower context: `ollama run huihui_ai/qwen3.5-abliterated:27b --num-ctx 4096`
