// ris-coding-harness compact-recall plugin for opencode.
// Install: copy to <project>/.opencode/plugins/compact-recall.ts (project) or
// ~/.config/opencode/plugins/compact-recall.ts (global).
//
// Bridges opencode plugin hooks to the harness shell contract:
//   session.compacted event -> scripts/compact-archive.py  (archive summary)
//   chat.message hook       -> scripts/session-recall.py   (recall briefing)
// Fail-open: any error is logged and swallowed; opencode's flow is never
// blocked. Requires python (python/python3/py) on PATH at runtime.

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
			if ((r.error as any).code === "ENOENT") continue;
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

async function fetchCompactionSummary(client: any, sessionID: string): Promise<{ summary: string; ts: number | null }> {
	try {
		const res = await client.session.messages({ path: { id: sessionID } });
		const list: any[] = res?.data ?? [];
		for (let i = list.length - 1; i >= 0; i--) {
			const m = list[i];
			if (m?.role === "assistant" && m.summary === true) {
				const text = (m.parts ?? [])
					.filter((p: any) => p?.type === "text")
					.map((p: any) => p?.text ?? "")
					.filter(Boolean)
					.join("\n");
				if (text.trim()) return { summary: text.trim(), ts: m.time?.created ?? null };
			}
		}
	} catch (e) {
		console.error(`[compact-recall] fetch summary failed: ${e}`);
	}
	return { summary: "", ts: null };
}

export const CompactRecallPlugin = async (input: any) => {
	return {
		event: async ({ event }: any) => {
			try {
				if (event?.type !== "session.compacted") return;
				const sessionID = event?.properties?.sessionID ?? "unknown";
				const { summary, ts } = await fetchCompactionSummary(input?.client, sessionID);
				runScript(ARCHIVE, {
					hook_event_name: "PostCompact",
					session_id: sessionID,
					session_title: "",
					cwd: process.cwd(),
					summary,
					timestamp: ts,
				});
			} catch (e) {
				console.error(`[compact-recall] session.compacted failed: ${e}`);
			}
		},
		"chat.message": async (input2: any, output: any) => {
			try {
				const out = runScript(RECALL, {
					hook_event_name: "UserPromptSubmit",
					session_id: input2?.sessionID ?? "unknown",
					cwd: process.cwd(),
				});
				const briefing = (out || "").trim();
				if (briefing && Array.isArray(output?.parts)) {
					output.parts.push({ type: "text", synthetic: true, text: briefing });
				}
			} catch (e) {
				console.error(`[compact-recall] chat.message failed: ${e}`);
			}
		},
	};
};

export default CompactRecallPlugin;
