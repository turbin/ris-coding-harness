# 2026-09-18-task-cost-budget — 任务级 token/费用预算

- 来源：用户 2026-09-18 需求「任务分解时 PM 需要添加任务 token/费用的预算，严格控制每个任务的开发成本」
- 目标层：L2（pm-workers 1.4.0 → 1.5.0、rsi-loop 1.1.0 → 1.2.0）+ L3 邻接配置（`.harness/.rsi/policy.yaml` 首次实体化）+ 工具/测试（`scripts/trace-usage.py`、`scripts/retro-aggregate.py`、`tests/trace-usage-smoke.sh`）
- 状态：adopted

## 动机

既有回路只有质量损失函数（pass@1），没有成本约束：任务可以无限消耗 token 而回路无从感知。
预算必须「分解时声明 + 执行时度量」才有效；度量数据链路（P6 强制留存的 trace）已具备，
缺的只是提取工具、预算字段和执行闸门。

## 设计（docs/rsi-design.md §4.8）

三个执行点：

1. **分解时声明（PM）**：任务字段必含 `Token/Cost Budget`（tokens 必填、cost_usd 可选）；
   给不出可信预算 = 任务过大信号，先拆分（pm-workers SKILL §6 + pm.md 模板）。
2. **派单前硬校验（rsi-loop）**：队列条目必含 `budget`；缺预算不派单，列出全部缺失条目报错
   （preflight 第 5 项 + round-protocol TAKE 双重校验）。
3. **轮后遥测与停机（rsi-loop）**：编排者用 `trace-usage.py` 从 trace 提取实际消耗写入轮报告
   （`budget`/`token_usage`/`total_tokens`/`cost_usd`/`cost_source`/`budget_exceeded`），
   累计进 state counters；不让子代理自报（防造假）。`policy.yaml budget.enforce: strict`
   下连续 2 轮超标或 `loop_budget` 累计超限 → 停机条件 #8/#9；`record` 只记录。

预算语义：计量对象 = 施工子代理会话 trace；token = input（含缓存读）+ output + reasoning 总和；
cost = 原生 cost（pi）优先，否则按 policy 定价表估算（kimi），均不可得记 unknown。

非目标：不做施工中途 kill（跨 CLI 实时监控 trace 不可靠），中途熔断留作未来项。

## 度量依据（实施前实测，round-1..5 历史 trace 回填）

| 轮 | 任务 | agent | total_tokens | cost_usd | 来源 |
|---|---|---|---|---|---|
| 1 | 11-concurrency-shared-state | pi | 435,268 | 0.008522 | native |
| 2 | 12-compat-legacy-format | pi | 194,999 | 0.004245 | native |
| 3 | 13-simplicity-overengineering | kimi | 1,018,579 | 0.048695 | pricing |
| 4 | 14-resource-handle-leak | pi | 704,947 | 0.010425 | native |
| 5 | 15-weak-test-regression | kimi | 893,318 | 0.041604 | pricing |

kimi 会话 token 量显著高于 pi（重缓存、262k 上下文），单任务经验预算量级：≤1M tokens / ≤$0.05（按默认定价表）。

## 验证

- `tests/trace-usage-smoke.sh`：PASS（合成 fixture 精确断言 + 真实 trace 数值锚定 + unknown/缺路径分支）。
- `tests/install-smoke.sh`：PASS。
- retro-aggregate `--rounds-dir`：10 份既有轮报告正确识别为 unmetered；合成 metered 报告产出
  budget vs actual 表与累计值。
- eval 回归门禁：`run-eval.sh setup + verify` 在全新沙盒上 20/20 FAIL——符合设计（未施工沙盒必须 FAIL，
  失败原因核实为内嵌缺陷，见 `decisions/` 本记录与 evals/README.md 自查规则）；
  本功能不触碰 `evals/**` 与 verify 执行路径。**完整 pass@1 回归待下一次协议战役**
  （届时轮报告将首次带 budget 字段，形成预算遥测闭环）。

## 结果

**采纳**（2026-09-18）。后续首个真实 loop 战役应：队列条目补 `budget` 字段；
strict 模式默认开启，observe-only 试跑可切 `record`。
