#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""FailureEvent contract CLI for the failure-reflection loop (M0).

Reads one failure_event_input/v1 JSON document from stdin, prints a
failure_event/v1 JSON document to stdout. Fail-open by contract
(DEC-FR-014): every path exits 0.

Spec: decisions/2026-09-24-failure-reflection-loop.md
"""
import hashlib
import json
import re
import sys

for _s in (sys.stdin, sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass

TERMINAL_STATES = ("success", "task_failure", "infra_failure",
                   "cancelled", "indeterminate")
ENUMS = {
    "evaluator_verdict": ("pass", "fail"),
    "acceptance_evidence": ("passed", "failed"),
    "user_action": ("none", "cancel", "rejection"),
    "final_message": ("complete_claim", "incomplete_claim"),
    "runtime_error": ("none", "fatal"),
    "fatal_error_origin": ("external", "agent", "harness", "unknown"),
    "failure_category": (
        "requirement_misunderstanding", "planning_error", "reasoning_error",
        "implementation_error", "verification_gap", "tool_usage_error",
        "context_loss", "missing_knowledge", "environment", "premature_stop",
        "unknown",
    ),
}


def validate_signals(signals):
    for key, allowed in ENUMS.items():
        value = signals.get(key)
        if value is not None and value not in allowed:
            raise ValueError(f"invalid {key}: {value!r}")


def classify(signals):
    if signals.get("user_action") == "cancel":
        return "cancelled"
    if signals.get("user_action") == "rejection":
        return "task_failure"
    verdict = signals.get("evaluator_verdict")
    if verdict == "pass":
        return "success"
    if verdict == "fail":
        return "task_failure"
    evidence = signals.get("acceptance_evidence")
    if evidence == "passed":
        return "success"
    if evidence == "failed":
        return "task_failure"
    # Priorities 5–9 implemented here; full A1 golden table lands in Task 2.
    if signals.get("budget_exhausted"):
        return "task_failure"
    if signals.get("verification_required") and not signals.get("verification_performed"):
        return "task_failure"
    if signals.get("final_message") == "incomplete_claim":
        return "task_failure"
    if signals.get("runtime_error") == "fatal":
        return "task_failure" if signals.get("fatal_error_origin") == "agent" else "infra_failure"
    return "indeterminate"


def reflectability(state, signals):
    if state == "task_failure":
        controllable = not (
            signals.get("failure_category") == "environment"
            or signals.get("fatal_error_origin") in ("external", "harness")
        )
        return {"actionable": True, "recoverable": True,
                "agent_controllable": controllable}
    if state == "infra_failure":
        return {"actionable": False, "recoverable": False,
                "agent_controllable": False}
    return {"actionable": False, "recoverable": False,
            "agent_controllable": "unknown"}


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True)


def sha_hex(obj):
    return hashlib.sha256(canonical(obj).encode("utf-8")).hexdigest()


_TS_RE = re.compile(r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?"
                    r"(?:Z|[+-]\d{2}:?\d{2})?")
_UUID_RE = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
                      r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
_HOME_WIN_RE = re.compile(r"[A-Za-z]:[\\/]Users[\\/][^\\/]+")
_HOME_UNIX_RE = re.compile(r"(?:/home/|/Users/)[^\\/\s\"']+")
# TMP 必须先于 HOME 执行，否则 C:\Users\<n>\AppData... 的盘符前缀已被替换；
# 盘符段允许多级目录；Windows/Unix 两侧各吞一个后续段（对称，消除 run-a/run-b 差异）
_TMP_WIN_RE = re.compile(
    r"[A-Za-z]:[\\/](?:[^\\/\s\"']*[\\/])*AppData[\\/]Local[\\/]Temp[\\/]"
    r"(?:[^\\/\s\"']*[\\/])?")
_TMP_UNIX_RE = re.compile(r"/(?:tmp|var/tmp)/(?:[^\\/\s\"']*[\\/]*)?")


def strip_noise(text):
    if not text:
        return ""
    text = _TS_RE.sub("<TS>", text)
    text = _UUID_RE.sub("<UUID>", text)
    text = _TMP_WIN_RE.sub("<TMP>", text)
    text = _TMP_UNIX_RE.sub("<TMP>", text)
    text = _HOME_WIN_RE.sub("<HOME>", text)
    text = _HOME_UNIX_RE.sub("<HOME>", text)
    return text


def reflection_fingerprint(signals):
    return {"version": "rf/v1", "hash": sha_hex({
        "v": "rf/v1",
        "category": signals.get("failure_category") or "unknown",
        "tool": signals.get("tool_identity") or "",
        "signature": strip_noise(signals.get("error_signature") or ""),
        "scope": signals.get("scope") or "",
        "path": strip_noise(signals.get("path") or ""),
        "line": signals.get("line"),
    })}


_LINE_NO_RE = re.compile(r":\d+\b")
_WIN_PATH_RE = re.compile(r"[A-Za-z]:(?:\\|/)(?:[^\s\"']+(?:\\|/))*[^\s\"']+")
_UNIX_PATH_RE = re.compile(r"(?:^|(?<=\s))/[^\s\"']+")


def _basename(match):
    token = match.group(0)
    for sep in ("/", "\\"):
        token = token.split(sep)[-1] if sep in token else token
    return token


def normalize_recurrence(text):
    text = strip_noise(text or "")
    text = _LINE_NO_RE.sub(":<LINE>", text)
    text = _WIN_PATH_RE.sub(_basename, text)
    text = _UNIX_PATH_RE.sub(_basename, text)
    return text


def recurrence_signature(signals):
    return {"version": "rs/v1", "hash": sha_hex({
        "v": "rs/v1",
        "category": signals.get("failure_category") or "unknown",
        "scope": signals.get("scope") or "",
        "signature": normalize_recurrence(signals.get("error_signature") or ""),
    })}


def failure_event_id(doc):
    return "fe_" + sha_hex({
        "v": "fe/v1",
        "run_id": doc.get("run_id"),
        "task_id": doc.get("task_id"),
        "attempt": doc.get("attempt"),
        "terminal_sequence": doc.get("terminal_sequence"),
    })[:16]


def main():
    try:
        raw = sys.stdin.read()
        doc = json.loads(raw) if raw.strip() else {}
        signals = doc.get("signals") or {}
        validate_signals(signals)
        state = classify(signals)
        if state not in TERMINAL_STATES:
            raise ValueError(f"invalid state: {state}")
        out = {"ok": True, "terminal_state": state,
               "reflectability": reflectability(state, signals),
               "failure_event_id": failure_event_id(doc),
               "fingerprints": {"reflection": reflection_fingerprint(signals),
                                "recurrence": recurrence_signature(signals)}}
    except Exception as exc:  # fail-open
        out = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
    json.dump(out, sys.stdout, sort_keys=True, separators=(",", ":"),
              ensure_ascii=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
