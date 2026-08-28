# 2026-08-29-L2 — SKILL.md RED 证据最小形式定义

- 来源：retro [2026-08-28](../progress/retro/2026-08-28.md) pattern 1（RED 证据缺失 10/10）
- 目标层：L2（Skill 层，`skills/pm-workers-engineering/SKILL.md`）
- 状态：adopted

## 缺口（P4-1）

基线施工期间 `coder_red_green_evidence=false` 占 10/10 里程碑。归因指向**协议空洞**：

1. SKILL.md §7 要求 RED，但未定义其最小形式，尤其未说明「存在外部机器判定
   （eval verify / CI）时 RED 如何取证」——agent 把外部 check 当作测试本身，
   跳过自写 RED；
2. §8 Reviewer 契约未将「RED 证据可信度（实现前 vs 事后补录）」纳入挑战项，
   导致 RED 缺失在审阅中不可见、不可计数。

## 变更（P4-2）

`skills/pm-workers-engineering/SKILL.md` 1.0.0 → **1.1.0**：

- §7 RED：新增最小 RED 证据定义——失败测试/最小复现脚本 + **实现前**记录的
  失败输出；外部 check 不替代 RED；纯重构豁免但须 GREEN 基线。
- §8 Reviewer 契约：新增挑战项「RED 证据可信度：失败条件是实现前记录还是
  事后重建」。

## 验证（P4-3）

- 2026-08-29 全量 eval：pass@1 = **10/10**，与基线 1.0000 持平（无回归，
  results/eval-20260829T071037.json）。
- 有效提升指标：严格首轮通过率 **7/10 → 9/10**（02/03 在 RED-first + 探针流程下
  首轮通过；此前各需 1 轮返工）。pass@1 已达上限 1.0，首轮通过率是更细粒度证据。
- 与 L1 P1 同向（不振荡）：P1 落规则层，本变更落协议层，互相引用。

## 结果

**采纳**（2026-08-29）。
