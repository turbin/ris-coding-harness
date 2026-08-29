# RSI 里程碑任务分解（Phase 3-5）

依据 `docs/rsi-design.md` §7 分阶段实施路线，将剩余里程碑分解为可独立交付、可验证的任务。
状态：`todo` / `in-progress` / `done`。每条任务完成时更新本表并附提交。

## Phase 3 — retro 机制 + L1 规则回写（人工批准）

验收标准：完成一次「失败 → 归因 → 规则变更 → eval 验证」全闭环。

| ID | 任务 | 交付物 | 验收 | 状态 |
|---|---|---|---|---|
| P3-1 | 实测 eval 基线 | 10 个沙盒任务施工完毕，`evals/baseline.json` 记录真实 pass@1；每任务一条 verdict 落账 `evals/results/` | 基线非 null，`run-eval.sh check` 可比较 | done |
| P3-2 | retro 机制落地 | `progress/retro/` 目录 + 报告模板 + `scripts/retro-aggregate.py`（verdict 聚合工具） | 能对 verdict 目录聚合 category/severity 统计并生成报告骨架 | done |
| P3-3 | 跑一次完整 retro | `progress/retro/<date>.md` 报告：数据摘要、recurring patterns（≥2 次才成模式）、提案清单（含目标层/预期收益/验证方式） | 每条 pattern 都有可执行提案；归因指向机制原因 | done |
| P3-4 | 提案审阅 + 用户确认 + L1 回写 | `decisions/` 提案记录；经对抗审阅与用户显式确认后回写 `templates/project/docs/engineering/` | 规则带 `source:` 标注；确认过程留痕 | done（P1-P3 已批准落地） |
| P3-5 | eval 验证闭环 | 重跑 eval，与基线比较 | pass@1 不降（目标类别提升） | done（10/10 无回归；02/03 首轮通过） |

## Phase 4 — L2 Skill 自改进（eval 驱动 + 版本号）

验收标准：一次 SKILL.md 变更有 eval 证据支撑。

| ID | 任务 | 交付物 | 验收 | 状态 |
|---|---|---|---|---|
| P4-1 | 识别 skill 层模式缺口 | 基于 P3-3 的归因，明确 SKILL.md 协议级缺口（非规则级） | 缺口描述可对应到具体协议段落 | done（RED 证据最小形式缺失，§7/§8） |
| P4-2 | SKILL.md 变更 + 版本号递增 | skill 版本 1.0.0 → 1.1.0，变更说明记录于 `decisions/` | 变更绑定提案 ID，有 eval 证据 | done |
| P4-3 | 全量 eval 验证 | 重跑 10 任务 | pass@1 不低于 P3-1 基线 | done（10/10 持平；首轮通过率 7/10→9/10） |

## Phase 5 — rsi-loop skill 无人值守循环

验收标准：`--gate observe-only` 连跑 5 轮产出完整报告。

| ID | 任务 | 交付物 | 验收 | 状态 |
|---|---|---|---|---|
| P5-1 | rsi-loop 主协议 | `skills/rsi-loop/SKILL.md`：编排者极薄、每轮子代理、状态全在文件 | 协议覆盖预检/取任务/派单/收 verdict/retro 触发/停机 | done |
| P5-2 | 参考文档 | `references/{preflight,round-protocol,gate-policy,stop-conditions}.md` | 每个文件可独立指导一个环节 | done |
| P5-3 | 状态与报告约定 | `progress/loop/state.yaml` + `<round>.yaml` 模板；预检清单落地 | 中断后可凭状态文件续跑 | done |
| P5-4 | 可选薄壳与钩子 | `run-loop.sh`（可选）+ 可选 pre-commit 钩子 `scripts/rsi-protect.sh` | 脚本只做「调起 agent 并 invoke rsi-loop」；钩子实测拦截受保护文件 | done |
| P5-5 | observe-only 试跑 | 连跑 5 轮（真实证据重建），产出 `progress/loop/summary-*.md` 总结报告 + 人工终验模板 | 报告含任务结果/eval 变化/变异清单 | done（待人工终验） |

## 演进任务（用户 2026-08-29 批准）

| ID | 任务 | 状态 |
|---|---|---|
| E-1 | eval 任务集扩充 10 → 20（补齐 concurrency/compat/simplicity/resource/testing/perf/money 类别） | done（`decisions/2026-08-29-eval-expansion.md`，全量 20/20，基线更新） |
| E-2 | 第二轮 retro（20 任务，N=5 触发）：报告 + 提案 P4（L3 verdict schema 校验器）/ P5（L2 verdict origin 字段） | done（提案已确认并落地：`decisions/2026-08-29-P4-P5.md`，20/20 回归无退化） |
| E-3 | 真实子代理轮（observe-only，agent 候选 pi/kimi，含 kimi 首个多 agent 数据点） | done（loop-real-01：5/5 机器判定 PASS，5 条 `origin: protocol` verdict 替换自记书签，零变异；待人工终验） |
| E-4 | P6 trace execution 落库：子代理执行轨迹入仓 + 协议强制（无轨迹=轮次无效）+ loop-real-01 回填 | done（`decisions/2026-08-29-P6.md`，rsi-loop v1.1.0，20/20 回归无退化） |
| E-5 | 真实工程试点（`install.sh --mode adopt` 到真实仓库 + 真实任务） | 用户主导，待执行（用户 2026-08-29：将应用到真实项目中观察） |

## 仓库卫生项（§9）

| ID | 任务 | 状态 |
|---|---|---|
| H-1 | 校验 `install.sh` 远程地址占位符（参数化说明） | todo（`REPO=${PROJECT_INIT_REPO:-turbin/ris-coding-harness}` 已参数化，README 已指向真实地址） |
| H-2 | `init-prompt-for-soft-engieneering.md` 拼写修正 + 旧文件标注废弃 | done（新文件 + 旧文件废弃标注 + README 同步） |

## 横切纪律（每任务适用）

- 一切变异走 git，单任务单提交，message 关联任务 ID。
- 不触碰 protected files：`install.sh`、`install.ps1`、`evals/tasks/**`、`evals/run-eval.sh`、`docs/rsi-design.md`、`.rsi/**`。
- eval 任务集与评分脚本不可变异（防 reward hacking）。
- Phase 3 期间 L1 提案必须经用户显式确认。
