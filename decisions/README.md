# decisions — 提案与决策记录

RSI 闭环 MUTATE 环节（`docs/rsi-design.md` §4.4）的审计轨迹：
每条变异提案一份记录，含对抗审阅、用户确认、落地、eval 验证与最终结果。
命名：`<date>-P<n>.md`（n 为 retro 报告中的提案序号）。

- `2026-08-28-P1.md` — L1 testing.md：行为变更必须先给 RED 证据
- `2026-08-28-P2.md` — L1 coding.md：标准库 API 先探针验证
- `2026-08-28-P3.md` — L1 testing.md：边界输入清单先行
- `2026-08-29-eval-expansion.md` — L3 资产新增：eval 任务集 10 → 20
- `2026-09-18-task-cost-budget.md` — L2+L3：任务级 token/费用预算（PM 声明 + loop 强制）
- `2026-09-20-zvec-search-routing.md` — L3 资产新增：zvec 检索路由分工 + 安装器 `--search` 初始化选项
- `2026-09-21-ponytail-integration.md` — L2 资产新增：vendor ponytail 反过度工程规则集（PM/Coder/Reviewer 三角色挂接；完整 pass@1 回归随下一次协议战役）
- `2026-09-23-diagram-skills-vendoring.md` — L2 资产新增：vendor c4-architecture + mermaid-diagrams（方案 A′：两 skill 判为用户级、经 `.harness/skill-scope.txt` 分发到全部 agent 的用户目录；替换用户级同类 skill；触发冲突已解决，输出位置改造待决）
- `2026-09-23-graphify-scale-gate.md` — L3 资产新增：init/adopt 按工程文件数（阈值 483，`.harness/graphify-threshold.txt`）判定 graphify 启用/禁用 + 安装器 `--graphify auto|on|off`
- `2026-09-23-topology-synthesis.md` — L2 资产新增：architecture-topology 按需拓扑合成 + 落盘缓存（user 级，规模门禁用 graphify 的工程的 fallback）
- `2026-09-24-failure-reflection-loop.md` — L3 机制设计：任务失败反思回路（Trigger/Reflect/Archive/Recall/Transition；DEC-FR-001~015 + 四项开口裁决：interactive_task_epoch / 证据权威+Kimi 抓包 / MVP 无 fast-gate / 双指纹拆分）
