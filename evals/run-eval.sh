#!/usr/bin/env bash
set -euo pipefail

# RSI eval harness: list / setup / verify / check.
# Style follows install.sh. Tasks live in tasks/<NN-slug>/, sandboxes in sandbox/<slug>/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_DIR="$SCRIPT_DIR/tasks"
SANDBOX_DIR="$SCRIPT_DIR/sandbox"
RESULTS_DIR="$SCRIPT_DIR/results"
BASELINE_FILE="$SCRIPT_DIR/baseline.json"

usage() {
  cat <<'USAGE'
RSI eval harness

Usage:
  run-eval.sh list                 List all eval tasks
  run-eval.sh setup [slug...]      (Re)create sandboxes for the given tasks (default: all)
  run-eval.sh verify [slug...]     Run verify.sh in each sandbox, print pass/fail table,
                                   write results to evals/results/eval-<timestamp>.json
  run-eval.sh check [slug...]      Verify, then compare pass rate with baseline.json;
                                   exit 1 if the pass rate regressed below the baseline
  run-eval.sh -h|--help            Show this help

Notes:
  This script does NOT run any agent. The loop is:
    setup -> an agent works inside evals/sandbox/<slug>/ following task.md -> verify
USAGE
}

list_tasks() {
  find "$TASKS_DIR" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' -exec basename {} \; | sort
}

# Resolve slugs from args, or all tasks when no args. Validates existence.
resolve_slugs() {
  if [ "$#" -eq 0 ]; then
    list_tasks
    return
  fi
  for slug in "$@"; do
    if [ ! -d "$TASKS_DIR/$slug" ]; then
      echo "Unknown task: $slug" >&2
      echo "Known tasks:" >&2
      list_tasks >&2
      exit 2
    fi
    printf '%s\n' "$slug"
  done
}

cmd_setup() {
  mapfile -t slugs < <(resolve_slugs "$@")
  [ "${#slugs[@]}" -gt 0 ] || { echo "No tasks found in $TASKS_DIR" >&2; exit 1; }
  for slug in "${slugs[@]}"; do
    sandbox="$SANDBOX_DIR/$slug"
    rm -rf "$sandbox"
    mkdir -p "$sandbox"
    bash "$TASKS_DIR/$slug/setup.sh" "$sandbox"
    printf 'setup  %s\n' "$slug"
  done
  echo
  echo "Sandboxes ready under evals/sandbox/. Hand each task.md to an agent, then run: $0 verify"
}

# Run verify.sh for one slug inside its sandbox. Prints PASS/FAIL; returns 0/1.
verify_one() {
  slug="$1"
  sandbox="$SANDBOX_DIR/$slug"
  if [ ! -d "$sandbox" ]; then
    echo "Sandbox missing for $slug; run: $0 setup $slug" >&2
    return 2
  fi
  if (cd "$sandbox" && bash "$TASKS_DIR/$slug/verify.sh") >"$sandbox/.verify-output.log" 2>&1; then
    printf '%-36s PASS\n' "$slug"
    return 0
  else
    printf '%-36s FAIL  (log: evals/sandbox/%s/.verify-output.log)\n' "$slug" "$slug"
    return 1
  fi
}

# Verifies slugs, prints table, writes results JSON. Sets globals:
#   LAST_RESULTS_FILE, LAST_PASS_RATE
run_verify() {
  mapfile -t slugs < <(resolve_slugs "$@")
  [ "${#slugs[@]}" -gt 0 ] || { echo "No tasks found in $TASKS_DIR" >&2; exit 1; }
  mkdir -p "$RESULTS_DIR"
  echo "task                                 result"
  echo "-----------------------------------  ------"
  pairs=()
  passed=0
  for slug in "${slugs[@]}"; do
    if verify_one "$slug"; then
      pairs+=("$slug=pass")
      passed=$((passed + 1))
    else
      pairs+=("$slug=fail")
    fi
  done
  total="${#slugs[@]}"
  ts="$(date +%Y%m%dT%H%M%S)"
  LAST_RESULTS_FILE="$RESULTS_DIR/eval-$ts.json"
  python3 - "$LAST_RESULTS_FILE" "$ts" "$passed" "$total" "${pairs[@]}" <<'PY'
import json, sys
out, ts, passed, total = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
per_task = {}
for pair in sys.argv[5:]:
    slug, status = pair.rsplit("=", 1)
    per_task[slug] = {"status": status}
rate = passed / total if total else 0.0
doc = {
    "schema_version": 1,
    "timestamp": ts,
    "passed": passed,
    "total": total,
    "pass_rate": rate,
    "per_task": per_task,
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")
PY
  LAST_PASS_RATE="$(python3 -c "print($passed / $total if $total else 0.0)")"
  echo
  printf 'pass@1: %d/%d (%.2f)\n' "$passed" "$total" "$(python3 -c "print($passed / $total if $total else 0.0)")"
  echo "results: ${LAST_RESULTS_FILE#$SCRIPT_DIR/}"
}

cmd_check() {
  run_verify "$@"
  echo
  python3 - "$BASELINE_FILE" "$LAST_RESULTS_FILE" <<'PY'
import json, sys
baseline_path, results_path = sys.argv[1], sys.argv[2]
with open(baseline_path, encoding="utf-8") as f:
    baseline = json.load(f)
with open(results_path, encoding="utf-8") as f:
    results = json.load(f)
base_rate = baseline.get("pass_rate")
cur_rate = results["pass_rate"]
if base_rate is None:
    print("baseline pass_rate is null (not yet measured); nothing to compare. OK.")
    sys.exit(0)
print(f"baseline pass_rate: {base_rate:.4f}  current: {cur_rate:.4f}")
if cur_rate < base_rate:
    print("REGRESSION: pass rate dropped below baseline", file=sys.stderr)
    sys.exit(1)
print("OK: pass rate at or above baseline")
PY
}

case "${1:-}" in
  list) shift; list_tasks ;;
  setup) shift; cmd_setup "$@" ;;
  verify) shift; run_verify "$@" ;;
  check) shift; cmd_check "$@" ;;
  -h|--help|"") usage ;;
  *) echo "Unknown command: $1" >&2; usage >&2; exit 2 ;;
esac
