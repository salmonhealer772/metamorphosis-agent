/**
 * Auto-Capture OpenViking Hook
 *
 * Listens on message:received and message:sent, appends conversation turns
 * to the agent's daily memory log (memory/YYYY-MM-DD.md) so OpenViking's
 * indexer can pick them up for cross-session recall.
 *
 * No agent involvement required. No external dependencies beyond Node.js
 * built-ins (fs, path, os).
 */

import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";

/**
 * Resolve the agent's memory/ directory.
 * Uses OPENCLAW_WORKSPACE_DIR env var if set, falls back to default path.
 */
function getMemoryDir(): string {
  const workspace =
    process.env.OPENCLAW_WORKSPACE_DIR ||
    path.join(os.homedir(), ".openclaw", "workspace");
  return path.join(workspace, "memory");
}

/**
 * Today's date as YYYY-MM-DD (UTC).
 */
function getDateStr(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Compact UTC timestamp for the log entry heading.
 * Example: "2026-07-07 11:04"
 */
function getTimestamp(): string {
  return new Date().toISOString().replace("T", " ").slice(0, 16);
}

/**
 * Filter out messages that aren't worth storing:
 * - Empty or whitespace-only content
 * - Slash-commands (/new, /reset, etc.)
 * - Messages under 2 characters (noise)
 * - Non-string content (objects, numbers, etc.)
 */
function shouldCapture(event: any): boolean {
  const content = event.context?.content;
  if (!content || typeof content !== "string") return false;
  if (content.trim().length < 2) return false;
  if (content.trim().startsWith("/")) return false;
  return true;
}

/**
 * Append a line to today's daily memory log.
 * Creates the directory and file if they don't exist.
 * Logs errors via console.error so they appear in gateway logs.
 */
async function appendToDailyLog(line: string): Promise<void> {
  try {
    const memoryDir = getMemoryDir();
    await fs.mkdir(memoryDir, { recursive: true });
    const dailyPath = path.join(memoryDir, `${getDateStr()}.md`);
    await fs.appendFile(dailyPath, line + "\n", "utf-8");
  } catch (err) {
    console.error(
      "[auto-capture-openviking] Failed to write to daily log:",
      err instanceof Error ? err.message : String(err)
    );
  }
}

/**
 * Hook handler registered for message:received and message:sent.
 */
const handler = async (event: any) => {
  // Only handle message events
  if (event.type !== "message") return;

  const isReceived = event.action === "received";
  const isSent = event.action === "sent";
  if (!isReceived && !isSent) return;

  // Skip failed sends
  if (isSent && event.context?.success === false) return;

  if (!shouldCapture(event)) return;

  const content = event.context.content.trim();
  const label = isReceived ? "**User**" : "**Agent**";
  const timestamp = getTimestamp();
  const line = `### ${timestamp}\n${label}: ${content}`;

  await appendToDailyLog(line);
};

export default handler;
