/**
 * Auto-Capture Daily Log Hook
 *
 * Listens on message:preprocessed (fires in gateway AND embedded mode),
 * appends the user's message to memory/YYYY-MM-DD.md so the agent
 * has cross-session context on every startup.
 *
 * Only captures user messages. Agent responses are captured implicitly
 * because the agent reads today's daily log on startup per AGENTS.md.
 *
 * No external dependencies. Just Node.js built-ins.
 */

import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";

function getMemoryDir(): string {
  const workspace =
    process.env.OPENCLAW_WORKSPACE_DIR ||
    process.env.OPENCLAW_DIR ||
    path.join(os.homedir(), ".openclaw", "workspace");
  return path.join(workspace, "memory");
}

function getDateStr(): string {
  return new Date().toISOString().slice(0, 10);
}

function getTimestamp(): string {
  return new Date().toISOString().replace("T", " ").slice(0, 16);
}

function shouldCapture(event: any): boolean {
  const content = event.context?.bodyForAgent || event.context?.content;
  if (!content || typeof content !== "string") return false;
  if (content.trim().length < 2) return false;
  if (content.trim().startsWith("/")) return false;
  return true;
}

const handler = async (event: any) => {
  if (event.type !== "message" || event.action !== "preprocessed") return;
  if (!shouldCapture(event)) return;

  const content = (event.context?.bodyForAgent || event.context?.content || "").trim();
  const line = `### ${getTimestamp()}\n**User**: ${content}`;

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
      "[auto-capture] Write failed:",
      err instanceof Error ? err.message : String(err)
    );
  }
};

export default handler;
