# 2026-09-24-failure-reflection-loop — 任务失败反思回路设计裁决

- 来源：用户 2026-09-24 需求「多数据源调研 claude code / kimi code / codex / pi 的
  任务结束判败与反思 hook 能力」→ 问卷移交 GPT → GPT 两轮设计裁决稿 →
  苏格拉底四问逐项收集（1-E / 2-C / 3-A / 4-D）→ 用户指示「按照 gpt 回答继续
  后续的工作」确认采纳。
- 目标层：L3（harness 机制：`scripts/` 新管道 + `install-agent-hooks.py` 注册扩展 +
  rsi-loop 协议字段）；按 M0–M10 分阶段落地，各阶段按实际触碰层补充验证记录。
- 状态：adopted（设计裁决已确认；实施自 M0 起步）

## 动机

RSI 闭环已有批处理失败数据（`evals/results/` verdict + `progress/retro/` 聚合），
但缺少「单次失败事件」在线层：任务在 agent 会话内失败时，没有统一的判败 → 当场反思 →
归档 → 下一任务回注通道，失败样本依赖 eval 跑批才被捕获。四家 agent（Claude Code、
Kimi Code、Codex、Pi）经调研均具备「结束边界 hook + 阻断续跑 + 注入反思」的原生能力
（Claude/Codex `Stop` block+reason；Kimi `Stop` exit 2+stderr；Pi
`agent_before_settle` 返回 entries+continue），且本仓库 compact-recall 管道已验证
「事件触发 → 落盘 → 回注」全链路可行——新回路是同一管道模式的延伸。

## 总体原则

1. Tool failure ≠ Task failure（工具错误只是证据）。
2. Failure record ≠ Reflection ≠ Lesson（事实、解释、经验分层保存）。
3. Hook ≠ Scheduler（hook 只观察/阻断/注入；切任务永远归编排器）。
4. Common core first, provider enhancement second（四家统一最小公共契约，
   Claude/Codex 的 LLM hook 仅作增强，不得进入公共路径必要依赖）。

三不变量：`Tool error ≠ Task failure`；`Reflection ≠ Verified knowledge`；
`Agent ≠ Task scheduler`。

统一 terminal outcome 五态：`success` / `task_failure` / `infra_failure` /
`cancelled` / `indeterminate`；仅 `task_failure` 默认进入在线反思候选。

## 裁决清单（GPT 设计稿 DEC-FR-001~015，经用户采纳）

| ID | 裁决 |
|---|---|
| DEC-FR-001 | 五态 failure taxonomy；工具错误不等于 task failure |
| DEC-FR-002 | 判败权威优先级：verdict > 验收证据 > task state > 最终表态启发式；LLM judge 仅增强且只能 indeterminate→suspected |
| DEC-FR-003 | 在线反思预算：每 task ≤2 次、每 reflection_fingerprint ≤1 次；terminal failure 100% 归档；仅 actionable+recoverable 的 task_failure 才 block+reflect |
| DEC-FR-004 | 反思结构化字段：失败事实/证据/根因分类/可控性/错误假设/修正动作/一句话 lesson/issue_candidate/confidence；不设「粗心」类根因 |
| DEC-FR-005 | 新建 `failures/`：单次失败事实 + 当场反思；与 `conversations/`（原文）、`issues/`（可复现缺陷）、`progress/retro/`（跨任务聚合）职责分离 |
| DEC-FR-006 | `failure_record/v1` schema（YAML frontmatter + Markdown 正文）；与 verdict 对齐 run_id/task_id/attempt/agent/terminal_state 公共键但不复用 schema |
| DEC-FR-007 | Failure 必记、Issue 条件创建（可复现 AND 值得独立跟踪）；双向只存 reference 不复制正文 |
| DEC-FR-008 | 回注语义统一为 `before_task_start`（≠ SessionStart）；Claude/Kimi/Codex 以 UserPromptSubmit 为 transport 并按 task 去重；Pi 用 before_agent_start |
| DEC-FR-009 | 回注预算：Top 3~5 条、默认 800 tokens、硬上限 1200；按相关性/状态/复发/时间筛选；MVP 不上 embedding |
| DEC-FR-010 | Lesson 生命周期 open/closed/merged_to_retro/stale；年龄只降权不自动删除；同 fingerprint 再现则 reopen |
| DEC-FR-011 | 无人值守模式 rsi-loop 是唯一 scheduler；agent 只能报告状态，无权选下一 task |
| DEC-FR-012 | Transition Gate（≠ RSI GATE）：无人值守须 success OR failure archived OR cancellation recorded 才可推进；交互模式软门禁；配 emergency spool 防死锁 |
| DEC-FR-013 | 跨 agent 契约五角色 Trigger/Reflect/Archive/Recall + Transition（编排层）；provider hook 仅 adapter；provider 元数据进 `extensions.*` 可选字段 |
| DEC-FR-014 | hook 层 fail-open 可接受，系统层 silent loss 不可接受；必须有 reconcile-failures（deterministic failure id 防双写） |
| DEC-FR-015 | 不建第二套 eval：现有 sandbox 加 `failure_reflection_loop: on|off` 配对 A/B，同预算；核心指标 pass@1 / 复发率 / 反思恢复率 / capture rate / 开销 |

## 四项开口裁决（苏格拉底四问收集，2026-09-24）

### DEC-INTERACTIVE-TASK（1-E）— 交互模式引入 `interactive_task_epoch`

- 同一用户目标下的连续追问/修复/重试属同一 epoch；任务 terminal 或用户明确切换
  目标才新建 epoch 并重置预算；**边界不明确时默认不重置**。
- `Session ≠ Task`，`Prompt ≠ Task`。
- 交互态状态落 `conversations/.state/`（沿用 recall marker 模式），
  **不复用** `progress/loop/state.yaml`（后者专属于 rsi-loop）。
- 预算分档：interactive 自动 block 最多 **1** 次；rsi-loop 在线反思最多 **2** 次。

### DEC-FAILURE-AUTHORITY（2-C）— 证据优先 + Kimi payload 一次性确认

- 权威链：客观验收证据/evaluator verdict > harness task state > agent 最终表态 >
  LLM 推断；表态仅为 fallback。
- 正式实现前对 Kimi Stop payload 做**一次抓包**确认是否含表态类字段：
  有则作增强，无则不改公共架构；**MVP 不得依赖 Kimi 私有 wire.jsonl 格式**。
- 公共能力必须在「无 agent 表态字段」的情况下完整工作。

### DEC-FAST-GATE（3-A）— MVP 不实现 fast-stop-gate

- Stop hook 不主动补跑测试/lint/smoke。无证据 → 记 `indeterminate`（合法状态，
  非故障）→ 由 reconciliation/evaluator 事后补判。
- 理由是职责边界：hook 消费事实，不二次充当 evaluator；项目 gate 配置/timeout/
  flaky/gate 失败语义均不进 MVP。
- 升级条件：真实数据显示大量 indeterminate 被补判为 task_failure 且廉价 gate
  可有效提前捕获时，再考虑 opt-in。

### DEC-FINGERPRINT（4-D）— 三级身份，禁止一指纹承担两个冲突目标

| 身份 | 用途 | 粒度 |
|---|---|---|
| `failure_event_id` | 唯一事件/幂等/归档/对账去重 | `hash(run_id, task_id, attempt, terminal_sequence)` |
| `reflection_fingerprint` | 本 task 内「是否已对这个失败反思过」 | **偏细**：宁可拆开，不可把新问题误判为已反思 |
| `recurrence_signature` | 跨任务「同类失败模式是否复发」 | 可更粗：category + 组件 scope + 归一化错误类（去行号/临时路径） |

schema 形状：`fingerprints: {reflection: {version: rf/v1, hash}, recurrence: {version: rs/v1, hash}}`。
M0 必须为两种指纹各建独立 golden pair tests（成对「应合并/应拆分」判定），
不得只验单一 fingerprint accuracy。

判败语义实现以 M0 golden tests 为完整规格（A1 判定表 18 行场景全量编码），
本文件仅记录权威链与五态定义。

## MVP 里程碑（验收随实施记录）

M0 契约+五态+双指纹 golden tests → M1 provisional archive（hook 崩溃不丢、幂等）→
M2 Claude 参考适配器全链路 → M3 反思 controller（≤2/task、≤1/fingerprint）→
M4 Recall（task 去重、Top-K、≤1200 tokens）→ M5 Transition Gate（不 silent
advance）→ M6 Kimi（含 payload 抓包）→ M7 Pi → M8 Codex conformance →
M9 reconciliation → M10 eval OFF/ON 配对。

实施优先级按 GPT 结论：**先可靠捕获（M0–M1–M9 的对账面）再复杂反思**。

## 风险要点（设计稿 R1–R8，实施时逐项设防）

R1 反思可能是错误归因（lesson 需 confidence/verification_status，hypothesis→
validated→canonical）；R2 recall 是持久化 prompt injection 通道（evidence 按
untrusted 处理，只回注结构化 lesson）；R3 归档前统一 redaction；R4 见
DEC-FINGERPRINT；R5 infra 失败风暴用 circuit breaker；R6 并发时 state 需
锁/原子写，长期迁 SQLite；R7 lesson 必须带 scope 防 negative transfer；
R8 正式实验需第三臂（generic retry）分离「额外算力」与「结构化反思」效应。

## 遗留

- Kimi Stop payload 抓包（M6 前执行，结果回填本记录）。
- opencode 不在本轮四家范围，共享管道后续补适配行。
- `fast-stop-gate` 配置形态、并发锁方案：按各自升级条件另行立项。
- 风险 R8 的三臂实验设计属 eval 层，随 M10 一并展开。

## 实施记录

- M0（2026-09-24）：`scripts/failure-event.py` + `tests/test-failure-event.py` +
  `tests/failure-event-smoke.sh` 落地。A1 判定表 23 案例、reflectability 派生、
  fe/v1 / rf/v1 / rs/v1 三级身份与成对 golden、三连跑确定性全部通过
  （27 个测试方法，unittest 输出 `OK`）。
  验收：`bash tests/failure-event-smoke.sh` → 0。
