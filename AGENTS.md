# ris-coding-harness — Agent 路由入口

本仓库是 RSI Coding Harness 本体。除本文件外无其他根级 AGENTS.md 约束；目标工程接入后由安装器生成各自的 AGENTS.md。

## 工作纪律（每次会话必须保持）

0. **硬约束直接写入本文件、即时生效**：凡属"必须始终遵守"的硬约束（本节的纪律、compact-recall 回顾路由等），一律写进根 `AGENTS.md`，从会话开始即生效，不得依赖某个 skill 激活或流程推进到某阶段后才开始遵守；渐进式披露（`docs/engineering/` 按需加载）仅适用于任务相关的软规则/上下文，不适用于硬约束。
1. **进度状态即交付物**：完成一项工作立即更新 TodoList；口头汇报"完成/通过"的任何事项，必须先在 TodoList 中标记 done——口头结论与工具状态不允许分裂。
2. **收尾对账**：turn 结束或任务收尾前，逐项核对口头结论与 TodoList 状态，不一致先修正再交付。
3. **用户可见状态必须准确**：TUI 进度面板等用户可观察的状态是交付质量的一部分；陈旧的进度信息比没有更糟（主动误导），发现过期立即更正。
4. **语义存疑先问再动**：用户指令含义不明时（单词/缩写/指代、多解并存、意图缺口落在是否要执行上），先用正文一句话给出「我的理解 + 可选项」并等答复，**不得择一直接执行**；分歧涉及执行类动作（写盘、安装/卸载、删除、`git commit`、改配置或用户目录）时此条强制。auto 权限模式下 `AskUserQuestion` 不可用，只是不可用该工具，**不等于可以不问**——正文提问即可。
5. **推断不得充当用户表态**：未经用户明说的解读，禁止写成「用户决定/已裁决」进入 `decisions/`、`issues/`、`*/index.md`、TodoList 或对用户的汇报；只能记「待用户答复」，误写立即改正。此项从第 3 条派生：状态失真既包括过期，也包括**虚构表态**。
6. **架构描述以文档为准**：回答架构/结构问题时，只依据仓库现有文档（`docs/`、`.harness/docs/engineering/`、decision 记录）；文档没有的明说「文档中没有」，不得口头补位或凭模型先验编造。
7. **设计与实现分离**：头脑风暴/规划产出的设计不算实现信号；判断某功能是否已实现，只认代码、测试、运行证据。
8. **判死先查引用**：裁决删除任何模块/文件/skill 前，先做全仓库引用核查（import、docstring、配置、文档提及），产出引用清单后才可裁决；无清单不裁决。
9. **跨线触点必须登记**：决策/计划声明跨工作线依赖（「回归待下一次战役」「后续补适配」「随某阶段一并展开」等）时，必须同步登记一行到 `progress/touchpoints.md`（生产方、消费方、触点内容、状态）；触点清偿（消费方落地、回归已跑）时更新状态并附证据。纵向链条（decision→plan→progress→index）不能替代横向登记。

## 回顾此前的对话/工作（compact-recall）

本仓库通过各 agent 的 hook/扩展机制（kimi/claude/codex 的 shell hook、pi/opencode 的 TS 适配器，由 `scripts/install-agent-hooks.py` 在 install 阶段注册，详见 README §5）自动把每次上下文压缩的摘要归档到 `conversations/`：

- `conversations/index.md` — 全部归档的索引表，按时间倒序（Time 列即压缩发生时间，ISO-8601 UTC）。
- `conversations/archive/<session_id>/<时间>.md` — 单次压缩的摘要原文（front matter 含 session_id、session_title、cwd、compact_time、source）。

当用户要求**回顾、继续、或追问此前会话中的工作**时：

1. 先读 `conversations/index.md`，按时间倒序挑选相关条目（可用 session id 关联到具体会话）。
2. 再读对应归档文件获取完整摘要。
3. 回答时注明所依据摘要的时间与 session id；**时间越新的摘要可信度越高**，较早的摘要可能与仓库现状脱节，引用前用 Read/Grep 对仓库当前状态做核实。
4. 同一 session 多次压缩会产生多个归档，按 compact_time 取最新一份为主、更早的为辅。

## 工程约定速览

- 目录与索引约定：`issues/` 带 `index.md`；`decisions/`、`progress/` 以 README 为索引（本仓库自身现状，与安装器模板「各带 index.md」不同）；跨线触点登记面为 `progress/touchpoints.md`。
- 测试与自检：`./tests/install-smoke.sh`、`./evals/run-eval.sh verdicts`、`./tests/compact-recall-smoke.sh`（compact-recall 冒烟，覆盖 kimi/claude/codex 归档路径与安装器幂等）、`./tests/trigger-smoke.sh`（事件触发冒烟）、`./tests/trace-usage-smoke.sh`（成本遥测冒烟）、`./tests/failure-event-smoke.sh`（失败事件判定表）、`./tests/retro-aggregate-smoke.sh`（verdict 聚合 + 预算遥测冒烟）、`./tests/rsi-loop-smoke.sh`（rsi-loop 文件契约 + retro 触发判定表冒烟）。
- 详细设计见 `README.md` 与 `docs/rsi-design.md`。
