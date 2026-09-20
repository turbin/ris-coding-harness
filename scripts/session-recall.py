#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""UserPromptSubmit-style hook for coding agents: inject a compact briefing
about the project's archived conversation summaries (conversations/) into the
context, once per session (and again whenever conversations/index.md changes).

Output formats:
  plain (default) - raw briefing text on stdout; understood natively by Kimi
                    Code (UserPromptSubmit) and Claude Code (UserPromptSubmit)
  codex           - JSON {"hookSpecificOutput": {...additionalContext}} as
                    required by Codex CLI command hooks

Usage (registered by scripts/install-agent-hooks.py, do not run by hand):
  hook payload JSON is read from stdin.

Fail-open by contract: every error path exits 0 with no output.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path

for _s in (sys.stdin, sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass

BRIEFING_HEAD = (
    "[对话归档简报] 本工程 conversations/ 下保存了各会话压缩时的上下文摘要档案"
    "（conversations/index.md 按时间倒序索引；时间越新的条目可信度越高，"
    "旧摘要引用前需与仓库当前状态核对）。"
)
BRIEFING_TAIL = (
    "当用户要求回顾 / 继续之前的工作时：先读 conversations/index.md 选定相关条目"
    "（可按 session id 关联），再读对应归档文件获取完整摘要；回答时注明摘要的"
    "时间与 session id。"
)
MAX_ROWS = 10


def log(msg):
    print(f"[session-recall] {msg}", file=sys.stderr)


def kimi_home():
    override = os.environ.get("KIMI_CODE_HOME")
    if override:
        return Path(override)
    return Path.home() / ".kimi-code"


def resolve_cwd(payload, session_id):
    """Same contract as compact-archive.resolve_cwd: payload cwd ->
    session_index.jsonl workDir; never os.getcwd() (hooks may run from a
    service context — issues/2026-09-20-hook-payload-cwd-fallback)."""
    raw = str(payload.get("cwd") or "").strip()
    if raw:
        p = Path(raw)
        if not p.is_absolute():
            log(f"ignoring non-absolute payload cwd: {raw}")
        elif p.is_dir():
            return p
        else:
            log(f"payload cwd is not a directory: {raw}")
    if session_id:
        index = kimi_home() / "session_index.jsonl"
        if index.is_file():
            workdir = ""
            try:
                with index.open("r", encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        if session_id not in line:
                            continue
                        try:
                            rec = json.loads(line)
                        except ValueError:
                            continue
                        if rec.get("sessionId") == session_id:
                            found = str(rec.get("workDir") or "").strip()
                            if found:
                                workdir = found
            except OSError:
                pass
            if workdir:
                d = Path(workdir)
                if not d.is_absolute():
                    d = kimi_home() / d
                if d.is_dir():
                    return d
                log(f"session_index workDir is not a directory: {workdir}")
    return None


def parse_rows(index_path):
    rows = []
    try:
        text = index_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return rows
    for line in text.splitlines():
        s = line.strip()
        if not s.startswith("|"):
            continue
        if re.match(r"^\|[\s:\-|]+\|$", s):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if len(cells) >= 3 and cells[0].lower() != "time":
            rows.append(cells[:3])
    rows.sort(key=lambda r: r[0], reverse=True)
    return rows


def build_briefing(rows):
    lines = [BRIEFING_HEAD, "", "| Time | File | Summary |", "|---|---|---|"]
    for r in rows[:MAX_ROWS]:
        lines.append(f"| {r[0]} | {r[1]} | {r[2]} |")
    if len(rows) > MAX_ROWS:
        lines.append("")
        lines.append(f"（共 {len(rows)} 条，其余见 conversations/index.md）")
    lines.append("")
    lines.append(BRIEFING_TAIL)
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--format", choices=("plain", "codex"), default="plain")
    args, _unknown = ap.parse_known_args()

    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except ValueError:
        payload = {}

    session_id = str(payload.get("session_id") or payload.get("sessionId") or "").strip() or "unknown"
    cwd = resolve_cwd(payload, session_id)
    if cwd is None:
        log("skip: cannot resolve project dir (no payload cwd, no session_index workDir)")
        return 0

    conv = cwd / "conversations"
    index_path = conv / "index.md"
    if not index_path.is_file():
        return 0

    try:
        mtime = index_path.stat().st_mtime_ns
    except OSError:
        return 0

    state_dir = conv / ".state"
    marker = state_dir / f"recall-{session_id}"
    try:
        if marker.is_file() and int(marker.read_text(encoding="utf-8").strip() or "0") >= mtime:
            return 0
    except (OSError, ValueError):
        pass

    rows = parse_rows(index_path)
    if not rows:
        return 0

    briefing = build_briefing(rows)
    if args.format == "codex":
        out = json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "UserPromptSubmit",
                    "additionalContext": briefing,
                }
            },
            ensure_ascii=False,
        )
    else:
        out = briefing

    # Only mark as injected after stdout went out successfully.
    try:
        sys.stdout.write(out + "\n")
        sys.stdout.flush()
        state_dir.mkdir(parents=True, exist_ok=True)
        marker.write_text(str(mtime), encoding="utf-8")
    except OSError as exc:
        log(f"cannot write marker: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
