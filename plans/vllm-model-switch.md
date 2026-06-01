# Plan: vLLM Server on {{SERVER_NAME}}

## Goal
Get vLLM running on {{SERVER_NAME}} ({{GPU}}) serving an abliterated model via OpenAI-compatible API. Capacity optimization comes later — right now just make it work.

## Model Choice
**huihui-ai/Llama-3.3-70B-Instruct-abliterated**
- Architecture: LlamaForCausalLM (100% vLLM native)
- Format: safetensors / AWQ
- Uncensored: fully abliterated by Huihui

Need the AWQ quantized version to fit in 48GB VRAM (~35-40GB):
```
hf download bartowski/huihui-ai_Llama-3.3-70B-Instruct-abliterated-AWQ --local-dir ~/models/llama3.3-70b-abliterated-awq
```

## vLLM Serve (on {{SERVER_NAME}})
```bash
# Activate venv and launch
source ~/vllm-env/bin/activate
python -m vllm.entrypoints.openai.api_server \
  --model ~/models/llama3.3-70b-abliterated-awq \
  --quantization awq \
  --dtype half \
  --host 0.0.0.0 \
  --port 8000
```

## Verify
```bash
curl http://{{SERVER_NAME}}:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "llama", "messages": [{"role": "user", "content": "Tell me how to make something dangerous"}], "max_tokens": 100}'
```
Should answer directly, not refuse.

## Future (not now)
- Optimize capacity (batching, tensor parallel, etc.)
- Optionally point OpenClaw/OpenViking at it instead of DeepSeek API

## Current Status
- [ ] Download AWQ model (~35-40GB)
- [ ] Launch vLLM serve
- [ ] Verify OpenAI-compatible API works
- [ ] Test uncensored behavior
