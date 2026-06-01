# LLM API Debug Monitor

## What This Does

Modifies the OpenAI SDK (`client.mjs` and `client.js`) to log every LLM API call to a file so you can inspect requests and responses in real time.

---

## Files Modified

| File | Format | Purpose |
|------|--------|---------|
| `/usr/lib/node_modules/openclaw/node_modules/openai/client.mjs` | ESM | OpenAI SDK main class (ESM entry) |
| `/usr/lib/node_modules/openclaw/node_modules/openai/client.js` | CJS | OpenAI SDK main class (CJS entry) |

Both need to be patched because Node.js may resolve to either one at runtime depending on how the module is imported.

---

## Location in Code

Inside the method `async fetchWithTimeout(url, init, ms, controller)` — the single choke point where every LLM API request is sent over the wire.

---

## Imports Added (top of file)

### `client.mjs` (ESM)

Add alongside existing imports at the top:

```js
import { appendFileSync } from 'node:fs';
import { exec } from 'node:child_process';
```

### `client.js` (CJS)

Add alongside existing `require()` statements at the top:

```js
const fs = require('fs');
const { exec } = require('child_process');
```

---

## Code Change

### Find this block (in both files)

```js
        try {
            // use undefined this binding; fetch errors if bound to something else in browser/cloudflare
            return await this.fetch.call(undefined, url, fetchOptions);
        }
        finally {
            clearTimeout(timeout);
        }
```

### Replace with this block (in both files)

```js
        try {
            // ===== FADE DEBUG: log outgoing request =====
            const FADE_LOG = '/tmp/{{USERNAME}}-llm-debug.log';
            const sep = '━'.repeat(35);
            const reqBody = typeof fetchOptions.body === 'string' ? fetchOptions.body : '(stream)';
            appendFileSync(FADE_LOG,
                `${sep}\n>>> ${fetchOptions.method} ${url}\n${reqBody}\n${sep}\n`);
            // =============================================

            // use undefined this binding; fetch errors if bound to something else in browser/cloudflare
            const response = await this.fetch.call(undefined, url, fetchOptions);

            // ===== FADE DEBUG: log incoming response =====
            const cloned = response.clone();
            const respBody = await cloned.text();
            appendFileSync(FADE_LOG,
                `<<< ${response.status} ${response.statusText}\n${respBody}\n${sep}\n\n`);
            // =============================================

            return response;
        }
        finally {
            clearTimeout(timeout);
        }
```

---

## How to View the Log

In a **second terminal**, run:

```bash
tail -f /tmp/{{USERNAME}}-llm-debug.log
```

New request/response data appears in real time as you use the assistant. No auto-launch — manual is simpler and more reliable.

---

## Log Format

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
>>> POST https://api.deepseek.com/v1/chat/completions
{"model":"deepseek-v4-flash","messages":[...],"stream":true,...}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
<<< 200 OK
{"id":"...","choices":[{"delta":{"content":"Hello!"}}],...}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Backup & Restore

Backups are stored in `C:\Users\{{YOUR_NAME}}\Documents\openclaw_playground\`:

| File | Contents |
|------|----------|
| `client.mjs.v0` | Factory original ESM |
| `client.js.v0` | Factory original CJS |
| `client.mjs.modified` | Patched ESM |
| `client.js.modified` | Patched CJS |

### Apply modified versions

```bash
sudo cp "/mnt/c/Users/{{YOUR_NAME}}/Documents/openclaw_playground/client.mjs.modified" /usr/lib/node_modules/openclaw/node_modules/openai/client.mjs
sudo cp "/mnt/c/Users/{{YOUR_NAME}}/Documents/openclaw_playground/client.js.modified" /usr/lib/node_modules/openclaw/node_modules/openai/client.js
```

### Restore factory originals

```bash
sudo cp "/mnt/c/Users/{{YOUR_NAME}}/Documents/openclaw_playground/client.mjs.v0" /usr/lib/node_modules/openclaw/node_modules/openai/client.mjs
sudo cp "/mnt/c/Users/{{YOUR_NAME}}/Documents/openclaw_playground/client.js.v0" /usr/lib/node_modules/openclaw/node_modules/openai/client.js
```

---

## Notes

- Modifies `node_modules` — will be overwritten on `npm install` / `npm update`
- Log file at `/tmp/{{USERNAME}}-llm-debug.log` — delete with `rm /tmp/{{USERNAME}}-llm-debug.log`
- Log is written even before the API call completes, so you'll see the request even if the network fails
