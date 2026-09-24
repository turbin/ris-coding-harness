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
               "failure_event_id": failure_event_id(doc)}
    except Exception as exc:  # fail-open
        out = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
    json.dump(out, sys.stdout, sort_keys=True, separators=(",", ":"),
              ensure_ascii=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
