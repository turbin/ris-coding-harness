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


# 全量 A1 判定表（23 案例）；后续任务不得删改其期望值。
GOLDEN_CASES = [
    # —— 验收 / verdict ——
    ("all_acceptance_passed", {"acceptance_evidence": "passed"}, "success"),
    ("claimed_done_but_tests_failed",
     {"acceptance_evidence": "failed", "final_message": "complete_claim"},
     "task_failure"),
    ("verdict_pass_beats_incomplete_claim",
     {"evaluator_verdict": "pass", "final_message": "incomplete_claim"},
     "success"),
    ("verdict_fail", {"evaluator_verdict": "fail"}, "task_failure"),
    # —— agent 表态 / 预算 / 验证 ——
    ("agent_says_incomplete", {"final_message": "incomplete_claim"}, "task_failure"),
    ("budget_exhausted", {"budget_exhausted": True}, "task_failure"),
    ("abandoned_after_retries",
     {"final_message": "incomplete_claim", "budget_exhausted": True},
     "task_failure"),
    ("no_evidence_complete_claim", {"final_message": "complete_claim"},
     "indeterminate"),
    ("stopped_without_required_verification",
     {"verification_required": True, "verification_performed": False,
      "final_message": "complete_claim"},
     "task_failure"),
    # —— 正常恢复路径（工具错误不降级）——
    ("transient_shell_error_then_recovered", {"acceptance_evidence": "passed"},
     "success"),
    ("exploratory_grep_failures",
     {"acceptance_evidence": "passed", "failure_category": "tool_usage_error"},
     "success"),
    ("build_broke_then_fixed", {"acceptance_evidence": "passed"}, "success"),
    ("flaky_test_passed_on_retry",
     {"acceptance_evidence": "passed", "flaky_retry_passed": True}, "success"),
    # —— 运行时致命错误（按 origin 分流）——
    ("external_outage",
     {"runtime_error": "fatal", "fatal_error_origin": "external"},
     "infra_failure"),
    ("hook_script_crash",
     {"runtime_error": "fatal", "fatal_error_origin": "harness"},
     "infra_failure"),
    ("unknown_origin_fatal",
     {"runtime_error": "fatal", "fatal_error_origin": "unknown"},
     "infra_failure"),
    ("agent_broke_environment",
     {"runtime_error": "fatal", "fatal_error_origin": "agent",
      "failure_category": "implementation_error"},
     "task_failure"),
    ("error_after_prior_success",
     {"acceptance_evidence": "passed", "runtime_error": "fatal",
      "fatal_error_origin": "external"},
     "success"),
    # —— 用户动作 ——
    ("user_cancelled", {"user_action": "cancel"}, "cancelled"),
    ("user_rejected_result", {"user_action": "rejection"}, "task_failure"),
    ("cancelled_after_requirement_change", {"user_action": "cancel"},
     "cancelled"),
    # —— 先例守卫 ——
    ("cancel_beats_failed_evidence",
     {"user_action": "cancel", "acceptance_evidence": "failed"}, "cancelled"),
    ("rejection_beats_pass_verdict",
     {"user_action": "rejection", "evaluator_verdict": "pass"}, "task_failure"),
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
