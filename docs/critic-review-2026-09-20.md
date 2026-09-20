# Harness Critic Iteration Review · 第三轮（2026-09-20）

> 对象：compact-recall 模块事故加固的全部未提交改动（基线 commit `28d067d`，含当日 System32 归档事故的热修 + TDD 加固）。
> 方法：1 个对抗式 coder 审查 agent（明确要求"论断必须实测复现，禁止凭读码断言"），实施方对每条发现走红→绿修复后复验；审查范围覆盖 5 个 agent 适配面（kimi/claude/codex/pi/opencode）、安装器契约、测试盲区与文档一致性。
> 结论先行：**0 个 P0；2 个 P1 均当日修复并固化为回归用例**；P2 采纳 6 项、记录性遗留 2 项。本轮最有价值的发现是"`--check` 医生自己会误报"与"相对路径 cwd 绕过防线"——两者都通过了 27/27 全绿的冒烟，再次验证"测试全绿 ≠ 无盲区"。

## 一、P1 发现（均当日修复，红→绿）

### P1-1 `--check` 针脚扫描不限受管块 → 外来 hook 触发假 DRIFT（审查 agent 实测复现）
- `scripts/install-agent-hooks.py`（修复前行 186–189）：在**整个** `config.toml` 找第一条含 `compact-archive`/`session-recall` + `command` 的行。实测：受管块之前放一条外来 `command = 'node ".../my-compact-archive-bridge/hook.mjs"'` → `--check` 误报 `DRIFT managed command not hosted` 且 exit 1。
- 为什么重要：医生的职业病是误报——假阳性会训练用户忽略真漂移。
- 修复：扫描范围限定 `KIMI_MARK_BEGIN/END` 之间的受管块行；同时补事件名完整性校验（缺 `PostCompact`/`UserPromptSubmit` 即 DRIFT）、路径比对改大小写不敏感（Windows 大小写不敏感文件系统）、空命令行改为明确的 `managed command missing`。
- 回归：冒烟用例 18（外来词不误报），红（rc=1）→绿（rc=0）。

### P1-2 相对路径 payload `cwd` 绕过"禁用 os.getcwd()"防线（审查 agent 实测复现）
- `resolve_cwd()`（两脚本同构）：`Path(raw).is_dir()` 对相对路径成立时按**进程 cwd 锚定**解析——恰好复活了事故的写错位模式，只是入口从"缺 cwd"变成"给相对 cwd"。实测：从主目录喂 `cwd: "kimi-relcwd-probe"`，归档写入进程 cwd 锚定路径。
- 修复：payload `cwd` 非绝对路径一律拒绝（记 stderr 后落入 `session_index workDir` 链），两个脚本同步修改。
- 回归：冒烟用例 19（相对 cwd + workDir 在位 → workDir 胜出、进程 cwd 下零写入），红→绿。

## 二、P1 级流程发现（已闭合）

### P1-3 加固特性从未跑过真实压缩，issue 文档的"结果"超前于证据
- 审查 agent 实证：实机 `conversations/.state/` 有 recall marker 但**无 `archive-log.jsonl`**；真实归档 `session_title` 为空——即那是热修代码的重放产物，回执/标题代码从未接触真实数据。
- 闭合：刷新寄宿副本后用真实会话数据重放（无 cwd payload、从主目录执行）——归档重生成且 `session_title` 带上真实会话标题（取自 `state.json` 的策展 `title`），回执首条实机落盘，索引去重 `unchanged` 符合设计。issue 文档"结果"节已改写为与证据对齐。

### P1-4 codex/claude 真实 payload 键集仍是"假设契约"（计划反思 #3 的未机械化残留）
- 冒烟用例 7 给 codex 喂的是合成 `cwd`——验证的是假设而非真实契约；若 codex 实际不发 `cwd`，该面将从"getcwd 兜底碰巧可用"变为"fail-open"。
- 处置：本轮无法在无 codex/claude 实机会话的前提下采集真实键集，记入 issue 文档遗留项（采集键集后补无-cwd 用例）。**这是遗留项，不是已修复项。**

## 三、P2 采纳与遗留

| # | 发现 | 处置 |
|---|---|---|
| P2-1 | 去重重跑产生重复回执（1 文件 3 行） | 保留 append-always，明确为**事件日志语义**并写入 README（索引有 200 行帽，回执无帽是本地 gitignored 数据） |
| P2-2 | 用例 17 首断言是 `set -e` 下的死分支（审查 agent 用探针脚本实证） | 改 `if ( ... ); then` 模式（本轮绿跑中曾实际踩中该中断） |
| P2-3 | 用例 13 第二断言永假（vacuous） | 改断言 `$BOGUS/conversations` 不存在 |
| P2-4 | `extract_title` 应优先 `state.json` 的策展 `title` 而非 `lastPrompt`（实机 state.json 两者皆有） | 采纳：title 优先、lastPrompt 兜底；用例 16 改写后红→绿 |
| P2-5 | `__pycache__/` 不在 `.gitignore` | 已加 `__pycache__/`、`*.pyc` |
| P2-6 | README 标题回退表述过宽、issue 用例计数含混 | 已精确化（kimi wire 流限定、用例 13–19 共 7 条） |
| 遗留 A | 从不同 checkout 跑 `--check` 会与该 checkout 的脚本比哈希 | 属寄宿模型的固有语义（"与**本**仓库源一致"），重跑安装器即消除；暂不加复杂度 |
| 遗留 B | 归档文件与索引行需同提交 | 记入 issue 文档提交注意项（本轮不提交） |

## 四、验证证据（审查 agent + 实施方各自实测）

| 命令/复现 | 结果 |
|---|---|
| `bash tests/compact-recall-smoke.sh`（终态） | 29 passed, 0 failed |
| `tests/install-smoke.sh` / `tests/trigger-smoke.sh` | PASS / PASS |
| `install-agent-hooks.py kimi --check`（实机） | ok，rc=0 |
| 外来 `compact-archive` 词命令 + `--check` | 修复前 rc=1 假 DRIFT → 修复后 rc=0 |
| 相对 cwd payload（外进程 cwd 下） | 修复前按进程 cwd 落盘 → 修复后拒绝并走 workDir，零写入 |
| 不可解析会话（无 cwd、不在索引、带内联摘要） | fail-open rc=0，零写入（fail-open 优先于摘要提取） |
| 重复 sessionId 条目 / cwd 指向文件 / 畸形 JSONL / workDir 不存在 | 最后一 条为准 / 落空 / 跳过 / fail-open |
| `extract_title` 矩阵（数值/CRLF/dict/空/500 字） | 全部正确，100 字符帽生效 |
| `git check-ignore conversations/.state/` | 命中 `.gitignore` |
| 真实会话重放（寄宿脚本、无 cwd） | 归档带真实 title + 回执实机落盘 + index unchanged |

## 五、元结论

本轮加固的起点本身就是第二轮评审 P0 的回声（"测试全绿但主路径已断"）：System32 事故在 27/27 全绿的冒烟眼皮底下发生了两周内的第一次真实压缩。它给出的永久解药有三层——**把事故成因逐条变成用例**（本轮 7 条新用例全部对应一个具体失败模式）、**给静默成功装黑匣子**（回执 + `--check`，让"归档到哪了"随时可问）、**让文档契约降级为"待验证假设"直到实测**（codex/claude 键集遗留项即此姿态的产物）。critic 审查再次证明自己的价格：两处 P1 都是"新增防线上的新漏洞"，单靠实现者自查不可见。
