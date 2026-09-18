#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# assert_json FILE PYTHON_EXPR LABEL — eval expr with d = parsed JSON of FILE
assert_json() {
  local out
  if ! out=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert eval(sys.argv[2], {'d': d})
" "$1" "$2" 2>&1); then
    echo "trace-usage smoke: FAIL ($3): $2 -> $out" >&2
    exit 1
  fi
}

# 1. synthetic pi trace: exact breakdown, native cost
cat > "$TMP/pi.jsonl" <<'EOF'
{"type":"session","version":3,"id":"fixture"}
{"type":"message","message":{"role":"user","content":[{"type":"text","text":"task"}]}}
{"type":"message","message":{"role":"assistant","usage":{"input":100,"output":200,"cacheRead":300,"cacheWrite":0,"reasoning":50,"totalTokens":650,"cost":{"input":0.001,"output":0.008,"cacheRead":0.001,"cacheWrite":0,"total":0.01}}}}
{"type":"message","message":{"role":"assistant","usage":{"input":10,"output":20,"cacheRead":30,"cacheWrite":0,"reasoning":5,"totalTokens":65,"cost":{"total":0.001}}}}
EOF
python3 "$ROOT/scripts/trace-usage.py" "$TMP/pi.jsonl" > "$TMP/pi.json"
assert_json "$TMP/pi.json" "d['agent']=='pi' and d['requests']==2 and d['total_tokens']==715" "pi totals"
assert_json "$TMP/pi.json" "d['tokens']=={'input':110,'output':220,'cache_read':330,'cache_write':0,'reasoning':55}" "pi breakdown"
assert_json "$TMP/pi.json" "d['cost_source']=='native' and abs(d['cost_usd']-0.011)<1e-9" "pi native cost"

# 2. synthetic kimi session dir: exact totals, no cost without pricing
mkdir -p "$TMP/kimi-session"
cat > "$TMP/kimi-session/wire.jsonl" <<'EOF'
{"timestamp": 1.0, "message": {"type": "StatusUpdate", "payload": {"context_tokens": 1000, "token_usage": {"input_other": 50000, "output": 100000, "input_cache_read": 200000, "input_cache_creation": 5000}}}}
{"timestamp": 2.0, "message": {"type": "StatusUpdate", "payload": {"context_tokens": 2000, "token_usage": {"input_other": 50000, "output": 100000, "input_cache_read": 200000, "input_cache_creation": 5000}}}}
EOF
python3 "$ROOT/scripts/trace-usage.py" "$TMP/kimi-session" > "$TMP/kimi.json"
assert_json "$TMP/kimi.json" "d['agent']=='kimi' and d['requests']==2 and d['total_tokens']==710000" "kimi totals"
assert_json "$TMP/kimi.json" "d['tokens']=={'input':100000,'output':200000,'cache_read':400000,'cache_write':10000,'reasoning':0}" "kimi breakdown"
assert_json "$TMP/kimi.json" "d['cost_usd'] is None and d['cost_source']=='none'" "kimi cost unknown without pricing"

# 3. kimi cost via pricing table
cat > "$TMP/pricing.yaml" <<'EOF'
pricing:
  default:
    input: 1.0
    output: 2.0
    cache_read: 0.5
    cache_write: 0.0
EOF
python3 "$ROOT/scripts/trace-usage.py" "$TMP/kimi-session" --pricing "$TMP/pricing.yaml" > "$TMP/kimi2.json"
assert_json "$TMP/kimi2.json" "d['cost_source']=='pricing' and abs(d['cost_usd']-0.7)<1e-9" "kimi pricing cost"

# 4. unknown format falls back, never guesses
python3 "$ROOT/scripts/trace-usage.py" "$ROOT/evals/baseline.json" > "$TMP/unknown.json"
assert_json "$TMP/unknown.json" "d['agent']=='unknown' and d['requests']==0 and d['total_tokens'] is None and d['cost_source']=='none'" "unknown fallback"

# 5. real traces (historical rounds, values cross-checked 2026-09-18)
python3 "$ROOT/scripts/trace-usage.py" \
  "$ROOT/progress/loop/traces/round-1-11-concurrency-shared-state.pi.jsonl" > "$TMP/real-pi.json"
assert_json "$TMP/real-pi.json" \
  "d['agent']=='pi' and d['requests']>0 and d['total_tokens']==435268 and d['cost_source']=='native' and d['cost_usd']>0" \
  "real pi trace"
python3 "$ROOT/scripts/trace-usage.py" \
  "$ROOT/progress/loop/traces/round-5-15-weak-test-regression.kimi" > "$TMP/real-kimi.json"
assert_json "$TMP/real-kimi.json" "d['agent']=='kimi' and d['total_tokens']==893318" "real kimi trace"

# 6. missing path exits 2
if python3 "$ROOT/scripts/trace-usage.py" "$TMP/does-not-exist.jsonl" >/dev/null 2>&1; then
  echo "trace-usage smoke: FAIL (missing path should exit 2)" >&2
  exit 1
fi

echo "trace-usage smoke test: PASS"
