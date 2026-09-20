#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PostCompact hook for coding agents: archive the compaction summary of the
current session into <cwd>/conversations/ and maintain conversations/index.md.

Supported agent flavors (auto-detected from the hook payload):
  kimi    payload session_id -> summary extracted from the session wire.jsonl
          (context.apply_compaction); payload summary fields win when present
  claude  PostCompact payload carries compact_summary + transcript_path
  codex   PostCompact payload carries transcript_path; the summary is the
          last {"type":"compacted"} line's payload.message in the rollout
  pi / opencode are adapted via TypeScript shims that feed this same contract

Usage (registered by scripts/install-agent-hooks.py, do not run by hand):
  hook payload JSON is read from stdin; optional --flavor forces a flavor.

Fail-open by contract: every error path exits 0 so a hook failure never
blocks compaction or the conversation. Agent session data is READ-ONLY here.
"""
import argparse
import datetime
import json
import os
import re
import sys
import tempfile
from pathlib import Path

for _s in (sys.stdin, sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass

INDEX_HEADER = """# Index

Use this file as a lightweight navigation surface. Keep entries concise and point to the detailed artifact instead of duplicating it.

| Time | File | Summary |
|---|---|---|
"""

MAX_INDEX_ROWS = 200
GIST_LEN = 80


def log(msg):
    print(f"[compact-archive] {msg}", file=sys.stderr)


def fail_open(reason):
    log(f"skip: {reason}")
    return 0


def kimi_home():
    override = os.environ.get("KIMI_CODE_HOME")
    if override:
        return Path(override)
    return Path.home() / ".kimi-code"


def resolve_cwd(payload, session_id):
    """Resolve the project directory without trusting os.getcwd(): hook
    payloads may lack cwd (observed on kimi 2026-09, contradicting the docs)
    and the CLI may spawn hooks from a service context (e.g. System32).
    Chain: payload cwd -> session_index.jsonl workDir. None = unresolvable."""
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


def find_wire(home, session_id):
    """Resolve the session's main-agent wire.jsonl. Primary source is
    session_index.jsonl; fall back to a directory glob."""
    index = home / "session_index.jsonl"
    if index.is_file():
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
                        d = Path(rec.get("sessionDir", ""))
                        if not d.is_absolute():
                            d = home / d
                        wire = d / "agents" / "main" / "wire.jsonl"
                        if wire.is_file():
                            return wire
        except OSError:
            pass
    matches = sorted(home.glob(f"sessions/*/{session_id}/agents/main/wire.jsonl"))
    return matches[-1] if matches else None


def extract_compaction(wire):
    """Scan a Kimi wire.jsonl once (substring pre-filter, then JSON parse) and
    keep the LAST context.apply_compaction summary plus the nearest preceding
    full_compaction.begin source/time."""
    summary = None
    summary_line = 0
    source = ""
    begin_time = None
    line_no = 0
    try:
        with wire.open("r", encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                line_no += 1
                if '"context.apply_compaction"' in raw:
                    try:
                        rec = json.loads(raw)
                    except ValueError:
                        continue
                    if rec.get("type") == "context.apply_compaction":
                        text = (rec.get("summary") or "").strip()
                        if text:
                            summary = text
                            summary_line = line_no
                elif '"full_compaction.begin"' in raw:
                    try:
                        rec = json.loads(raw)
                    except ValueError:
                        continue
                    if rec.get("type") == "full_compaction.begin":
                        source = rec.get("source") or source
                        begin_time = rec.get("time") or begin_time
    except OSError as exc:
        log(f"cannot read {wire}: {exc}")
        return None
    if summary is None:
        return None
    return {
        "summary": summary,
        "summary_line": summary_line,
        "source": source,
        "time": begin_time,
    }


def extract_title(wire):
    """Fallback session title when the payload lacks one: first line of the
    session state.json lastPrompt, whitespace-collapsed, capped at 100 chars."""
    state = wire.parent.parent.parent / "state.json"
    try:
        data = json.loads(state.read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError):
        return ""
    curated = str(data.get("title") or "").strip()
    if curated:
        return re.sub(r"\s+", " ", curated)[:100]
    first = str(data.get("lastPrompt") or "").strip().splitlines()
    if not first or not first[0].strip():
        return ""
    return re.sub(r"\s+", " ", first[0].strip())[:100]


def _claude_content_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content or []:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text") or "")
            elif isinstance(block, str):
                parts.append(block)
        return "\n".join(p for p in parts if p)
    return ""


def extract_from_transcript(path, flavor):
    """Pull the LAST compaction summary out of a claude/codex transcript.

    claude: {"isCompactSummary": true} user record; message.content holds text
    codex : {"type": "compacted"} line; payload.message holds text, line
            timestamp (RFC3339) is the compaction time.
    Returns {"summary", "time"} or None."""
    want_claude = flavor in ("auto", "claude")
    want_codex = flavor in ("auto", "codex")
    found = None
    try:
        with Path(path).open("r", encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                if want_codex and '"compacted"' in raw:
                    try:
                        rec = json.loads(raw)
                    except ValueError:
                        continue
                    if rec.get("type") == "compacted":
                        msg = (rec.get("payload") or {}).get("message") or ""
                        if msg.strip():
                            found = {"summary": msg.strip(), "time": rec.get("timestamp")}
                elif want_claude and "isCompactSummary" in raw:
                    try:
                        rec = json.loads(raw)
                    except ValueError:
                        continue
                    if rec.get("isCompactSummary"):
                        text = _claude_content_text((rec.get("message") or {}).get("content"))
                        if text.strip():
                            found = {"summary": text.strip(), "time": rec.get("timestamp")}
    except OSError as exc:
        log(f"cannot read transcript {path}: {exc}")
        return None
    return found


def parse_time(value):
    """Accept epoch ms (int/str) or ISO-8601; return normalized UTC ISO."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return iso_from_epoch_ms(value)
    s = str(value).strip()
    if not s:
        return None
    if s.isdigit():
        return iso_from_epoch_ms(int(s))
    try:
        dt = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return dt.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_from_epoch_ms(ms):
    try:
        dt = datetime.datetime.fromtimestamp(int(ms) / 1000, tz=datetime.timezone.utc)
    except (OverflowError, OSError, ValueError):
        return None
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def now_iso():
    return datetime.datetime.now(tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def make_gist(summary):
    first = ""
    for line in summary.splitlines():
        if line.strip():
            first = line.strip()
            break
    first = re.sub(r"\s+", " ", first)
    return first[:GIST_LEN] + ("…" if len(first) > GIST_LEN else "")


def update_index(index_path, time_iso, rel_file, gist):
    """Insert one row into the index table, keep it sorted newest-first,
    dedup on (time, file), cap at MAX_INDEX_ROWS."""
    if index_path.is_file():
        text = index_path.read_text(encoding="utf-8", errors="replace")
    else:
        text = INDEX_HEADER
    rows = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("|") and not re.match(r"^\|[\s:\-|]+\|$", s):
            cells = [c.strip() for c in s.strip("|").split("|")]
            if len(cells) >= 3 and cells[0].lower() != "time":
                rows.append(cells[:3])
    key = (time_iso, rel_file)
    if any((r[0], r[1]) == key for r in rows):
        return False
    rows.append(list(key) + [gist])
    rows.sort(key=lambda r: r[0], reverse=True)
    rows = rows[:MAX_INDEX_ROWS]
    body = "\n".join(f"| {r[0]} | {r[1]} | {r[2]} |" for r in rows)
    index_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(index_path.parent), prefix=".index-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(INDEX_HEADER)
            if body:
                out.write(body + "\n")
        os.replace(tmp, index_path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    return True


def first_present(mapping, keys):
    for k in keys:
        v = mapping.get(k)
        if v is not None and str(v).strip():
            return str(v).strip()
    return ""


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--flavor", choices=("auto", "kimi", "claude", "codex"), default="auto")
    args, _unknown = ap.parse_known_args()

    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except ValueError:
        payload = {}

    session_id = first_present(payload, ("session_id", "sessionId"))
    cwd = resolve_cwd(payload, session_id)
    if cwd is None:
        return fail_open(
            "cannot resolve project dir (no payload cwd, no session_index "
            "workDir); refusing os.getcwd() fallback"
        )
    title = first_present(payload, ("session_title", "sessionTitle"))
    summary = first_present(
        payload, ("summary", "compaction_summary", "compact_summary")
    )
    source = first_present(payload, ("source", "trigger", "reason"))
    time_iso = parse_time(first_present(payload, ("compact_time", "timestamp", "pi_timestamp")))

    wire_ref = ""
    if not summary:
        transcript = payload.get("transcript_path")
        if transcript:
            info = extract_from_transcript(transcript, args.flavor)
            if info:
                summary = info["summary"]
                if not time_iso:
                    time_iso = parse_time(info["time"])
        if not summary and session_id and args.flavor in ("auto", "kimi"):
            wire = find_wire(kimi_home(), session_id)
            if wire:
                if not title:
                    title = extract_title(wire)
                info = extract_compaction(wire)
                if info:
                    summary = info["summary"]
                    wire_ref = f"agents/main/wire.jsonl line {info['summary_line']}"
                    if not source:
                        source = info["source"]
                    if not time_iso:
                        time_iso = iso_from_epoch_ms(info["time"]) if info.get("time") else None
    if not summary:
        return fail_open("no compaction summary in payload, transcript, or wire.jsonl")
    if not time_iso:
        time_iso = now_iso()

    conv = cwd / "conversations"
    session_dir = conv / "archive" / (session_id or "unknown")
    try:
        session_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return fail_open(f"cannot mkdir {session_dir}: {exc}")

    fname = re.sub(r"[^0-9A-Za-z]", "-", time_iso)
    archive_path = session_dir / f"{fname}.md"
    front = [
        "---",
        f"session_id: {session_id or 'unknown'}",
        f"session_title: {title}",
        f"cwd: {cwd}",
        f"compact_time: {time_iso}",
        f"source: {source or 'unknown'}",
    ]
    if wire_ref:
        front.append(f"wire: {wire_ref}")
    elif payload.get("transcript_path"):
        front.append(f"transcript: {payload['transcript_path']}")
    front.append("---")
    content = "\n".join(front) + "\n\n" + summary.rstrip() + "\n"
    try:
        if not archive_path.exists():
            archive_path.write_text(content, encoding="utf-8")
    except OSError as exc:
        return fail_open(f"cannot write {archive_path}: {exc}")

    rel = archive_path.relative_to(conv).as_posix()
    changed = update_index(conv / "index.md", time_iso, rel, make_gist(summary))
    try:
        state_dir = conv / ".state"
        state_dir.mkdir(parents=True, exist_ok=True)
        receipt = {
            "archived_at": now_iso(),
            "compact_time": time_iso,
            "session": session_id or "unknown",
            "file": f"conversations/{rel}",
        }
        with (state_dir / "archive-log.jsonl").open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(receipt, ensure_ascii=False) + "\n")
    except OSError as exc:
        log(f"cannot append archive receipt: {exc}")
    log(f"archived -> conversations/{rel} (index {'updated' if changed else 'unchanged'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
