#!/usr/bin/env bash
# Golden smoke for scripts/retro-aggregate.py:
# aggregation of valid verdicts, P4 fail-fast validation, empty dir,
# and §4.8 budget telemetry from loop round reports.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

AGG="$ROOT/scripts/retro-aggregate.py"

# assert_run LABEL EXPECTED_EXIT DIR [EXPECTED_OUTPUT_GREP...]
# runs the aggregator against DIR, checks exit code, then greps combined
# output for each expected fragment (substring match, one per argument).
assert_run() {
  local label="$1" want_exit="$2" dir="$3"; shift 3
  local out rc
  out=$("$ROOT/scripts/retro-aggregate.py" "$dir" 2>&1) && rc=0 || rc=$?
  if [ "$rc" -ne "$want_exit" ]; then
    echo "retro-aggregate smoke: FAIL ($label): exit $rc, want $want_exit" >&2
    echo "$out" >&2
    exit 1
  fi
  local frag
  for frag in "$@"; do
    if ! grep -qF "$frag" <<<"$out"; then
      echo "retro-aggregate smoke: FAIL ($label): output missing '$frag'" >&2
      echo "$out" >&2
      exit 1
    fi
  done
}

# refute LABEL OUTPUT FRAGMENT — assert fragment is NOT in output.
refute() {
  if grep -qF "$3" <<<"$2"; then
    echo "retro-aggregate smoke: FAIL ($1): output must not contain '$3'" >&2
    echo "$2" >&2
    exit 1
  fi
}

write_verdict() { # FILE TASK_ID ORIGIN RED ROUNDS
  cat > "$1" <<EOF
schema_version: 1
task_id: "$2"
milestone: m1
decision: accepted
origin: $3
scores: {correctness: 5, test_quality: 4, simplicity: 5, resource_safety: 5, convention_fit: 4}
issues: []
rounds: $5
coder_red_green_evidence: $4
loc_delta: {added: 10, removed: 2}
new_dependencies: 0
timestamp: "2026-09-01T08:00:00+08:00"
EOF
}

# --- 1. valid aggregation: protocol + manual origins, one MAJOR issue ----
GOOD="$TMP/good"; mkdir -p "$GOOD"
write_verdict "$GOOD/01-alpha-m1.yaml"        "01-alpha"        protocol true  1
write_verdict "$GOOD/02-beta-m1.yaml"         "02-beta"         manual  false 2
cat > "$GOOD/03-gamma-m1.yaml" <<'EOF'
schema_version: 1
task_id: "03-gamma"
milestone: m1
decision: accepted
scores: {correctness: 4, test_quality: 3, simplicity: 5, resource_safety: 2, convention_fit: 4}
issues:
  - severity: MAJOR
    category: resource
    summary: "unbounded cache grows linearly"
rounds: 1
coder_red_green_evidence: true
loc_delta: {added: 30, removed: 4}
new_dependencies: 0
timestamp: "2026-09-01T09:00:00+08:00"
EOF
assert_run "valid aggregation" 0 "$GOOD" \
  "verdicts: 3   accepted: 3" \
  "avg rounds: 1.33" \
  "origin protocol" \
  "origin manual" \
  "resource" \
  "recurring hints" \
  "03-gamma"

# --- 2. P4 fail-fast: ALL invalid files listed, exit 2 --------------------
BAD="$TMP/bad"; mkdir -p "$BAD"
write_verdict "$BAD/01-ok-m1.yaml" "01-ok" manual true 1
printf 'schema_version: 1\ntask_id: [unclosed\n' > "$BAD/02-parse-error-m1.yaml"
cat > "$BAD/03-schema-violation-m1.yaml" <<'EOF'
schema_version: 1
task_id: "03-bad"
milestone: m1
decision: accepted
scores: {correctness: 9, test_quality: 4, simplicity: 5, resource_safety: 5, convention_fit: 4}
issues: []
rounds: 1
coder_red_green_evidence: true
loc_delta: {added: 1, removed: 1}
new_dependencies: 0
timestamp: "2026-09-01T10:00:00+08:00"
EOF
out=$("$ROOT/scripts/retro-aggregate.py" "$BAD" 2>&1) && rc=0 || rc=$?
if [ "$rc" -ne 2 ]; then
  echo "retro-aggregate smoke: FAIL (P4 fail-fast): exit $rc, want 2" >&2
  echo "$out" >&2
  exit 1
fi
for frag in "INVALID VERDICT DATA" "02-parse-error-m1.yaml" \
            "03-schema-violation-m1.yaml" "scores.correctness"; do
  if ! grep -qF "$frag" <<<"$out"; then
    echo "retro-aggregate smoke: FAIL (P4 fail-fast): output missing '$frag'" >&2
    echo "$out" >&2
    exit 1
  fi
done
# the clean file must NOT be accused
refute "P4 fail-fast" "$out" "01-ok-m1.yaml: "

# --- 3. empty dir: exit 0, friendly message ------------------------------
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"
assert_run "empty dir" 0 "$EMPTY" "no verdicts found"

# --- 4. budget telemetry from round reports -------------------------------
ROUNDS="$TMP/rounds"; mkdir -p "$ROUNDS"
cat > "$ROUNDS/round-1.yaml" <<'EOF'
round: 1
task_id: "01-alpha"
decision: accepted
trace_file: "traces/round-1-01-alpha.pi.jsonl"
budget: {tokens: 100000, cost_usd: 0.50}
total_tokens: 120000
cost_usd: 0.012
cost_source: native
budget_exceeded: true
timestamp: "2026-09-01T08:00:00+08:00"
EOF
cat > "$ROUNDS/round-2.yaml" <<'EOF'
round: 2
task_id: "02-beta"
decision: accepted
trace_file: "traces/round-2-02-beta.pi.jsonl"
budget: {tokens: 100000}
total_tokens: unknown
cost_usd: null
cost_source: none
budget_exceeded: null
timestamp: "2026-09-01T09:00:00+08:00"
EOF
out=$("$AGG" "$GOOD" --rounds-dir "$ROUNDS")
if ! grep -qF 'budget telemetry' <<<"$out" \
   || ! grep -qF 'totals: tokens 120000' <<<"$out" \
   || ! grep -qF 'budget_exceeded rounds: 1' <<<"$out" \
   || ! grep -qF 'unmetered rounds (no usage data)' <<<"$out"; then
  echo "retro-aggregate smoke: FAIL (budget telemetry totals)" >&2
  echo "$out" >&2
  exit 1
fi

# --- 5. no rounds dir: no budget section ----------------------------------
out=$("$AGG" "$GOOD" --rounds-dir "")
if grep -qF 'budget telemetry' <<<"$out"; then
  echo "retro-aggregate smoke: FAIL (empty --rounds-dir must skip telemetry)" >&2
  exit 1
fi

echo "retro-aggregate smoke test: PASS"
