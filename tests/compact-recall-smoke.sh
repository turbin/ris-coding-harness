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

# 6) claude PostCompact payload (compact_summary delivered inline; real claude
#    payloads carry cwd — see issues/2026-09-20-hook-payload-cwd-fallback)
printf '%s' '{"hook_event_name":"PostCompact","session_id":"sess-claude","session_title":"c","trigger":"manual","compact_summary":"claude 直接携带的摘要。","cwd":"'"$PROJ"'"}' \
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

# 10) kimi installer: hooks hosted under $KIMI_CODE_HOME/hooks (no project
# path dependency — issues/2026-09-19-kimi-hooks-project-path), idempotent,
# foreign [[hooks]] entries preserved.
printf '%s\n' '[loop_control]' 'max_attempts_per_step = 3' '' \
  '[[hooks]]' 'event = "PostCompact"' \
  'command = "node \"E:/workspace/some-other/scripts/hook.mjs\""' 'timeout = 30' \
  > "$FAKE_HOME/config.toml"
( cd "$PROJ" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/install-agent-hooks.py" kimi --target "$PROJ" >/dev/null 2>&1 )
( cd "$PROJ" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/install-agent-hooks.py" kimi --target "$PROJ" >/dev/null 2>&1 )
n="$(grep -c '>>> managed by ris-coding-harness: compact-recall' "$FAKE_HOME/config.toml")"
[ "$n" -eq 1 ] && ok "kimi managed block unique after re-install" || bad "kimi managed block duplicated (n=$n)"
grep -q 'some-other/scripts/hook.mjs' "$FAKE_HOME/config.toml" \
  && ok "kimi foreign hook preserved" || bad "kimi foreign hook lost"
grep -q 'hooks/compact-archive' "$FAKE_HOME/config.toml" \
  && ok "kimi command points at user-level hooks dir" || bad "kimi command not hosted in hooks dir"
if grep -q "$PROJ" "$FAKE_HOME/config.toml"; then
  bad "kimi config still references a project path"
else
  ok "kimi config free of project paths"
fi
khooks_ok=1
for f in compact-archive.sh compact-archive.ps1 compact-archive.py session-recall.sh session-recall.ps1 session-recall.py; do
  [ -f "$FAKE_HOME/hooks/$f" ] || khooks_ok=0
done
[ "$khooks_ok" -eq 1 ] && ok "6 hook scripts copied to KIMI_CODE_HOME/hooks" || bad "hook scripts missing in KIMI_CODE_HOME/hooks"

# 11) PostCompact WITHOUT payload cwd: project must be resolved via
#     session_index workDir; os.getcwd() fallback is forbidden
#     (issues/2026-09-20-hook-payload-cwd-fallback). Run from a neutral dir
#     with no conversations/ so a getcwd fallback can't pass by accident.
SESSION_ID2="session_aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
SESSION_DIR2="$FAKE_HOME/sessions/wd_fake_998877665544/$SESSION_ID2"
mkdir -p "$SESSION_DIR2/agents/main"
printf '%s\n' \
  '{"type":"full_compaction.begin","source":"manual","time":1767398400000}' \
  '{"type":"context.apply_compaction","summary":"无 cwd payload 用例：workDir 解析回归。"}' \
  '{"type":"full_compaction.complete","time":1767398401000}' \
  > "$SESSION_DIR2/agents/main/wire.jsonl"
printf '%s\n' "{\"sessionId\":\"$SESSION_ID2\",\"sessionDir\":\"$SESSION_DIR2\",\"workDir\":\"$PROJ\"}" \
  >> "$FAKE_HOME/session_index.jsonl"
NEUTRAL="$WORK/no-cwd-sandbox"
mkdir -p "$NEUTRAL"
OUT="$(printf '%s' "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"$SESSION_ID2\",\"session_title\":\"smoke\"}" \
  | ( cd "$NEUTRAL" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" 2>&1 ) )"
if [ -f "$PROJ/conversations/archive/$SESSION_ID2/2026-01-03T00-00-00Z.md" ] \
  && grep -q "workDir 解析回归" "$PROJ/conversations/archive/$SESSION_ID2/2026-01-03T00-00-00Z.md"; then
  ok "no-cwd archive lands in session_index workDir project"
else
  bad "no-cwd archive lost (output: $OUT)"
fi
if [ -e "$NEUTRAL/conversations" ]; then
  bad "archive fell back to os.getcwd() (neutral cwd polluted)"
else
  ok "archive has no os.getcwd() fallback"
fi
grep -q "archive/$SESSION_ID2/2026-01-03T00-00-00Z.md" \
  "$PROJ/conversations/.state/archive-log.jsonl" 2>/dev/null \
  && ok "archive receipt appended" \
  || bad "archive receipt missing"

# 12) UserPromptSubmit WITHOUT payload cwd: recall still briefs via workDir
R5="$(printf '%s' "{\"hook_event_name\":\"UserPromptSubmit\",\"session_id\":\"$SESSION_ID2\"}" \
  | ( cd "$NEUTRAL" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/session-recall.py" 2>/dev/null ) )"
case "$R5" in
  *对话归档简报*) ok "no-cwd recall briefs via session_index workDir" ;;
  *) bad "no-cwd recall silent (got: ${R5:0:60})" ;;
esac

# 13) payload cwd bogus + session_index workDir -> workDir wins, bogus untouched
BOGUS="$WORK/bogus-cwd"
mkdir -p "$BOGUS"
OUT="$(printf '%s' "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"$SESSION_ID2\",\"session_title\":\"smoke\",\"cwd\":\"$BOGUS/does-not-exist\"}" \
  | ( cd "$NEUTRAL" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" 2>&1 ) )"
if [ -f "$PROJ/conversations/archive/$SESSION_ID2/2026-01-03T00-00-00Z.md" ]; then
  ok "bogus payload cwd falls through to session_index workDir"
else
  bad "bogus cwd broke resolution (output: $OUT)"
fi
[ ! -e "$BOGUS/conversations" ] && ok "bogus cwd never written" \
  || bad "archive wrote under bogus cwd"

# 14) unresolvable (unknown session, no cwd) -> fail-open, refuse getcwd, write nothing
OUT="$(printf '%s' '{"hook_event_name":"PostCompact","session_id":"sess-unknown-xyz","session_title":"c","compact_summary":"孤儿会话摘要。"}' \
  | ( cd "$NEUTRAL" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" 2>&1 ) )"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -e "$NEUTRAL/conversations" ]; then
  ok "unresolvable project fail-opens without writing"
else
  bad "unresolvable project misbehaved (rc=$rc, output: $OUT)"
fi

# 15) relative workDir in session_index -> resolved against KIMI_CODE_HOME
SESSION_ID3="session_77777777-8888-9999-aaaa-bbbbbbbbbbbb"
SESSION_DIR3="$FAKE_HOME/sessions/wd_fake_121212121212/$SESSION_ID3"
mkdir -p "$SESSION_DIR3/agents/main"
printf '%s\n' \
  '{"type":"full_compaction.begin","source":"manual","time":1767484800000}' \
  '{"type":"context.apply_compaction","summary":"相对 workDir 解析用例。"}' \
  '{"type":"full_compaction.complete","time":1767484801000}' \
  > "$SESSION_DIR3/agents/main/wire.jsonl"
printf '%s\n' "{\"sessionId\":\"$SESSION_ID3\",\"sessionDir\":\"$SESSION_DIR3\",\"workDir\":\"relative-proj\"}" \
  >> "$FAKE_HOME/session_index.jsonl"
mkdir -p "$FAKE_HOME/relative-proj"
printf '%s' "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"$SESSION_ID3\"}" \
  | ( cd "$NEUTRAL" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" >/dev/null 2>&1 )
[ -f "$FAKE_HOME/relative-proj/conversations/archive/$SESSION_ID3/2026-01-04T00-00-00Z.md" ] \
  && ok "relative workDir resolves against KIMI_CODE_HOME" \
  || bad "relative workDir not resolved"

# 16) title fallback from state.json lastPrompt when payload has no title
SESSION_ID4="session_55555555-6666-7777-8888-999999999999"
SESSION_DIR4="$FAKE_HOME/sessions/wd_fake_343434343434/$SESSION_ID4"
mkdir -p "$SESSION_DIR4/agents/main"
printf '%s\n' '{"id":"'"$SESSION_ID4"'","cwd":"'"$PROJ"'","title":"策展标题：compact-recall 加固验证","lastPrompt":"验证一下是否产生摘要信息，并成功落盘\n第二行不应出现"}' \
  > "$SESSION_DIR4/state.json"
printf '%s\n' \
  '{"type":"full_compaction.begin","source":"manual","time":1767571200000}' \
  '{"type":"context.apply_compaction","summary":"标题回退用例摘要。"}' \
  '{"type":"full_compaction.complete","time":1767571201000}' \
  > "$SESSION_DIR4/agents/main/wire.jsonl"
printf '%s\n' "{\"sessionId\":\"$SESSION_ID4\",\"sessionDir\":\"$SESSION_DIR4\",\"workDir\":\"$PROJ\"}" \
  >> "$FAKE_HOME/session_index.jsonl"
printf '%s' "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"$SESSION_ID4\"}" \
  | ( cd "$NEUTRAL" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" >/dev/null 2>&1 )
if grep -q "session_title: 策展标题：compact-recall 加固验证" \
  "$PROJ/conversations/archive/$SESSION_ID4/2026-01-05T00-00-00Z.md"; then
  ok "title prefers state.json title over lastPrompt"
else
  bad "title preference missing"
fi

# 17) kimi --check: clean after install, drift after tampering
if ( cd "$PROJ" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/install-agent-hooks.py" kimi --check >/dev/null 2>&1 ); then
  ok "kimi --check clean after install"
else
  bad "kimi --check not clean after install"
fi
echo "# tampered" >> "$FAKE_HOME/hooks/session-recall.py"
CHK_RC=0
CHK_OUT="$( cd "$PROJ" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/install-agent-hooks.py" kimi --check 2>&1 )" || CHK_RC=$?
if [ "$CHK_RC" -eq 1 ] && grep -q "session-recall.py" <<<"$CHK_OUT"; then
  ok "kimi --check reports drifted hosted copy (rc=1)"
else
  bad "kimi --check missed drift (rc=$CHK_RC, out: ${CHK_OUT:0:80})"
fi

# 18) --check scan is scoped to the managed block: a foreign command that
#     merely mentions compact-archive must not trigger DRIFT
printf '%s\n' '[loop_control]' 'max_attempts_per_step = 3' '' \
  '[[hooks]]' 'event = "Notification"' \
  'command = "node \"E:/tools/my-compact-archive-bridge/hook.mjs\""' 'timeout = 30' \
  > "$FAKE_HOME/config.toml"
( cd "$PROJ" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/install-agent-hooks.py" kimi --target "$PROJ" >/dev/null 2>&1 )
FK_RC=0
FK_OUT="$( cd "$PROJ" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/install-agent-hooks.py" kimi --check 2>&1 )" || FK_RC=$?
if [ "$FK_RC" -eq 0 ]; then
  ok "foreign compact-archive command does not trigger DRIFT"
else
  bad "foreign needle command false-positives DRIFT (rc=$FK_RC, out: ${FK_OUT:0:100})"
fi

# 19) relative payload cwd must be rejected (non-absolute = untrusted anchor)
REL="$NEUTRAL/relative-dir-probe"
mkdir -p "$REL"
printf '%s' "{\"hook_event_name\":\"PostCompact\",\"session_id\":\"$SESSION_ID2\",\"session_title\":\"smoke\",\"cwd\":\"relative-dir-probe\"}" \
  | ( cd "$NEUTRAL" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/compact-archive.py" >/dev/null 2>&1 )
if [ -f "$PROJ/conversations/archive/$SESSION_ID2/2026-01-03T00-00-00Z.md" ] && [ ! -e "$REL/conversations" ]; then
  ok "relative payload cwd rejected, session_index workDir used"
else
  bad "relative payload cwd accepted as project root (process-cwd anchored write)"
fi

echo
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
