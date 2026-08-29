# 2026-08-29-eval-expansion — eval 任务集扩充 10 → 20

- 来源：设计 §4.2（"任务集刻意小而多样（10-20 个起步）"）+ 用户 2026-08-29 批准继续
- 目标层：L3 资产新增（`evals/tasks/**` 为 protected，新增任务由人工发起，不改动既有任务）
- 状态：adopted

## 动机

既有 10 任务覆盖 bug 修复/小特性/重构/性能/convention，但以下类别缺位：
concurrency、compatibility（数据格式）、simplicity（过度工程）、resource（异常路径泄漏）、
testing（弱测试）、performance（算法复杂度）、money 舍入、类级状态泄漏。

## 新增任务（11-20）

| ID | 类别 | 陷阱 | 验证方式 |
|---|---|---|---|
| 11-concurrency-shared-state | concurrency | check-then-act 竞态（sleep 加宽窗口） | 30 线程同座，恰好 1 成功 |
| 12-compat-legacy-format | compatibility | 新字段导致旧格式解析崩溃 | 旧格式缺省字段 + round-trip |
| 13-simplicity-overengineering | simplicity | 类/工厂/注册表过度设计 | 行为测试 + grep 类定义残留 |
| 14-resource-handle-leak | resource | 异常路径句柄注册表无界增长 | 成功/失败反复调用后注册表有界 |
| 15-weak-test-regression | testing | 测试通过但断言的不是行为 | 行为修复 + 测试须含精确频次断言 |
| 16-date-boundary | correctness | ISO 时间戳按时刻差计算，跨日错一 | 日期截断后按日历日计数 |
| 17-performance-quadratic | performance | O(n²) 全对但不可扩展 | 100k 规模 6s 超时守卫（子进程内生成数据） |
| 18-convention-discipline | convention | 绕过数据访问入口/错误结构不符 | 行为 + grep 禁用术语 |
| 19-money-rounding | correctness | 浮点舍入漂移，分账不守恒 | 和精确等于总额 + 最大差 ≤0.01 |
| 20-class-state-leak | resource | 类属性共享导致实例串扰 | 实例隔离测试 |

## 质量自查（每任务）

- 未改动沙盒 verify：11/20 首轮 9/10 FAIL，17 因 30k 规模恰好挤进超时 → 修正为
  100k 规模后 FAIL（此轮自查暴露了超时守卫设计不严）。
- 修复后 verify：20/20 PASS（全量 20 任务验证通过，无回归）。
- 开发过程中发现并修复的验证脚本缺陷：
  1. 17 超时规模不足（30k O(n²) 约 2-5s，接近 5s 阈值）→ 100k；
  2. 13 setup 原始实现与任务规格不一致（价格小数位）→ 修正 setup；
  3. 11 verify 测试间共享模块状态污染（distinct 测试后全局计数不符）→ setUp 清空。

## 验证

- 全量 `run-eval.sh verify`：20/20 PASS，pass@1 = 1.00。
- `baseline.json` 更新为 20 任务全绿。

## 结果

**采纳**（2026-08-29）。verdict 落账 `evals/results/11..20-*-m1.yaml`。
