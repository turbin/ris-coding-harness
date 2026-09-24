#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Golden tests for scripts/failure-event.py (M0 acceptance)."""
import json
import pathlib
import subprocess
import sys
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = REPO / "scripts" / "failure-event.py"


def run_cli(doc):
    proc = subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=json.dumps(doc),
        capture_output=True, text=True, encoding="utf-8", timeout=30,
    )
    assert proc.returncode == 0, f"exit={proc.returncode} stderr={proc.stderr}"
    return json.loads(proc.stdout)


def base_doc(**signal_overrides):
    signals = {
        "evaluator_verdict": None, "acceptance_evidence": None,
        "user_action": "none", "budget_exhausted": False,
        "verification_required": False, "verification_performed": True,
        "final_message": None, "runtime_error": "none",
        "fatal_error_origin": None, "flaky_retry_passed": False,
        "failure_category": None, "tool_identity": None,
        "error_signature": None, "scope": None, "path": None, "line": None,
    }
    signals.update(signal_overrides)
    return {
        "schema_version": "failure_event_input/v1",
        "run_id": "R1", "task_id": "T1", "attempt": 1, "terminal_sequence": 1,
        "mode": "interactive", "signals": signals,
    }


# Task 1 子集；Task 2 替换为全量 A1 表（见计划）。
GOLDEN_CASES = [
    ("all_acceptance_passed", {"acceptance_evidence": "passed"}, "success"),
    ("claimed_done_but_tests_failed",
     {"acceptance_evidence": "failed", "final_message": "complete_claim"},
     "task_failure"),
    ("agent_says_incomplete", {"final_message": "incomplete_claim"}, "task_failure"),
    ("user_cancelled", {"user_action": "cancel"}, "cancelled"),
    ("user_rejected_result", {"user_action": "rejection"}, "task_failure"),
    ("cancelled_after_requirement_change", {"user_action": "cancel"}, "cancelled"),
]


class CliContract(unittest.TestCase):
    def test_malformed_input_fails_open(self):
        proc = subprocess.run(
            [sys.executable, str(SCRIPT)],
            input="not-json", capture_output=True, text=True,
            encoding="utf-8", timeout=30,
        )
        self.assertEqual(proc.returncode, 0)
        out = json.loads(proc.stdout)
        self.assertFalse(out["ok"])
        self.assertIn("error", out)

    def test_unknown_enum_rejected(self):
        doc = base_doc()
        doc["signals"]["user_action"] = "self_destruct"
        proc = subprocess.run(
            [sys.executable, str(SCRIPT)],
            input=json.dumps(doc), capture_output=True, text=True,
            encoding="utf-8", timeout=30,
        )
        self.assertEqual(proc.returncode, 0)
        out = json.loads(proc.stdout)
        self.assertFalse(out["ok"])

    def test_output_has_ok_and_state(self):
        out = run_cli(base_doc())
        self.assertTrue(out["ok"])
        self.assertIn(out["terminal_state"],
                      {"success", "task_failure", "infra_failure",
                       "cancelled", "indeterminate"})


class GoldenClassification(unittest.TestCase):
    def test_golden_table(self):
        for name, overrides, expected in GOLDEN_CASES:
            with self.subTest(case=name):
                out = run_cli(base_doc(**overrides))
                self.assertTrue(out["ok"], out)
                self.assertEqual(out["terminal_state"], expected)


if __name__ == "__main__":
    unittest.main(verbosity=2)
