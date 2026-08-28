# progress/retro — REFLECT 环节产出目录

依据 `docs/rsi-design.md` §4.3。Retro 是 RSI 闭环的归因环节：把近期
verdict（`evals/results/*.yaml`）与 issue 记录聚合成**机制级失败模式**，
并产出可执行的变更提案。Retro **只产出提案，不直接改文件**——修改走
`decisions/` + 门禁流程（§4.4）。

## 触发时机（满足其一）

1. 每完成 N 个任务/里程碑（建议 N=5）；
2. 同一 `category` 的 BLOCKER/MAJOR 累计出现 3 次；
3. eval 分数相对基线下降。

## 流程

```bash
# 1. 聚合 verdict 数据（不修改任何文件）
scripts/retro-aggregate.py --verbose

# 2. 归因：对每个 recurring pattern 问「机制原因是什么」
#    （规则缺失？规则没被加载？协议没约束？），而非「这次没做好」

# 3. 写报告：progress/retro/<date>.md，含提案清单；每个 pattern ≥2 次出现才可提案

# 4. 提案进 decisions/，走审阅 → （Phase 3 期间）用户确认 → 回写 → eval 验证
```

## 报告模板

```markdown
# Retro <date>（任务 <a>-<b>）

## 数据摘要
- 通过率 x/y；平均审阅轮数 z；BLOCKER×n（均 <category> 类）
- （聚合命令：scripts/retro-aggregate.py）

## Recurring patterns
1. **<模式名>**（<n> 次）：<现象>
   → 归因：<机制原因，指向规则/协议/加载缺口>
   → 提案 P<n>：<一句话>
2. ...

## 提案清单
| ID | 目标层 | 文件 | 变更摘要 | 预期收益 | 验证方式 |
| P1 | L1 | docs/engineering/coding.md | ... | ... | eval 回归 |

## 观察项（不足提案阈值 / 需人工）
- ...
```

## 规则卫生（§4.4）

- 每条落地规则必须带 `source:` 标注（提案/issue ID）。
- 单文件规则设软上限；超限先合并/删除旧规则再新增。
- 连续 K 轮 eval 从未被触发的规则标记为候选删除。
