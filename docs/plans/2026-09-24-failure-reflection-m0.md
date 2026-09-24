# Failure Reflection M0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付判败契约 CLI `scripts/failure-event.py`：五态分类器 + reflectability + 三级身份（failure_event_id / reflection_fingerprint rf/v1 / recurrence_signature rs/v1），以 golden tests 全量编码 A1 判定表与成对指纹规则。

**Architecture:** 单文件 Python CLI（stdin JSON → stdout JSON，恒 exit 0 fail-open），无第三方依赖；测试为独立 unittest 脚本，经 subprocess 走真实 CLI 契约；shell smoke 包装对齐仓库既有 `tests/*.sh` 验收入口。哈希基于 canonical JSON（sort_keys、紧凑分隔符、ensure_ascii），保证确定性。

**Tech Stack:** Python 3.11 stdlib（json / hashlib / re / unittest / subprocess）；Bash smoke wrapper；Git Bash（Windows）。

**Spec:** `decisions/2026-09-24-failure-reflection-loop.md`（五态、权威链、三级身份、A1 场景表；A1 完整场景以本计划 Task 2 的 GOLDEN_CASES 为全量规格——spec 已声明 M0 golden tests 即完整规格）。

## Global Constraints

- 仅 Python 标准库，不新增任何第三方依赖。
- CLI 恒 `exit 0`（fail-open，DEC-FR-014）；输入不合法时 stdout 输出 `{"ok": false, "error": "..."}`。
- 输出与哈希确定性：canonical JSON = `json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=True)`。
- 五态闭集：`success` / `task_failure` / `infra_failure` / `cancelled` / `indeterminate`（DEC-FR-001）。
- 指纹版本字符串固定：`fe/v1`（id 内嵌）、`rf/v1`、`rs/v1`（DEC-FINGERPRINT）。
- 文件命名跟随仓库：`scripts/failure-event.py`（hyphen，同 `compact-archive.py`）、`tests/test-failure-event.py`、`tests/failure-event-smoke.sh`。
- 测试运行器：`python3`（本机已验证 3.11.9；wrapper 依次探测 `python3` → `python` → `py`，同 `session-recall.sh` 惯例）。
- 提交信息格式 `feat:` / `test:`（AGENTS.md）。
- 只创建/修改本计划列出的文件；不触碰 `install-agent-hooks.py`（M2 范围）。

## 文件结构

| 文件 | 职责 |
|---|---|
| Create `scripts/failure-event.py` | 契约 CLI：分类、reflectability、三级身份哈希 |
| Create `tests/test-failure-event.py` | golden cases + 成对指纹 + 确定性测试（subprocess 走真实 CLI） |
| Create `tests/failure-event-smoke.sh` | 仓库风格验收入口（探测解释器后跑 unittest） |
| Modify `decisions/2026-09-24-failure-reflection-loop.md` | 追加 M0 实施记录 |

## 输入 / 输出契约（所有任务共同消费）

输入 `failure_event_input/v1`（stdin 单个 JSON 文档）：

```json
{
  "schema_version": "failure_event_input/v1",
  "run_id": "R1", "task_id": "T1", "attempt": 1, "terminal_sequence": 1,
  "mode": "interactive",
  "signals": {
    "evaluator_verdict": null,
    "acceptance_evidence": null,
    "user_action": "none",
    "budget_exhausted": false,
    "verification_required": false,
    "verification_performed": true,
    "final_message": null,
    "runtime_error": "none",
    "fatal_error_origin": null,
    "flaky_retry_passed": false,
    "failure_category": null,
    "tool_identity": null,
    "error_signature": null,
    "scope": null,
    "path": null,
    "line": null
  }
}
```

枚举（`null` 合法，表示无该信号）：`evaluator_verdict ∈ {pass, fail}`；`acceptance_evidence ∈ {passed, failed}`；`user_action ∈ {none, cancel, rejection}`；`final_message ∈ {complete_claim, incomplete_claim}`；`runtime_error ∈ {none, fatal}`；`fatal_error_origin ∈ {external, agent, harness, unknown}`；`failure_category ∈ {requirement_misunderstanding, planning_error, reasoning_error, implementation_error, verification_gap, tool_usage_error, context_loss, missing_knowledge, environment, premature_stop, unknown}`。未知枚举值 → `ok:false`。

输出（最终形态，键按任务逐步补齐）：

```json
{
  "ok": true,
  "terminal_state": "task_failure",
  "reflectability": {"actionable": true, "recoverable": true, "agent_controllable": true},
  "failure_event_id": "fe_0123456789abcdef",
  "fingerprints": {
    "reflection": {"version": "rf/v1", "hash": "<64 hex>"},
    "recurrence": {"version": "rs/v1", "hash": "<64 hex>"}
  }
}
```

`reflectability.agent_controllable` 类型为 `true | false | "unknown"`。

分类优先级（精确顺序，DEC-FAILURE-AUTHORITY）：

```text
1 user_action == cancel                     → cancelled
2 user_action == rejection                  → task_failure
3 evaluator_verdict pass/fail               → success / task_failure
4 acceptance_evidence passed/failed         → success / task_failure
5 budget_exhausted                          → task_failure
6 verification_required and not verification_performed → task_failure
7 final_message == incomplete_claim         → task_failure
8 runtime_error == fatal                    → origin==agent ? task_failure : infra_failure
9 otherwise                                 → indeterminate
```

---

### Task 1: CLI 骨架 + 分类优先级 1–4（cancel / rejection / verdict / evidence）

**Files:**
- Create: `scripts/failure-event.py`
- Create: `tests/test-failure-event.py`

**Interfaces:**
- Consumes: 输入契约（见上）。
- Produces: `run_cli(doc) -> dict`（测试辅助）；`base_doc(**signal_overrides) -> dict`；输出键 `ok`、`terminal_state`（本任务仅此两键）；`classify(signals) -> str` 实现优先级 1–4，5–9 暂返回 `indeterminate`。

- [ ] **Step 1: 写失败测试（完整文件）**

```python
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
        out = run_cli.__wrapped__ if False else None  # noqa: F841 — see below
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
```

（注：`test_unknown_enum_rejected` 中的 `run_cli.__wrapped__` 死行是无效残留，实现者应删除该行及其 `noq a` 注释，只保留 subprocess 直调。）

- [ ] **Step 2: 运行确认失败**

Run: `python3 tests/test-failure-event.py -v`
Expected: FAIL——`scripts/failure-event.py` 不存在（FileNotFoundError / CLI 契约断言失败）。

- [ ] **Step 3: 最小实现**

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""FailureEvent contract CLI for the failure-reflection loop (M0).

Reads one failure_event_input/v1 JSON document from stdin, prints a
failure_event/v1 JSON document to stdout. Fail-open by contract
(DEC-FR-014): every path exits 0.

Spec: decisions/2026-09-24-failure-reflection-loop.md
"""
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
    # Steps 5–9 land in Task 2.
    if signals.get("budget_exhausted"):
        return "task_failure"
    if signals.get("verification_required") and not signals.get("verification_performed"):
        return "task_failure"
    if signals.get("final_message") == "incomplete_claim":
        return "task_failure"
    if signals.get("runtime_error") == "fatal":
        return "task_failure" if signals.get("fatal_error_origin") == "agent" else "infra_failure"
    return "indeterminate"


def main():
    try:
        raw = sys.stdin.read()
        doc = json.loads(raw) if raw.strip() else {}
        signals = doc.get("signals") or {}
        validate_signals(signals)
        state = classify(signals)
        if state not in TERMINAL_STATES:
            raise ValueError(f"invalid state: {state}")
        out = {"ok": True, "terminal_state": state}
    except Exception as exc:  # fail-open
        out = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}
    json.dump(out, sys.stdout, sort_keys=True, ensure_ascii=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

注：本任务实现里 5–9 步已随代码落地（与 Task 2 目标一致的连续实现是允许的），但**验收只断言 Task 1 的 6 个案例 + 3 个契约测试**；若实现者选择先只写 1–4 再在 Task 2 补齐 5–9，行为等价。

- [ ] **Step 4: 运行确认通过**

Run: `python3 tests/test-failure-event.py -v`
Expected: PASS（9 tests：3 契约 + 6 golden subTest）。

- [ ] **Step 5: Commit**

```bash
git add scripts/failure-event.py tests/test-failure-event.py
git commit -m "feat: failure-event CLI 五态分类优先级与金测骨架"
```

---

### Task 2: 全量 A1 判定表（优先级 5–9 补齐验收 + 先例守卫）

**Files:**
- Modify: `tests/test-failure-event.py`（替换 `GOLDEN_CASES` 为下表全量）
- 无 `scripts/failure-event.py` 行为变更预期（Task 1 已带 5–9；若 Step 2 发现缺分支，同任务补上）

**Interfaces:**
- Consumes: `base_doc`、`run_cli`（Task 1）。
- Produces: 全量 `GOLDEN_CASES`（21 案例），后续任务不得删改其期望值。

- [ ] **Step 1: 替换 GOLDEN_CASES 为全量表**

```python
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
```

- [ ] **Step 2: 运行**

Run: `python3 tests/test-failure-event.py -v`
Expected: PASS。若任何 subTest 失败（实现缺分支或优先级顺序错误），修 `scripts/failure-event.py` 的 `classify` 至全绿——顺序必须与 Global Constraints 的 1–9 精确一致。

- [ ] **Step 3: Commit**

```bash
git add tests/test-failure-event.py scripts/failure-event.py
git commit -m "test: A1 判定表 23 案例全量金测"
```

---

### Task 3: reflectability

**Files:**
- Modify: `scripts/failure-event.py`（新增 `reflectability()`，main 输出加键）
- Modify: `tests/test-failure-event.py`（新增测试类）

**Interfaces:**
- Consumes: `terminal_state`、`signals.failure_category`、`signals.fatal_error_origin`。
- Produces: 输出键 `reflectability: {actionable: bool, recoverable: bool, agent_controllable: true|false|"unknown"}`；函数 `reflectability(state, signals) -> dict`。

规则（确定性，DEC-FR-003 / A1 reflectability 字段）：

```text
state == task_failure:
    actionable = true
    recoverable = true
    agent_controllable = false 当 failure_category == "environment"
                         或 fatal_error_origin in {external, harness}
                         否则 true
state == infra_failure:
    actionable = false, recoverable = false, agent_controllable = false
其他（success / cancelled / indeterminate）:
    actionable = false, recoverable = false, agent_controllable = "unknown"
```

- [ ] **Step 1: 写失败测试**

```python
class Reflectability(unittest.TestCase):
    def test_success_not_actionable(self):
        out = run_cli(base_doc(acceptance_evidence="passed"))
        self.assertEqual(out["reflectability"],
                         {"actionable": False, "recoverable": False,
                          "agent_controllable": "unknown"})

    def test_infra_not_controllable(self):
        out = run_cli(base_doc(runtime_error="fatal", fatal_error_origin="external"))
        self.assertEqual(out["reflectability"],
                         {"actionable": False, "recoverable": False,
                          "agent_controllable": False})

    def test_task_failure_implementation_error_actionable(self):
        out = run_cli(base_doc(acceptance_evidence="failed",
                               failure_category="implementation_error"))
        self.assertEqual(out["reflectability"],
                         {"actionable": True, "recoverable": True,
                          "agent_controllable": True})

    def test_task_failure_environment_category_not_controllable(self):
        out = run_cli(base_doc(user_action="rejection", failure_category="environment"))
        self.assertEqual(out["reflectability"]["agent_controllable"], False)
        self.assertTrue(out["reflectability"]["actionable"])

    def test_indeterminate_unknown(self):
        out = run_cli(base_doc())
        self.assertEqual(out["reflectability"]["agent_controllable"], "unknown")
```

- [ ] **Step 2: 运行确认失败**

Run: `python3 tests/test-failure-event.py Reflectability -v`
Expected: FAIL——`KeyError: 'reflectability'`。

- [ ] **Step 3: 实现**

```python
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
```

main 中 `out` 构造改为：

```python
        out = {"ok": True, "terminal_state": state,
               "reflectability": reflectability(state, signals)}
```

- [ ] **Step 4: 全量回归**

Run: `python3 tests/test-failure-event.py -v`
Expected: PASS（全部）。

- [ ] **Step 5: Commit**

```bash
git add scripts/failure-event.py tests/test-failure-event.py
git commit -m "feat: failure-event reflectability 三态派生规则"
```

---

### Task 4: failure_event_id（确定性事件身份）

**Files:**
- Modify: `scripts/failure-event.py`（`failure_event_id()` + main 加键）
- Modify: `tests/test-failure-event.py`（新增测试类）

**Interfaces:**
- Consumes: 文档顶层 `run_id` / `task_id` / `attempt` / `terminal_sequence`。
- Produces: 输出键 `failure_event_id`，形如 `fe_<16 hex>`；`"fe_" + sha256(canonical({"v": "fe/v1", ...}))[:16]`。

- [ ] **Step 1: 写失败测试**

```python
class FailureEventId(unittest.TestCase):
    def test_deterministic_same_input(self):
        a = run_cli(base_doc())
        b = run_cli(base_doc())
        self.assertEqual(a["failure_event_id"], b["failure_event_id"])
        self.assertRegex(a["failure_event_id"], r"^fe_[0-9a-f]{16}$")

    def test_terminal_sequence_separates_events(self):
        a = run_cli(base_doc())
        doc = base_doc()
        doc["terminal_sequence"] = 2
        b = run_cli(doc)
        self.assertNotEqual(a["failure_event_id"], b["failure_event_id"])

    def test_run_id_separates_events(self):
        a = run_cli(base_doc())
        doc = base_doc()
        doc["run_id"] = "R2"
        b = run_cli(doc)
        self.assertNotEqual(a["failure_event_id"], b["failure_event_id"])
```

- [ ] **Step 2: 运行确认失败**

Run: `python3 tests/test-failure-event.py FailureEventId -v`
Expected: FAIL——`KeyError: 'failure_event_id'`。

- [ ] **Step 3: 实现**

```python
import hashlib

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
```

main 中 `out` 增加 `"failure_event_id": failure_event_id(doc)`。

- [ ] **Step 4: 全量回归** → Run: `python3 tests/test-failure-event.py -v` → PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/failure-event.py tests/test-failure-event.py
git commit -m "feat: deterministic failure_event_id (fe/v1)"
```

---

### Task 5: reflection_fingerprint（rf/v1，偏细）

**Files:**
- Modify: `scripts/failure-event.py`（噪声剥离 + `reflection_fingerprint()` + main 加 `fingerprints.reflection`）
- Modify: `tests/test-failure-event.py`（新增测试类）

**Interfaces:**
- Consumes: `signals.{failure_category, tool_identity, error_signature, scope, path, line}`。
- Produces: 输出键 `fingerprints.reflection = {"version": "rf/v1", "hash": "<64 hex>"}`。

哈希输入（DEC-FINGERPRINT：**保留行号与文件差异**，仅剥离确定性噪声）：

```python
{"v": "rf/v1", "category": ..., "tool": ..., "signature": strip_noise(sig),
 "scope": ..., "path": strip_noise(path), "line": line}
```

`strip_noise` 替换：ISO 时间戳 → `<TS>`；UUID → `<UUID>`；`C:\Users\<name>` / `/home/<name>` / `/Users/<name>` → `<HOME>`；`AppData/Local/Temp`、`/tmp/`、`/var/tmp/` 路径段 → `<TMP>`。**不做**行号剥离、**不做** basename 归并。

- [ ] **Step 1: 写失败测试**

```python
def fp_doc(**overrides):
    return base_doc(acceptance_evidence="failed",
                    failure_category="implementation_error",
                    tool_identity="pytest",
                    error_signature="LegacySchemaError: missing field 'invoice'",
                    scope="parser", path="src/parser.py", line=183,
                    **overrides)


class ReflectionFingerprint(unittest.TestCase):
    def test_identical_failures_equal(self):
        a = run_cli(fp_doc())
        b = run_cli(fp_doc())
        self.assertEqual(a["fingerprints"]["reflection"],
                         b["fingerprints"]["reflection"])
        self.assertEqual(a["fingerprints"]["reflection"]["version"], "rf/v1")

    def test_line_change_makes_new_fingerprint(self):
        a = run_cli(fp_doc())
        b = run_cli(fp_doc(line=241))
        self.assertNotEqual(a["fingerprints"]["reflection"]["hash"],
                            b["fingerprints"]["reflection"]["hash"])

    def test_path_change_makes_new_fingerprint(self):
        a = run_cli(fp_doc())
        b = run_cli(fp_doc(path="src/parser_v2.py"))
        self.assertNotEqual(a["fingerprints"]["reflection"]["hash"],
                            b["fingerprints"]["reflection"]["hash"])

    def test_timestamp_noise_ignored(self):
        a = run_cli(fp_doc(error_signature="fail at 2026-09-24T10:00:00Z"))
        b = run_cli(fp_doc(error_signature="fail at 2026-09-25T23:59:59Z"))
        self.assertEqual(a["fingerprints"]["reflection"]["hash"],
                         b["fingerprints"]["reflection"]["hash"])

    def test_tmp_path_noise_ignored(self):
        a = run_cli(fp_doc(path="C:\\Users\\dev\\AppData\\Local\\Temp\\run\\parser.py"))
        b = run_cli(fp_doc(path="/tmp/run/parser.py"))
        # 路径前缀均剥为 <TMP> 后剩余文本需一致才相等——两例剩余不同，
        # 因此改为同型路径仅 run 目录不同：
        a = run_cli(fp_doc(path="/tmp/run-a/parser.py"))
        b = run_cli(fp_doc(path="/tmp/run-b/parser.py"))
        self.assertEqual(a["fingerprints"]["reflection"]["hash"],
                         b["fingerprints"]["reflection"]["hash"])

    def test_windows_user_temp_noise_ignored(self):
        a = run_cli(fp_doc(path="C:\\Users\\dev\\AppData\\Local\\Temp\\run-a\\parser.py"))
        b = run_cli(fp_doc(path="C:\\Users\\dev\\AppData\\Local\\Temp\\run-b\\parser.py"))
        self.assertEqual(a["fingerprints"]["reflection"]["hash"],
                         b["fingerprints"]["reflection"]["hash"])

    def test_home_noise_ignored(self):
        a = run_cli(fp_doc(path="C:\\Users\\alice\\proj\\parser.py"))
        b = run_cli(fp_doc(path="C:\\Users\\bob\\proj\\parser.py"))
        self.assertEqual(a["fingerprints"]["reflection"]["hash"],
                         b["fingerprints"]["reflection"]["hash"])

    def test_uuid_noise_ignored(self):
        a = run_cli(fp_doc(error_signature="run 550e8400-e29b-41d4-a716-446655440000 failed"))
        b = run_cli(fp_doc(error_signature="run 6ba7b810-9dad-11d1-80b4-00c04fd430c8 failed"))
        self.assertEqual(a["fingerprints"]["reflection"]["hash"],
                         b["fingerprints"]["reflection"]["hash"])
```

（实现者注意：删除上例中被覆盖的第一对 `run_cli` 赋值，仅保留 `/tmp/run-a` vs `/tmp/run-b` 比较。）

- [ ] **Step 2: 运行确认失败** → Run: `python3 tests/test-failure-event.py ReflectionFingerprint -v` → FAIL（`KeyError: 'fingerprints'`）

- [ ] **Step 3: 实现**

```python
import re

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
```

main 中 `out` 增加：

```python
        out = {..., "fingerprints": {"reflection": reflection_fingerprint(signals)}}
```

- [ ] **Step 4: 全量回归** → PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/failure-event.py tests/test-failure-event.py
git commit -m "feat: reflection_fingerprint rf/v1（细粒度、噪声剥离、保留行号）"
```

---

### Task 6: recurrence_signature（rs/v1）+ 成对 golden + 确定性

**Files:**
- Modify: `scripts/failure-event.py`（`recurrence_signature()` + main 补 `fingerprints.recurrence`）
- Modify: `tests/test-failure-event.py`（新增测试类）

**Interfaces:**
- Consumes: `signals.{failure_category, scope, error_signature}`；`strip_noise`（Task 5）。
- Produces: 输出键 `fingerprints.recurrence = {"version": "rs/v1", "hash": "<64 hex>"}`。

哈希输入（DEC-FINGERPRINT：**不含 path/line**；签名先 `strip_noise` 再剥行号 `:<digits>` 再把路径类 token 归并为 basename）：

```python
{"v": "rs/v1", "category": ..., "scope": ...,
 "signature": normalize_recurrence(sig)}
```

- [ ] **Step 1: 写失败测试（成对 golden，M0 验收核心）**

```python
class RecurrenceSignature(unittest.TestCase):
    def test_parser_example_same_recurrence_different_reflection(self):
        a = run_cli(fp_doc(path="src/parser.py", line=183))
        b = run_cli(fp_doc(path="src/parser_v2.py", line=241))
        self.assertNotEqual(a["fingerprints"]["reflection"]["hash"],
                            b["fingerprints"]["reflection"]["hash"])
        self.assertEqual(a["fingerprints"]["recurrence"]["hash"],
                         b["fingerprints"]["recurrence"]["hash"])

    def test_line_only_change_same_recurrence(self):
        a = run_cli(fp_doc(line=183))
        b = run_cli(fp_doc(line=190))
        self.assertNotEqual(a["fingerprints"]["reflection"]["hash"],
                            b["fingerprints"]["reflection"]["hash"])
        self.assertEqual(a["fingerprints"]["recurrence"]["hash"],
                         b["fingerprints"]["recurrence"]["hash"])

    def test_different_category_different_recurrence(self):
        a = run_cli(fp_doc())
        b = run_cli(fp_doc(failure_category="requirement_misunderstanding"))
        self.assertNotEqual(a["fingerprints"]["recurrence"]["hash"],
                            b["fingerprints"]["recurrence"]["hash"])

    def test_different_scope_different_recurrence(self):
        a = run_cli(fp_doc())
        b = run_cli(fp_doc(scope="auth"))
        self.assertNotEqual(a["fingerprints"]["recurrence"]["hash"],
                            b["fingerprints"]["recurrence"]["hash"])

    def test_line_number_in_signature_normalized(self):
        a = run_cli(fp_doc(error_signature="parser.py:183 boom"))
        b = run_cli(fp_doc(error_signature="parser.py:241 boom"))
        self.assertEqual(a["fingerprints"]["recurrence"]["hash"],
                         b["fingerprints"]["recurrence"]["hash"])
        self.assertNotEqual(a["fingerprints"]["reflection"]["hash"],
                            b["fingerprints"]["reflection"]["hash"])

    def test_recurrence_version(self):
        out = run_cli(fp_doc())
        self.assertEqual(out["fingerprints"]["recurrence"]["version"], "rs/v1")


class Determinism(unittest.TestCase):
    def test_three_runs_identical_output(self):
        outputs = [run_cli(fp_doc()) for _ in range(3)]
        self.assertEqual(outputs[0], outputs[1])
        self.assertEqual(outputs[1], outputs[2])
```

- [ ] **Step 2: 运行确认失败** → Run: `python3 tests/test-failure-event.py RecurrenceSignature Determinism -v` → FAIL（`KeyError: 'recurrence'`）

- [ ] **Step 3: 实现**

```python
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
```

main 中 `fingerprints` 改为：

```python
        out = {..., "fingerprints": {
            "reflection": reflection_fingerprint(signals),
            "recurrence": recurrence_signature(signals),
        }}
```

- [ ] **Step 4: 全量回归** → Run: `python3 tests/test-failure-event.py -v` → PASS（Task 1–6 全部）

- [ ] **Step 5: Commit**

```bash
git add scripts/failure-event.py tests/test-failure-event.py
git commit -m "feat: recurrence_signature rs/v1 与成对金测"
```

---

### Task 7: smoke 入口 + 实施记录

**Files:**
- Create: `tests/failure-event-smoke.sh`
- Modify: `decisions/2026-09-24-failure-reflection-loop.md`（追加「实施记录」节）

**Interfaces:**
- Consumes: `tests/test-failure-event.py`（unittest 入口）。
- Produces: 验收命令 `bash tests/failure-event-smoke.sh`（退出码 0 = M0 通过）。

- [ ] **Step 1: 写 smoke 脚本**

```bash
#!/usr/bin/env bash
# Golden smoke for scripts/failure-event.py (M0 acceptance).
set -euo pipefail
cd "$(dirname "$0")/.."
py=""
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then py="$c"; break; fi
done
if [ -z "$py" ]; then
  echo "failure-event-smoke: no python interpreter found" >&2
  exit 1
fi
"$py" tests/test-failure-event.py -v
```

- [ ] **Step 2: 运行 smoke**

Run: `bash tests/failure-event-smoke.sh`
Expected: `OK` / exit 0；任何断言失败 exit 1。

- [ ] **Step 3: decisions 追加实施记录**

在 `decisions/2026-09-24-failure-reflection-loop.md` 末尾追加：

```markdown
## 实施记录

- M0（2026-09-24）：`scripts/failure-event.py` + `tests/test-failure-event.py` +
  `tests/failure-event-smoke.sh` 落地。A1 判定表 23 案例、reflectability 派生、
  fe/v1 / rf/v1 / rs/v1 三级身份与成对 golden、三连跑确定性全部通过。
  验收：`bash tests/failure-event-smoke.sh` → 0。
```

（案例数以实际 `GOLDEN_CASES` 长度为准，实现者跑一次 `python3 -c "import ast;..."` 或数表后写实数。）

- [ ] **Step 4: Commit**

```bash
git add tests/failure-event-smoke.sh decisions/2026-09-24-failure-reflection-loop.md
git commit -m "test: failure-event smoke 入口与 M0 实施记录"
```

---

## Self-Review 结论（写计划时已执行）

1. **Spec 覆盖**：DEC-FR-001 五态 → Task 1/2；DEC-FAILURE-AUTHORITY 权威链 → 分类 1–9 顺序；DEC-FINGERPRINT 三级身份 → Task 4/5/6（含成对 golden）；A1 表 18 行 + 先例守卫 → Task 2（23 案例）；fail-open → 契约测试；M0 验收「输出稳定」→ Task 6 三连跑。DEC-FAST-GATE 明确不实现（无任务，符合裁决）。
2. **占位符扫描**：无 TBD/TODO；两处标注的测试残留行已写明删除动作。
3. **类型一致性**：输出键 `terminal_state` / `reflectability` / `failure_event_id` / `fingerprints.{reflection,recurrence}` 与契约节一致；`rf/v1`、`rs/v1`、`fe/v1` 版本串全局一致。
