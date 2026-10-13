#!/usr/bin/env bash
# Golden smoke for the rsi-loop orchestration mechanism (skills/rsi-loop):
# skill file integrity, state/round/queue file contracts, the §4.3 retro
# trigger decision table, and stop-condition table completeness.
#
# rsi-loop is a markdown protocol executed by an agent — there is no
# executable orchestrator to smoke end-to-end. This test pins the protocol's
# machine-checkable contracts so drift breaks loudly here, not in a live loop
# (design §4.5.8: skill self-restraint is weaker than external checks).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SKILL="$ROOT/.harness/skills/rsi-loop"
FAIL=""

# fail LABEL — record a failure (all cases run; exit non-zero at the end).
fail() { echo "rsi-loop smoke: FAIL ($1)" >&2; FAIL=1; }

py() { # py 'expr' — run python with yaml available
  python3 -c "
import sys, yaml, json
try:
    import yaml
except ImportError:
    sys.exit('rsi-loop smoke: PyYAML required')
" 2>/dev/null || { echo "rsi-loop smoke: python3/yaml unavailable" >&2; exit 1; }
}
py

# --- 1. skill integrity ----------------------------------------------------
for f in SKILL.md references/preflight.md references/round-protocol.md \
         references/gate-policy.md references/stop-conditions.md; do
  [ -f "$SKILL/$f" ] || fail "missing skill file: $f"
done
grep -q '^name: rsi-loop' "$SKILL/SKILL.md" || fail "SKILL.md frontmatter name"
grep -q '^version:' "$SKILL/SKILL.md" || fail "SKILL.md frontmatter version"

# --- 2. state.yaml contract ------------------------------------------------
cat > "$TMP/state.yaml" <<'EOF'
schema_version: 1
loop_id: "loop-smoke-01"
gate: l1-auto
rounds_requested: 5
rounds_done: 2
queue_file: "progress/loop/tasks.yaml"
queue_position: 2
pause: false
counters:
  accepted: 2
  rejected: 0
  no_red_evidence: 0
  issues_by_category: {testing: 1}
  proposals_landed: []
  evals: []
  repair_attempts_total: 0
  repair_exhausted_rounds: 0
  tokens_total: 300000
  cost_usd_total: 0.02
  budget_exceeded_rounds: 0
metrics:
  last_pass_rate: 1.0
  baseline_pass_rate: 1.0
EOF
python3 - "$TMP/state.yaml" <<'PYEOF' || fail "state.yaml contract"
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
top = {"schema_version", "loop_id", "gate", "rounds_requested",
       "rounds_done", "counters", "metrics"}
missing = top - set(d)
assert not missing, f"state missing top-level: {missing}"
assert d["gate"] in ("observe-only", "l1-auto", "all-manual"), d["gate"]
counters = d["counters"]
need = {"accepted", "rejected", "no_red_evidence", "issues_by_category",
        "proposals_landed", "repair_attempts_total",
        "tokens_total", "cost_usd_total", "budget_exceeded_rounds"}
missing = need - set(counters)
assert not missing, f"state counters missing: {missing}"
PYEOF
# gate validation actually rejects invalid levels
sed 's/^gate: l1-auto/gate: turbo/' "$TMP/state.yaml" > "$TMP/state-bad.yaml"
python3 - "$TMP/state-bad.yaml" <<'PYEOF' 2>/dev/null && fail "state gate enum not enforced in contract check"
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert d["gate"] in ("observe-only", "l1-auto", "all-manual"), d["gate"]
PYEOF

# --- 3. round report contract ----------------------------------------------
cat > "$TMP/round-1.yaml" <<'EOF'
round: 1
task_id: "01-alpha"
gate: observe-only
decision: accepted
verdict_file: "evals/results/01-alpha-m1.yaml"
trace_file: "traces/round-1-01-alpha.pi.jsonl"
budget: {tokens: 100000, cost_usd: 0.50}
token_usage: {input: 100, output: 200, cache_read: 300, cache_write: 0, reasoning: 50}
total_tokens: 650
cost_usd: 0.001
cost_source: native
budget_exceeded: false
mutations: []
eval_after: null
timestamp: "2026-09-01T08:00:00+08:00"
EOF
python3 - "$TMP/round-1.yaml" <<'PYEOF' || fail "round report contract"
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
need = {"round", "task_id", "decision", "verdict_file", "trace_file",
        "budget", "total_tokens", "cost_usd", "cost_source",
        "budget_exceeded", "timestamp"}
missing = need - set(d)
assert not missing, f"round report missing: {missing}"
assert d["decision"] in ("accepted", "rejected", "no-verdict"), d["decision"]
assert d["trace_file"], "P6: round without trace_file is invalid"
PYEOF
# a round without trace_file must trip the same contract
cat > "$TMP/round-bad.yaml" <<'EOF'
round: 2
task_id: "02-beta"
decision: accepted
timestamp: "2026-09-01T09:00:00+08:00"
EOF
python3 - "$TMP/round-bad.yaml" <<'PYEOF' 2>/dev/null && fail "trace_file requiredness not enforced in contract check"
import sys, yaml
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
assert d.get("trace_file"), "P6: round without trace_file is invalid"
PYEOF

# --- 4. queue contract (preflight #5 / TAKE double-check) -------------------
cat > "$TMP/queue-ok.yaml" <<'EOF'
- task_id: "01-alpha"
  description: "evals/tasks/01-alpha/task.md"
  workdir: "evals/sandbox/01-alpha"
  gate_ok: true
  budget: {tokens: 100000}
EOF
cat > "$TMP/queue-bad.yaml" <<'EOF'
- task_id: "01-alpha"
  description: "evals/tasks/01-alpha/task.md"
  gate_ok: true
  budget: {tokens: 100000}
- task_id: "02-beta"
  description: "evals/tasks/02-beta/task.md"
  gate_ok: true
EOF
python3 - "$TMP/queue-bad.yaml" <<'PYEOF' || fail "queue unbudgeted detection"
import sys, yaml
entries = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
bad = [e["task_id"] for e in entries
       if not (e.get("budget") or {}).get("tokens")]
assert bad == ["02-beta"], f"unbudgeted tasks: {bad}"
print("unbudgeted: " + ", ".join(bad))
PYEOF

# --- 5. §4.3 retro trigger decision table ----------------------------------
python3 - <<'PYEOF' || fail "retro trigger decision table"
import sys

def retro_trigger(tasks_since_last_retro, blockmajor_by_category,
                  pass_rate, baseline):
    """docs/rsi-design.md §4.3: any one of the three conditions fires."""
    if tasks_since_last_retro >= 5:
        return True
    if any(n >= 3 for n in blockmajor_by_category.values()):
        return True
    if baseline is not None and pass_rate < baseline:
        return True
    return False

cases = [
    # (tasks_since, blockmajor, pass_rate, baseline, expected, label)
    (5, {}, 1.0, 1.0, True,  "N=5 tasks fires"),
    (4, {}, 1.0, 1.0, False, "N=4 does not fire"),
    (2, {"resource": 3}, 1.0, 1.0, True,  "3x BLOCKER+MAJOR in one category fires"),
    (2, {"resource": 2, "testing": 2}, 1.0, 1.0, False, "2+2 across categories does not fire"),
    (2, {"resource": 1, "testing": 1, "scope": 1}, 1.0, 1.0, False, "1+1+1 across categories does not fire"),
    (1, {}, 0.9, 1.0, True,  "eval drop fires"),
    (1, {}, 1.0, 1.0, False, "eval at baseline does not fire"),
    (1, {}, 1.0, 1.0, False, "eval above baseline does not fire"),
]
for tasks, cats, rate, base, want, label in cases:
    got = retro_trigger(tasks, cats, rate, base)
    assert got == want, f"{label}: got {got}, want {want}"
PYEOF

# --- 6. stop-conditions table completeness ---------------------------------
for n in 1 2 3 4 5 6 7 8 9; do
  grep -qE "^\| $n \|" "$SKILL/references/stop-conditions.md" \
    || fail "stop-conditions missing row #$n"
done
grep -q 'budget_exceeded: true' "$SKILL/references/stop-conditions.md" \
  || fail "stop-conditions #8 budget breach wording"
grep -q 'loop_budget' "$SKILL/references/stop-conditions.md" \
  || fail "stop-conditions #9 loop budget wording"

# --- 7. example files parse and match the contracts ------------------------
for ex in state.yaml.example round.yaml.example; do
  [ -f "$ROOT/progress/loop/$ex" ] || fail "missing example: $ex"
done
python3 - "$ROOT/progress/loop" <<'PYEOF' || fail "example files parse + contract match"
import sys, yaml
state = yaml.safe_load(open(sys.argv[1] + "/state.yaml.example", encoding="utf-8"))
assert state["gate"] in ("observe-only", "l1-auto", "all-manual")
need = {"accepted", "rejected", "tokens_total", "budget_exceeded_rounds"}
missing = need - set(state["counters"])
assert not missing, f"state.yaml.example counters missing: {missing}"
rnd = yaml.safe_load(open(sys.argv[1] + "/round.yaml.example", encoding="utf-8"))
for k in ("round", "task_id", "decision", "trace_file", "budget",
          "total_tokens", "cost_source", "budget_exceeded"):
    assert k in rnd, f"round.yaml.example missing: {k}"
PYEOF

if [ -n "$FAIL" ]; then
  echo "rsi-loop smoke test: FAIL" >&2
  exit 1
fi
echo "rsi-loop smoke test: PASS"
