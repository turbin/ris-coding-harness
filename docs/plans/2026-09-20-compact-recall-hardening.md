# compact-recall 加固 Implementation Plan

> **状态：已执行完毕（2026-09-20）。** 两轮 TDD 红绿 + 一轮 critic 迭代审查，终态冒烟 29/29、install/trigger PASS；审查结论与残留项见 `docs/critic-review-2026-09-20.md` 与 `issues/2026-09-20-hook-payload-cwd-fallback.md`。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 compact-recall 的 PostCompact 归档从"静默失败/静默写错"变为"可观测、可自检、可回归"，并把本次 System32 事故的每个成因固化成永久测试。

**Architecture:** 沿用现有双脚本（compact-archive.py / session-recall.py）+ 安装器（install-agent-hooks.py）结构，不新增运行时组件：归档成功后追加本地回执（archive-log.jsonl），标题缺失时从 state.json 回退，安装器新增 kimi `--check` 漂移自检（寄宿副本哈希 vs 仓库源 + 受管块指向校验）。

**Tech Stack:** Python 3 标准库（json/hashlib/pathlib）、bash 冒烟（tests/compact-recall-smoke.sh）。

**Spec:** `issues/2026-09-20-hook-payload-cwd-fallback.md`（事故定档）+ 本计划"反思"节。

## 反思：为什么监视 compact 的 hook 没有成功

1. **契约过度信任 + 最不可靠的兜底**：脚本写的是 `payload.cwd or os.getcwd()`。官方文档承诺 payload 带 `cwd`，实测当前 CLI 不带；而 `os.getcwd()` 在服务进程拉起的场景下是 System32。兜底链的最后一环恰恰是最可能错的环节，且错得无声（文件照样写出，exit 0）。
2. **失败模式是"假成功"而非"显式失败"**：fail-open 设计（正确）缺少配套的可观测面——归档写到哪、成功与否，没有任何持久痕迹，直到用户问"落盘了吗"才暴露。fail-open 必须"失败可诊断"，否则等于埋雷。
3. **测试验证的是"假设的契约"而非"真实的契约"**：冒烟全部显式传 cwd 且从工程目录起跑——恰好绕开了真实 CLI 的两个行为（无 cwd、异根 cwd）。合成测试全绿 ≠ 主路径可用（与 09-13 critic P0 的教训同构）。
4. **已知缺口没有被机制化**：设计上早知道"首次真实 /compact 才算端到端实证"，但停留为人工注意事项，没有任何自动化去核对"最近一次压缩是否归档进正确工程"。
5. **寄宿副本无漂移检测**：修复仓库脚本后必须手动重跑安装器刷新 `~/.kimi-code/hooks/`，没有任何机制发现"仓库已修、寄宿仍旧"的漂移。

**应优化的模块**：`compact-recall` 模块（`scripts/compact-archive.py`、`scripts/session-recall.py`、`scripts/install-agent-hooks.py` 的 kimi 面 + `tests/compact-recall-smoke.sh`）。对策映射：静默写错→回执+`--check`；契约漂移→载荷变体矩阵；元数据缺失→标题回退。

## Global Constraints

- 仅 Python 标准库；不新增任何依赖、不新增运行时脚本文件。
- hook 脚本全程 fail-open：任何错误 exit 0，不影响主流程；禁止在 hook 脚本中使用 `os.getcwd()` 定位工程。
- `install.sh`、`evals/**` 等属 `policy.yaml` protected files，本计划不触碰。
- 用户约束：不主动 git commit（用户明确下令才提交），故任务步骤不含 commit。
- 完成定义：`tests/compact-recall-smoke.sh`、`tests/install-smoke.sh`、`tests/trigger-smoke.sh` 全绿 + 实机 `kimi --check` ok + 真实寄宿脚本 E2E 归档进工程。

---

### Task 1: resolve_cwd 载荷变体矩阵（契约固化）

**Files:**
- Modify: `tests/compact-recall-smoke.sh`（用例 12 之后追加 13–15）

**Interfaces:**
- Consumes: `scripts/compact-archive.py` 现有 CLI（stdin payload、`KIMI_CODE_HOME`）、`resolve_cwd` 行为：payload cwd（合法目录）→ session_index workDir（相对路径按 KIMI_CODE_HOME 解析）→ None=fail-open。
- Produces: 用例 13–15 固化三条解析规则，后续任务回归时不得破坏。

- [ ] **Step 1: 写三条用例（13 篡改 cwd、14 不可解析 fail-open、15 相对 workDir）**

```bash
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
[ ! -e "$BOGUS/does-not-exist/conversations" ] && ok "bogus cwd never written" \
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
```

- [ ] **Step 2: 运行冒烟**

Run: `bash tests/compact-recall-smoke.sh`
Expected: 三条新用例全绿（契约已由上一轮修复实现；若红=真 bug，最小修复后复绿）。

### Task 2: 归档回执 archive-log.jsonl（可观测面）

**Files:**
- Modify: `tests/compact-recall-smoke.sh`（用例 11 追加回执断言）
- Modify: `scripts/compact-archive.py`（`update_index` 成功后追加回执）

**Interfaces:**
- Consumes: `now_iso()`、`conv`、`rel`、`time_iso`、`session_id`（main() 现有局部量）。
- Produces: `<conv>/.state/archive-log.jsonl`，每行 `{"archived_at","compact_time","session","file"}`；后续排障与 critic 审查以此为准。

- [ ] **Step 1: 先加失败断言（用例 11 末尾）**

```bash
grep -q "archive/$SESSION_ID2/2026-01-03T00-00-00Z.md" \
  "$PROJ/conversations/.state/archive-log.jsonl" 2>/dev/null \
  && ok "archive receipt appended" \
  || bad "archive receipt missing"
```

- [ ] **Step 2: 跑冒烟确认红**

Run: `bash tests/compact-recall-smoke.sh`
Expected: FAIL - archive receipt missing（其余不受影响）

- [ ] **Step 3: 最小实现（compact-archive.py，`update_index` 之后、最终 log 之前）**

```python
    try:
        state_dir = conv / ".state"
        state_dir.mkdir(parents=True, exist_ok=True)
        receipt = {
            "archived_at": now_iso(),
            "compact_time": time_iso,
            "session": session_id or "unknown",
            "file": f"conversations/{rel}",
        }
        with (state_dir / "archive-log.jsonl").open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(receipt, ensure_ascii=False) + "\n")
    except OSError as exc:
        log(f"cannot append archive receipt: {exc}")
```

- [ ] **Step 4: 跑冒烟确认绿**

Run: `bash tests/compact-recall-smoke.sh`
Expected: 全绿（含 receipt 断言）

### Task 3: 标题回退（state.json lastPrompt）

**Files:**
- Modify: `scripts/compact-archive.py`（新增 `extract_title()`；wire 分支中 `title` 为空时回退）
- Modify: `tests/compact-recall-smoke.sh`（用例 16）

**Interfaces:**
- Consumes: `find_wire()` 返回的 wire 路径（`<sessionDir>/agents/main/wire.jsonl`）；`<sessionDir>/state.json` 的 `lastPrompt` 字段（实测存在）。
- Produces: `extract_title(wire) -> str`（首行、压空白、截断 100 字符）；front matter `session_title` 不再为空。

- [ ] **Step 1: 新增 extract_title（放在 extract_compaction 之后）**

```python
def extract_title(wire):
    """Fallback session title when the payload lacks one: first line of the
    session state.json lastPrompt, whitespace-collapsed, capped at 100 chars."""
    state = wire.parent.parent.parent / "state.json"
    try:
        data = json.loads(state.read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError):
        return ""
    first = str(data.get("lastPrompt") or "").strip().splitlines()
    if not first or not first[0].strip():
        return ""
    return re.sub(r"\s+", " ", first[0].strip())[:100]
```

- [ ] **Step 2: wire 分接入参（main() 内，`wire_ref = ...` 赋值处之后）**

```python
                    if not title:
                        title = extract_title(wire)
```

- [ ] **Step 3: 用例 16（先写测试跑红再实现亦可，此处按实现顺序）**

```bash
# 16) title fallback from state.json lastPrompt when payload has no title
SESSION_ID4="session_55555555-6666-7777-8888-999999999999"
SESSION_DIR4="$FAKE_HOME/sessions/wd_fake_343434343434/$SESSION_ID4"
mkdir -p "$SESSION_DIR4/agents/main"
printf '%s\n' '{"id":"'"$SESSION_ID4"'","cwd":"'"$PROJ"'","lastPrompt":"验证一下是否产生摘要信息，并成功落盘\n第二行不应出现"}' \
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
if grep -q "session_title: 验证一下是否产生摘要信息，并成功落盘" \
  "$PROJ/conversations/archive/$SESSION_ID4/2026-01-05T00-00-00Z.md"; then
  ok "title falls back to state.json lastPrompt first line"
else
  bad "title fallback missing"
fi
```

- [ ] **Step 4: 全量冒烟**

Run: `bash tests/compact-recall-smoke.sh`
Expected: 全绿

### Task 4: 安装器 kimi `--check` 漂移自检

**Files:**
- Modify: `scripts/install-agent-hooks.py`（argparse `--check`；新增 `check_kimi()`）
- Modify: `tests/compact-recall-smoke.sh`（用例 17）

**Interfaces:**
- Consumes: `KIMI_HOOK_FILES`、`KIMI_MARK_BEGIN`、`SCRIPT_DIR`、`fwd()`（安装器现有符号）。
- Produces: `install-agent-hooks.py kimi --check` → 干净 exit 0 打印 `ok`；漂移 exit 1 逐条打印 `DRIFT ...`；非 kimi agent 带 `--check` → exit 2。

- [ ] **Step 1: check_kimi 实现（放在 install_kimi 之后）**

```python
def check_kimi():
    """Verify installed state instead of installing: hosted scripts must
    byte-match the repo sources and the managed block must point at the
    user-level hooks dir. Exit 0 clean, 1 drift."""
    import hashlib
    home = Path(os.environ.get("KIMI_CODE_HOME") or (Path.home() / ".kimi-code"))
    hooks_dir = home / "hooks"
    problems = []
    for name in KIMI_HOOK_FILES:
        src, dst = SCRIPT_DIR / name, hooks_dir / name
        if not src.is_file():
            problems.append(f"source missing: {src}")
            continue
        if not dst.is_file():
            problems.append(f"hosted copy missing: {dst} (re-run: install-agent-hooks.py kimi)")
            continue
        if hashlib.sha256(src.read_bytes()).hexdigest() != hashlib.sha256(dst.read_bytes()).hexdigest():
            problems.append(f"hosted copy drifted from repo: {dst} (re-run: install-agent-hooks.py kimi)")
    cfg = home / "config.toml"
    text = cfg.read_text(encoding="utf-8", errors="replace") if cfg.is_file() else ""
    if KIMI_MARK_BEGIN not in text:
        problems.append(f"managed block missing in {cfg}")
    else:
        for needle in ("compact-archive", "session-recall"):
            line = next((l for l in text.splitlines() if needle in l and "command" in l), "")
            if fwd(hooks_dir) not in line:
                problems.append(f"managed command not hosted in {hooks_dir}: {line.strip()}")
    if problems:
        for p in problems:
            log(f"kimi check: DRIFT {p}")
        return 1
    log("kimi check: ok (hosted scripts match repo; managed block points at user-level hooks dir)")
    return 0
```

- [ ] **Step 2: main() 接线（target 校验之前）**

```python
    ap.add_argument("--check", action="store_true",
                    help="verify installed state instead of installing (kimi only)")
    args, _unknown = ap.parse_known_args()

    if args.check:
        if args.agent == "kimi":
            return check_kimi()
        log(f"{args.agent}: --check is not supported yet")
        return 2
```

- [ ] **Step 3: 用例 17（用例 10 的 fake home 之后追加）**

```bash
# 17) kimi --check: clean after install, drift after tampering
( cd "$PROJ" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/install-agent-hooks.py" kimi --check >/dev/null 2>&1 )
[ $? -eq 0 ] && ok "kimi --check clean after install" || bad "kimi --check not clean after install"
echo "# tampered" >> "$FAKE_HOME/hooks/session-recall.py"
CHK_OUT="$(cd "$PROJ" && KIMI_CODE_HOME="$FAKE_HOME" "$PY" "$ROOT/scripts/install-agent-hooks.py" kimi --check 2>&1)"
CHK_RC=$?
if [ "$CHK_RC" -eq 1 ] && grep -q "session-recall.py" <<<"$CHK_OUT"; then
  ok "kimi --check reports drifted hosted copy (rc=1)"
else
  bad "kimi --check missed drift (rc=$CHK_RC, out: ${CHK_OUT:0:80})"
fi
```

- [ ] **Step 4: 先跑红（--check 未接线时被 parse_known_args 忽略→当安装跑，篡改用例 rc=0）再实现复绿**

Run: `bash tests/compact-recall-smoke.sh`
Expected: 实现前 tamper 用例红（rc=0），实现后全绿

### Task 5: 实机刷新 + 真实自检 + 文档同步

**Files:**
- Modify: `README.md`（§5 机制 bullet 追加自检命令）
- Modify: `issues/2026-09-20-hook-payload-cwd-fallback.md`（追加"后续加固"节）

- [ ] **Step 1:** `python scripts/install-agent-hooks.py kimi --target .`（刷新实机寄宿副本，带回执/标题能力）
- [ ] **Step 2:** `python scripts/install-agent-hooks.py kimi --check` → 期望 exit 0 `ok`
- [ ] **Step 3:** README §5 追加：`python scripts/install-agent-hooks.py kimi --check` 自检说明
- [ ] **Step 4:** issue #6 追加加固记录；三套冒烟（compact-recall / install / trigger）全绿

### Task 6: critic iteration review（对抗性全工程影响审查）

**Files:**
- Create: `docs/critic-review-2026-09-20.md`（沿用 09-13 格式：P0/P1/P2 + file:line + 元结论）

- [ ] **Step 1:** 派发 coder 子代理：以只读方式审查本轮+上轮全部未提交改动（git diff + 新文件）对全工程的影响（安装器契约、claude/codex/pi/opencode 四适配面、冒烟盲区、文档与实现一致性、回执的隐私/膨胀面、--check 的误报面），论断须实测或推演并附 file:line。
- [ ] **Step 2:** 按发现迭代修复（P0 立即、P1 评估后修、P2 记录），每轮修复后跑三冒烟。
- [ ] **Step 3:** 写 `docs/critic-review-2026-09-20.md`：轮次、发现、修复、残留、元结论。

## Self-Review

- 覆盖：反思 5 条成因 → Task 2/4（可观测+漂移）、Task 1（契约矩阵）、Task 3（元数据）、Task 6（第三方对抗复核）。无遗漏条目。
- 占位符：无 TBD/TODO；所有步骤含实际代码/命令。
- 符号一致性：`extract_title(wire)`、`check_kimi()`、回执键名在各任务间一致；`SESSION_ID2/3/4` 与既有 `SESSION_ID` 不冲突；用例 15/16 的 archive 时间戳（01-04/01-05）互不相同、不与既有用例（01-01~01-03）冲突。
