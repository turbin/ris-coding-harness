// ris-coding-harness compact-recall extension for pi (badlogic/pi-mono).
// Install: copy to <project>/.pi/extensions/compact-recall.ts (project) or
// ~/.pi/agent/extensions/compact-recall.ts (global, no project trust needed).
//
// Bridges pi's extension events to the harness shell contract:
//   session_compact      -> scripts/compact-archive.py  (PostCompact archive)
//   before_agent_start   -> scripts/session-recall.py   (recall briefing)
// Fail-open: any error is logged and swallowed; pi's flow is never blocked.

import { spawnSync } from "node:child_process";
import * as path from "node:path";

const ARCHIVE = path.join(process.cwd(), "scripts", "compact-archive.py");
const RECALL = path.join(process.cwd(), "scripts", "session-recall.py");

function runScript(script: string, payload: Record<string, unknown>): string | null {
	for (const py of ["python", "python3", "py"]) {
		const r = spawnSync(py, [script], {
			input: JSON.stringify(payload),
			encoding: "utf-8",
			timeout: 15000,
			windowsHide: true,
		});
		if (r.error) {
			if ((r.error as NodeJS.ErrnoException).code === "ENOENT") continue; // try next interpreter
			console.error(`[compact-recall] ${py} ${script}: ${r.error.message}`);
			return null;
		}
		if (r.status !== 0) {
			console.error(`[compact-recall] ${script} exited ${r.status}: ${r.stderr || ""}`);
			return null;
		}
		return (r.stdout as string) || null;
	}
	console.error("[compact-recall] no python interpreter found");
	return null;
}

export default function (pi: any) {
	pi.on("session_compact", async (event: any, ctx: any) => {
		try {
			const entry = event?.compactionEntry ?? {};
			const sessionId =
				String(ctx?.sessionId ?? ctx?.session?.id ?? ctx?.sessionManager?.getSessionId?.() ?? "pi");
			runScript(ARCHIVE, {
				hook_event_name: "PostCompact",
				session_id: sessionId,
				session_title: "",
				cwd: process.cwd(),
				summary: entry.summary ?? "",
				source: event?.reason ?? "",
				pi_timestamp: entry.timestamp ?? null,
			});
		} catch (e) {
			console.error(`[compact-recall] session_compact failed: ${e}`);
		}
	});

	pi.on("before_agent_start", async (event: any, ctx: any) => {
		try {
			const sessionId = String(
				ctx?.sessionId ?? ctx?.session?.id ?? ctx?.sessionManager?.getSessionId?.() ?? "unknown",
			);
			const out = runScript(RECALL, {
				hook_event_name: "UserPromptSubmit",
				session_id: sessionId,
				cwd: process.cwd(),
			});
			const briefing = (out || "").trim();
			if (!briefing) return;
			return { message: { customType: "compact-recall", content: briefing, display: false } };
		} catch (e) {
			console.error(`[compact-recall] before_agent_start failed: ${e}`);
		}
	});
}
