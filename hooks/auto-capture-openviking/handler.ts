/**
 * Auto-Capture OpenViking Hook
 *
 * Listens on message:received and message:sent, stores every conversation
 * turn into BOTH the daily markdown log AND OpenViking's vector database.
 *
 * Writes are serialized through a promise chain to avoid RocksDB lock
 * conflicts from concurrent Python processes.
 */

import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { execFile } from "node:child_process";

// ── Serialized store queue ──────────────────────────────────────────────────
// OpenViking's RocksDB lock only allows one Python process at a time.
// This promise chain ensures stores run sequentially, never concurrently.
let storeQueue: Promise<void> = Promise.resolve();

// ── Path resolution helpers ─────────────────────────────────────────────────

function getWorkspaceDir(): string {
  return (
    process.env.OPENCLAW_WORKSPACE_DIR ||
    process.env.OPENCLAW_DIR ||
    path.join(os.homedir(), ".openclaw", "workspace")
  );
}

function getMemoryDir(): string {
  return path.join(getWorkspaceDir(), "memory");
}

function getInstallDir(): string {
  // workspace is at $INSTALL_DIR/.openclaw/workspace
  return path.resolve(getWorkspaceDir(), "..", "..");
}

function getOvPyPath(): string {
  // Primary: workspace/ov.py shipped with the repo
  const workspaceOv = path.join(getWorkspaceDir(), "ov.py");
  // Fallback: .local/bin/ov.py (symlinked by setup.sh)
  const localOv = path.join(getInstallDir(), ".local", "bin", "ov.py");
  try {
    require("fs").accessSync(workspaceOv);
    return workspaceOv;
  } catch {
    return localOv;
  }
}

function getPythonPath(): string {
  // Primary: venv python (setup.sh creates this)
  const venvPython = path.join(getInstallDir(), ".openclaw", "venv", "bin", "python3");
  try {
    require("fs").accessSync(venvPython);
    return venvPython;
  } catch {
    return "python3"; // fallback to system PATH
  }
}

/**
 * Build environment for the ov.py child process.
 * PYTHONPATH and OPENVIKING_CONFIG_FILE must be set so the Python process
 * can find the openviking package and its config.
 */
function buildOvEnv(): Record<string, string> {
  const installDir = getInstallDir();
  const pyLibs = path.join(installDir, ".openclaw", "py-libs");
  const ovConfig = path.join(installDir, ".openviking", "ov.conf");

  return {
    ...(process.env as Record<string, string>),
    PYTHONPATH: [pyLibs, process.env.PYTHONPATH || ""].filter(Boolean).join(":"),
    OPENVIKING_CONFIG_FILE: process.env.OPENVIKING_CONFIG_FILE || ovConfig,
  };
}

// ── Date/time helpers ───────────────────────────────────────────────────────

function getDateStr(): string {
  return new Date().toISOString().slice(0, 10);
}

function getTimestamp(): string {
  return new Date().toISOString().replace("T", " ").slice(0, 16);
}

// ── Content filter ──────────────────────────────────────────────────────────

function shouldCapture(event: any): boolean {
  const content = event.context?.content;
  if (!content || typeof content !== "string") return false;
  if (content.trim().length < 2) return false;
  if (content.trim().startsWith("/")) return false;
  return true;
}

// ── Daily markdown log writer ───────────────────────────────────────────────

async function writeDailyLog(line: string): Promise<void> {
  try {
    const memoryDir = getMemoryDir();
    await fs.mkdir(memoryDir, { recursive: true });
    await fs.appendFile(
      path.join(memoryDir, `${getDateStr()}.md`),
      line + "\n",
      "utf-8"
    );
  } catch (err) {
    console.error(
      "[auto-capture] Daily log write failed:",
      err instanceof Error ? err.message : String(err)
    );
  }
}

// ── Store health tracking ────────────────────────────────────────────────────
// Writes a health file after every successful vector store so the agent
// can check on startup whether memory storage is working.
// If the health file is stale (>5 min), something is broken.

let storeSuccessCount = 0;
let storeFailureCount = 0;

function getHealthFilePath(): string {
  return path.join(getWorkspaceDir(), ".openviking", ".store-health");
}

async function writeHealth(): Promise<void> {
  try {
    const health = {
      last_successful: new Date().toISOString(),
      total_stores: storeSuccessCount,
      total_failures: storeFailureCount,
      ok: true,
    };
    const healthDir = path.dirname(getHealthFilePath());
    await fs.mkdir(healthDir, { recursive: true });
    await fs.writeFile(getHealthFilePath(), JSON.stringify(health, null, 2), "utf-8");
  } catch {
    // Can't write health file — not critical, don't log
  }
}

// ── OpenViking vector store (serialized via promise chain) ──────────────────

/**
 * Store a single message into OpenViking's vector database.
 * This spawns `python3 ov.py store` and waits for completion.
 * Errors are logged but never thrown — the gateway is never blocked.
 */
function storeToOV(text: string): Promise<void> {
  return new Promise<void>((resolve) => {
    const py = getPythonPath();
    const ovPy = getOvPyPath();
    const env = buildOvEnv();

    const child = execFile(
      py,
      [ovPy, "store", text],
      { env, timeout: 15_000, maxBuffer: 1024 },
      (err, _stdout, stderr) => {
        if (err) {
          storeFailureCount++;
          console.error(
            `[auto-capture] Vector store FAILED (${storeFailureCount} failures):`,
            stderr?.trim?.()?.slice(0, 200) || err.message
          );
        } else {
          storeSuccessCount++;
          // Update health file so agent can check storage is working
          writeHealth();
        }
        resolve();
      }
    );
    child.on("error", (e) => {
      console.error(`[auto-capture] Vector store spawn error: ${e.message}`);
      resolve();
    });
  });
}

/**
 * Enqueue a vector store operation.
 * All stores run sequentially through a promise chain, preventing
 * concurrent RocksDB lock conflicts.
 */
function enqueueStore(text: string): void {
  storeQueue = storeQueue.then(() => storeToOV(text));
  // Catch so rejections in the chain don't bubble
  storeQueue.catch(() => {});
}

// ── Hook handler ────────────────────────────────────────────────────────────

const handler = async (event: any) => {
  if (event.type !== "message") return;

  const isReceived = event.action === "received";
  const isSent = event.action === "sent";
  if (!isReceived && !isSent) return;

  // Skip failed sends
  if (isSent && event.context?.success === false) return;
  if (!shouldCapture(event)) return;

  const content = event.context.content.trim();
  const label = isReceived ? "**User**" : "**Agent**";
  const ts = getTimestamp();
  const dailyLine = `### ${ts}\n${label}: ${content}`;

  // 1. Write to daily markdown log (human-readable, always works)
  writeDailyLog(dailyLine);

  // 2. Push into OpenViking vector DB (serialized, fire-and-forget)
  const storeText = `${label}: ${content}`;
  enqueueStore(storeText);
};

export default handler;
