# 跨线触点登记（cross-line touchpoints）

横向纪律的登记面：登记**跨工作线/跨资产的依赖与欠账**——A 线的产物需要 B 线消费、A 的变更需要 B 联动、或 A 自知欠 B 一次回归/适配。每条线的纵向链条（decision → plan → progress → index）不在此重复。

规则：

- 新决策声明跨线依赖（如「回归待下一次战役」「后续补适配」「随 M10 一并展开」）时，**必须同步登记一行触点**，否则该依赖只存在于括号备注里，等撞上才被发现。
- 触点关闭（消费方已落地、回归已跑）时更新 Status 为 closed 并附证据链接。
- Status 取值：`open`（欠账未清）/ `closed`（已清，附证据）。

| ID | Line A（生产方） | Line B（消费方/受影响方） | Touchpoint（触点内容） | Status | Evidence / Due |
|---|---|---|---|---|---|
| TP-1 | task-cost-budget（2026-09-18） | evals/协议战役 | 预算线落地时声明「完整 pass@1 回归待下一次协议战役」；下一次战役的队列条目需带 `budget` 字段并跑全量回归 | open | `decisions/2026-09-18-task-cost-budget.md`（§验证节） |
| TP-2 | ponytail-integration（2026-09-21） | 遥测/verdict schema | verdict 与轮报告增加 diff LOC 统计，与 token 预算并列 | open | `decisions/2026-09-21-ponytail-integration.md:58` |
| TP-3 | failure-reflection-loop（2026-09-24） | rsi-loop REFLECT / install-agent-hooks（M2）/ trigger.sh / retro-aggregate | M0 产物 `scripts/failure-event.py` 已落地，当前零消费方；M1+ 各阶段需按消费点接线 | open | `decisions/2026-09-24-failure-reflection-loop.md`（遗留节、M0–M10 分期） |
| TP-4 | 检索路由（zvec routing 决策） | 安装器 / .gitignore | 路由文本点名 CodeGraph，但安装器不装、`.gitignore` 缺 `.codegraph/`；已撞上并落 issue，属「撞上才登记」反面案例 | open | `issues/2026-09-24-codegraph-absent-vs-routing.md` |
