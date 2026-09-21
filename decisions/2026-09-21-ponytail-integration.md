# 2026-09-21-ponytail-integration — vendor 反过度工程规则集（ponytail）

- 来源：用户 2026-09-21 需求「读取 DietrichGebert/ponytail，判断如何集成到 harness、挂在哪个环节」
- 目标层：L2（新增 `.harness/skills/ponytail/`；pm-workers-engineering 1.5.0 → 1.6.0）+ L3 邻接（install.sh / install.ps1 的 AGENTS.md 受管路由段模板、README）
- 状态：adopted（集成落地；完整 pass@1 回归随下一次协议战役执行）

## 动机

PM-Workers 的 Coder 自检（`coder.md`）与 Reviewer「Simplicity」维度此前只有
清单条目、无操作判据；eval 任务 `13-simplicity-overengineering` 已把简洁性纳入
损失函数，但流程侧缺少与之配套的具体判据。ponytail 提供经实测的
7 级「简约阶梯」与 diff delete-list 审阅格式（agentic 基准：LOC -54%、
cost -20%、time -27%，安全项 100% 保留），正好把清单升级为可执行判据。

## 决策

**Vendor 为 harness L2 Skill，不用上游 plugin/hook 分发。** 依据：

1. G1 机制/决策二分：skill 内容进 `.harness/skills/`，installer 统一分发并登记
   manifest，单一事实源；
2. 渐进式披露：harness 的哲学是「AGENTS.md 路由 + skill 按需激活」，上游的
   hook 每轮注入会增加常驻 token 成本，与 2026-09-18 任务成本预算决策方向相反；
   hook 安装面已由 `install-agent-hooks.py` 统一管辖，不引入第二套管理面；
3. G3 跨 agent：复用 `--agent` 分发即覆盖 claude/pi/kimi/opencode/codex；
4. 挂点天然存在：PM（拆解 YAGNI 检查）/ Coder（施工前阶梯 + 自检 delete-list）/
   Reviewer（Simplicity 维度升级为 tagged findings + net LOC）三个角色引用，
   不新增流程环节。

**明确排除**：上游 plugin/hook 直装；node 依赖；`ponytail-help`（上游 slash 命令
在本 harness 不存在）；always-on 模式持久化（lite/full/ultra 降级为单次调用强度提示）。

## 落地内容

- `.harness/skills/ponytail/`：SKILL.md（阶梯 + 规则 + 安全红线 + 强度表 +
  pm-workers 边界）+ `references/{review,audit,debt,gain}.md` + 上游 MIT LICENSE +
  UPSTREAM.md（来源 commit `e3ba2aa6f1e6f0bc4d69eb09c9f0d0a93af56156` 与同步约定）。
- pm-workers-engineering 1.6.0：coder.md 工作流插入 LADDER 步（第 3 步，记录
  停留级）与自检前置 delete-list；reviewer.md Simplicity 维度改为 tagged
  findings（delete/stdlib/native/yagni/shrink）+ `net: -<N> lines possible.`；
  pm.md 职责加拆解期 YAGNI 检查。
- install.sh / install.ps1：AGENTS.md 受管路由段模板增列 ponytail（两侧同步）。
- README：必需 skill 清单与安装内容树增列 ponytail。

## 验证

- `tests/install-smoke.sh`：PASS；`tests/install-smoke.ps1`（powershell 5.1）：PASS，
  必需 skill 自检显示 `ok .harness\skills\ponytail`。
- `evals/run-eval.sh verdicts`：20 files, 0 hard violations（存量 v1 告警为历史
  verdict，与本次变更无关）。
- 引用路径抽验：coder.md / reviewer.md / pm.md 中 `.harness/skills/ponytail/...`
  路径与落位一致。

## 遗留

- **完整 pass@1 回归待下一次协议战役**（与 2026-09-18 先例一致）：pm-workers
  1.6.0 属 L2 变更，按 Phase 4 纪律须 eval 验证不退化；本次提交会触发
  `evals/.eval-pending` 标记（触及 `.harness/skills/**`），由战役消费。
- Phase 3 遥测衔接（verdict / 轮报告增加 diff LOC 统计、与 token 预算并列）
  后置，另行立项。
- 上游同步为手动：更新后需改 UPSTREAM.md / SKILL.md frontmatter 的 commit hash
  并在本目录记录。
