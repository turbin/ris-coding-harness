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
