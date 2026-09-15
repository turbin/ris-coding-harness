#!/usr/bin/env bash
set -euo pipefail

# compact-recall smoke test: exercise the PostCompact archive and
# UserPromptSubmit recall scripts against a synthetic KIMI_CODE_HOME and a
# scratch project — no real CLI compaction needed.
#
#   tests/compact-recall-smoke.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd -W)"
PY=""
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -n "$PY" ] || { echo "SKIP: no python interpreter found"; exit 0; }

# Use a Windows-style path (pwd -W) so the native Python interpreter and the
# shell agree on the scratch location.
WORK="$ROOT/tmp/compact-recall-smoke-$$"
rm -rf "$WORK"; mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# --- synthetic Kimi home with one session whose wire carries a compaction ---
FAKE_HOME="$WORK/kimi-home"
SESSION_ID="session_00000000-1111-2222-3333-444444444444"
SESSION_DIR="$FAKE_HOME/sessions/wd_fake_a1b2c3d4e5f6/$SESSION_ID"
mkdir -p "$SESSION_DIR/agents/main"
printf '%s\n' \
  '{"type":"full_compaction.begin","source":"manual","time":1767225600000}' \
  '{"type":"context.apply_compaction","summary":"已完成 ris-coding-harness 的 compact-recall 初版：归档脚本、回顾注入、安装器集成全部落地。\n剩余：冒烟测试与真实 /compact 验证。"}' \
  '{"type":"full_compaction.complete","time":1767225601000}' \
  > "$SESSION_DIR/agents/main/wire.jsonl"
printf '%s\n' \
  "{\"sessionId\":\"$SESSION_ID\",\"sessionDir\":\"$SESSION_DIR\",\"workDir\":\"$WORK/proj\"}" \
  > "$FAKE_HOME/session_index.jsonl"

# --- scratch project ---
PROJ="$WORK/proj"
mkdir -p "$PROJ/conversations"

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   - $1"; }
bad()  { fail=$((fail+1)); echo "FAIL - $1"; }

# 1) PostCompact payload -> archive file + index row
OUT="$(printf '%s' "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"$SESSION_ID\",\"session_title\":\"smoke\",\"cwd\":\"$PROJ\"}" \
  | KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" 2>&1)"
ARCHIVE="$PROJ/conversations/archive/$SESSION_ID/2026-01-01T00-00-00Z.md"
if [ -f "$ARCHIVE" ] && grep -q "compact-recall 初版" "$ARCHIVE"; then
  ok "archive file written with summary text"
else
  bad "archive file missing or empty (output: $OUT)"
fi
if grep -q "archive/$SESSION_ID/2026-01-01T00-00-00Z.md" "$PROJ/conversations/index.md" 2>/dev/null; then
  ok "index.md contains the archive row"
else
  bad "index.md missing archive row"
fi

# 2) duplicate event must not duplicate the index row
printf '%s' "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"$SESSION_ID\",\"session_title\":\"smoke\",\"cwd\":\"$PROJ\"}" \
  | KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" >/dev/null 2>&1
n="$(grep -c "archive/$SESSION_ID/2026-01-01T00-00-00Z.md" "$PROJ/conversations/index.md")"
[ "$n" -eq 1 ] && ok "duplicate PostCompact deduped" || bad "index row duplicated (n=$n)"

# 3) second, newer compaction -> newer row sorts first
printf '%s\n' \
  '{"type":"full_compaction.begin","source":"auto","time":1767312000000}' \
  '{"type":"context.apply_compaction","summary":"第二条摘要：验证倒序排序。"}' \
  '{"type":"full_compaction.complete","time":1767312001000}' \
  >> "$SESSION_DIR/agents/main/wire.jsonl"
printf '%s' "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"$SESSION_ID\",\"session_title\":\"smoke\",\"cwd\":\"$PROJ\"}" \
  | KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" >/dev/null 2>&1
first_row="$(grep '^|' "$PROJ/conversations/index.md" | grep -v '^|---' | sed -n '2p')"
case "$first_row" in
  *2026-01-02T00-00-00Z*) ok "index sorted newest-first" ;;
  *) bad "newest row not first: $first_row" ;;
esac

# 4) session-recall: first prompt injects, immediate second stays silent
R1="$(printf '%s' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$PROJ\"}" \
  | KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/session-recall.py" 2>/dev/null)"
R2="$(printf '%s' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$PROJ\"}" \
  | KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/session-recall.py" 2>/dev/null)"
case "$R1" in
  *对话归档简报*) ok "recall briefing injected on first prompt" ;;
  *) bad "no briefing on first prompt" ;;
esac
[ -z "$R2" ] && ok "recall silent on repeated prompt" || bad "recall repeated: $R2"

# 5) recall re-fires after index changes
sleep 0.05
printf '%s' "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"$SESSION_ID\",\"session_title\":\"smoke\",\"cwd\":\"$PROJ\"}" \
  | KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" >/dev/null 2>&1
touch "$PROJ/conversations/index.md"
R3="$(printf '%s' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID\",\"cwd\":\"$PROJ\"}" \
  | KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/session-recall.py" 2>/dev/null)"
case "$R3" in
  *对话归档简报*) ok "recall re-injects after index update" ;;
  *) bad "no re-injection after index update" ;;
esac

# 6) claude PostCompact payload (compact_summary delivered inline)
printf '%s' '{"hook_event_name":"PostCompact","session_id":"sess-claude","session_title":"c","trigger":"manual","compact_summary":"claude 直接携带的摘要。"}' \
  | ( cd "$PROJ" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" --flavor claude >/dev/null 2>&1 )
if ls "$PROJ/conversations/archive/sess-claude/"*.md >/dev/null 2>&1 && grep -q "claude 直接携带的摘要" "$PROJ"/conversations/archive/sess-claude/*.md; then
  ok "claude payload compact_summary archived"
else
  bad "claude payload not archived"
fi

# 7) codex rollout transcript extraction (type:"compacted")
ROLLOUT="$WORK/rollout-test.jsonl"
printf '%s\n' \
  '{"timestamp":"2026-01-03T00:00:00Z","type":"event_msg","payload":{"message":"noise"}}' \
  '{"timestamp":"2026-01-03T00:00:00Z","type":"compacted","payload":{"message":"codex rollout 中的压缩摘要。"}}' \
  > "$ROLLOUT"
printf '%s' "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"thr_1\",\"cwd\":\"$PROJ\",\"transcript_path\":\"$ROLLOUT\",\"trigger\":\"auto\"}" \
  | ( cd "$PROJ" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" --flavor codex >/dev/null 2>&1 )
if [ -f "$PROJ/conversations/archive/thr_1/2026-01-03T00-00-00Z.md" ] && grep -q "codex rollout" "$PROJ/conversations/archive/thr_1/2026-01-03T00-00-00Z.md"; then
  ok "codex transcript compacted line archived with rollout timestamp"
else
  bad "codex transcript extraction failed"
fi

# 8) codex recall output format (JSON hookSpecificOutput)
R4="$(printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"sess-codex","cwd":"'"$PROJ"'"}' \
  | KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/session-recall.py" --format codex 2>/dev/null)"
case "$R4" in
  '{"hookSpecificOutput"'*) ok "codex recall emits JSON additionalContext" ;;
  *) bad "codex recall format wrong: ${R4:0:60}" ;;
esac

# 9) installer idempotency + foreign-entry preservation (claude adapter)
mkdir -p "$PROJ/.claude"
cat > "$PROJ/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "echo foreign-hook" } ] }
    ]
  }
}
JSON
( cd "$PROJ" && "$PY" "$ROOT/scripts/install-agent-hooks.py" claude --target "$PROJ" >/dev/null 2>&1 )
( cd "$PROJ" && "$PY" "$ROOT/scripts/install-agent-hooks.py" claude --target "$PROJ" >/dev/null 2>&1 )
python - "$PROJ/.claude/settings.json" <<'PY' && ok "claude installer idempotent, foreign hooks preserved" || bad "claude installer merge wrong"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
h = d["hooks"]
assert any("foreign-hook" in x["hooks"][0]["command"] for x in h["SessionStart"]), "foreign lost"
pc = [g for g in h["PostCompact"] if "compact-archive" in g["hooks"][0]["command"]]
ups = [g for g in h["UserPromptSubmit"] if "session-recall" in g["hooks"][0]["command"]]
assert len(pc) == 1 and len(ups) == 1, f"managed dup: {len(pc)}/{len(ups)}"
PY

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
