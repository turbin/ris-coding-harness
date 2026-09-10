# RIS Coding Harness — 递归自我改进（RSI）设计

版本：v0.4（Phase 0-5 已实施；L1P 平台层 / 约束冲突门 / 事件触发已实施）
日期：2026-08-27

## 1. 背景与目标

本仓库当前是一套「安装器 + PM-Workers 静态协作 Skill」：

- `install.sh`：幂等工程引导器（`init`/`adopt` 双模式），安装 `AGENTS.md` 路由、`docs/engineering/` 规则目录和 `.agents/skills/pm-workers-engineering/`。
- `SKILL.md`：PM / Coder / Reviewer 三角色协议，TDD + 对抗式审阅 + 渐进式披露。

它解决了「agent 如何规范地做一次工程任务」，但没有解决「agent 如何从做任务的历史中变得更好」。

**目标**：把 harness 升级为递归自我改进系统——agent 执行任务 → 结果被结构化评估 → 从失败与评审中提炼模式 → 回写自身规则/prompt/skill → 在下一轮任务中表现更好，且每一步可度量、可回滚、有门禁。

**非目标**：

- 不做模型权重层面的自我改进（那是训练问题，不是 harness 问题）。
- 不追求全自动无监督；自改进的每一层都有与其风险匹配的批准门禁。
- 不推翻现有 PM-Workers 协议，RSI 是它的外层回路，不是替代品。

## 2. RSI 闭环总览

```
            ┌────────────────────────────────────────────────────┐
            │                                                    │
            ▼                                                    │
  ┌───────────┐   ┌────────────┐   ┌───────────┐   ┌──────────┐  │
  │  EXECUTE  │──▶│   SENSE    │──▶│ EVALUATE  │──▶│ REFLECT  │  │
  │ PM-Workers│   │ 结构化证据  │   │ 机器可读   │   │ 模式归因  │  │
  │ 跑任务     │   │ 落地       │   │ verdict   │   │          │  │
  └───────────┘   └────────────┘   └───────────┘   └──────────┘  │
                                                        │         │
            ┌───────────────────────────────────────────┘         │
            ▼                                                     │
  ┌───────────┐   ┌────────────┐                                  │
  │   GATE    │──▶│  MUTATE    │──────────────────────────────────┘
  │ 门禁+回滚  │   │ 回写规则/  │
  │           │   │ skill      │
  └───────────┘   └────────────┘
```

各环节职责：

| 环节 | 职责 | 载体 |
|---|---|---|
| EXECUTE | 现有 PM-Workers 流程执行任务 | `SKILL.md` |
| SENSE | 把测试输出、reviewer 结论、diff 统计落成结构化记录 | `evals/results/`、`progress/` |
| EVALUATE | 对任务结果打机器可读的分（pass/fail + 维度分） | verdict schema（见 §4.1） |
| REFLECT | 跨任务聚合，归因 recurring failure patterns | retro 报告（见 §4.3） |
| MUTATE | 提出对规则/skill 的具体修改 | 变更提案（见 §4.4） |
| GATE | 按风险层级审阅、批准、快照、可回滚 | 门禁策略（见 §5） |
| ACCEPT | 人工终验：一批变更/一轮循环结束后，人对结果做最终验收 | 循环总结报告（见 §4.5） |

人工终验不可配置关闭：门禁级别只决定「过程中」的自动化程度，任何自动合并的变更在人工终验通过前都视为「试运行」状态，可被整批回滚。

### EXECUTE 环节的两条数据纪律（已实现）

RSI 回路的上游数据质量由执行环节的两条硬规则保证：

1. **发现即记录**：任务中发现但未在本任务修复的问题（范围外缺陷、放行的 MAJOR、声明的 known limitations、onboarding 发现的基础设施缺口）必须记入 `issues/`，这是 DoD 检查项；本任务内修复的问题由 verdict + 回归测试覆盖，不重复记录。
2. **验收前核查 issue 闭环**：Reviewer 验收里程碑前，必须检查与本任务相关的所有 issue（用户报告的 + Coder 自测记录的）——逐条验证已修复（有证据）或显式延期（记录已更新）；任务声称要修的 issue 未关闭则不得验收。范围外的 open issue 只记录、不顺手修，交 PM 分诊。

这两条保证 REFLECT 阶段的归因输入（verdicts + issues）完整可信——漏记等于丢掉失败模式样本。

## 3. 「自我」的分层与风险边界

RSI 的首要设计问题是：agent 允许修改自己的哪一部分？分三层，风险与门禁递增：

| 层 | 对象 | 变更内容 | 风险 | 默认门禁 |
|---|---|---|---|---|
| L1 规则层 | `docs/engineering/*.md`（目标工程内） | 编码规范、测试约定、架构约束 | 低：只影响行为提示，且是目标工程的产物 | Reviewer 审阅 + git 提交 |
| L1P 平台知识层 | `docs/engineering/platform/**`（目标工程内；路径匹配上优先于 L1） | 平台相关经验知识卡（如 Windows 专项修复经验、平台相关依赖约束） | 低-中：不进通用规则上下文，但含环境特定性 | Reviewer 审阅 + **人工提交（永不自动 commit）**；预留外部知识库导出（§4.6） |
| L2 Skill 层 | `.agents/skills/pm-workers-engineering/SKILL.md` + `references/` | 协作协议、角色指令 | 中：影响所有任务的行为 | Reviewer diff 审阅 + eval 不回归 + 版本号递增 |
| L3 Harness 层 | `install.sh` / `install.ps1`、`rsi-loop` skill、评分脚本 | 回路机制本身 | 高：改错了整个回路失真 | 人类批准，永不自动改 |

原则：

1. **默认只在 L1 变异**。L1 闭环稳定运行且有数据证明收益后，才开放 L2。
2. **L3 永不自动变异**。机制层的修改必须人来发起。
3. **每层变异的收益必须用 eval 集验证**（见 §4.2），不接受「看起来更合理」作为变更理由。

## 4. 组件设计

### 4.1 SENSE / EVALUATE：结构化 verdict

现状缺口：Reviewer 的结论（`MILESTONE ACCEPTED/REJECTED` + 自然语言 issue 列表）无法被统计。

设计：Reviewer 在维持自然语言审阅的同时，额外输出一份机器可读 verdict，写入 `evals/results/<task-id>.yaml`：

```yaml
task_id: "2026-08-27-add-cache-layer"
milestone: "m1"
decision: rejected            # accepted | rejected
scores:                       # 1-5，Reviewer 按 rubric 打分
  correctness: 2
  test_quality: 3
  simplicity: 4
  resource_safety: 5
  convention_fit: 4
issues:
  - severity: BLOCKER
    category: correctness     # 有限枚举，便于聚合
    summary: "缓存无上限，重复执行内存线性增长"
    file: "src/cache.py"
rounds: 2                     # 对抗审阅往返次数
coder_red_green_evidence: true
loc_delta: {added: 120, removed: 15}
new_dependencies: 0
timestamp: "2026-08-27T10:41:00+08:00"
```

要点：

- `category` 用有限枚举（correctness / testing / simplicity / resource / concurrency / compatibility / convention / scope），使 REFLECT 阶段可以按类别聚合失败模式。
- Coder 的 TDD 红绿证据作为布尔字段落账，「跳过 RED」成为可统计指标。
- schema 版本化（`schema_version` 字段），演进时旧数据可迁移。

### 4.2 EVALUATE：eval 任务集与基线

现状缺口：没有「损失函数」。没有可重复跑的任务集，自改进无法区分「变好」和「没变/变差」。

设计：新增 `evals/` 目录：

```text
evals/
  tasks/                    # 每个任务一个目录
    001-off-by-one/
      task.md               # 任务描述（输入）
      setup.sh              # 构造初始仓库状态
      rubric.md             # 人工可读的评分标准
      expected.patch 或 verify.sh   # 机器可判的通过条件
    002-...
  results/                  # verdict 落账（§4.1）
  run-eval.sh               # 跑全部/单个任务，输出通过率
  baseline.json             # 当前基线分数
```

要点：

- 任务集刻意小而多样（10-20 个起步）：bug 修复、小特性、重构、性能修复、convention 遵循各若干。
- 每个任务必须有**机器可判的通过条件**（测试脚本或精确 diff 校验），不接受纯人工评判，否则无法高频跑。
- 基线指标：`pass@1` 为主，`reviewer 首轮通过率`和`平均审阅往返轮数`为辅。
- 任何 L1/L2 变异前后各跑一次 eval，**分数不提升的变更不合并**——这是整个 RSI 的防退化闸门。
- eval 任务集本身是 L3 资产，变异不许动它（防 reward hacking 的第一道墙）。

### 4.3 REFLECT：retro 机制

触发时机（满足其一）：

1. 每完成 N 个任务/里程碑（建议 N=5）；
2. 同一 `category` 的 BLOCKER/MAJOR 累计出现 3 次；
3. eval 分数相对基线下降。

输入：近期 verdict 记录、`issues/`、reviewer 拒绝理由、diff 统计。

产出：retro 报告，写入 `progress/retro/<date>.md`：

```markdown
# Retro 2026-08-27（任务 41-45）

## 数据摘要
- 通过率 4/5；平均审阅轮数 1.8；BLOCKER×2（均 resource 类）

## Recurring patterns
1. **无界资源增长**（3 次）：coder 反复引入无上限缓存。
   → 已有 docs/engineering/performance.md 未被 coder 加载（Level 2 漏判）。
   → 提案 P1：在 coding.md 顶部加「任何新增容器必须写明上限或清理点」检查项。
2. **RED 证据缺失**（2 次）：...
   → 提案 P2：...

## 提案清单
| ID | 目标层 | 文件 | 变更摘要 | 预期收益 | 验证方式 |
| P1 | L1 | coding.md | 新增资源检查项 | resource 类 BLOCKER 归零 | eval 回归 |
```

要点：

- 归因必须指向**机制原因**（规则缺失？规则没被加载？协议没约束？），而不是「这次没做好」。
- 每个 pattern 必须产出可执行的提案，没有提案的 retro 是无效的。
- retro 只产出提案，不直接改文件——修改走 §4.4。

### 4.4 MUTATE：变更提案与回写

每个提案是一个最小 diff，走与代码变更相同的流程：

1. **提案**：retro 产出，注明目标层、预期收益、验证方式。
2. **冲突同步检查**（`references/rule-conflict-check.md`）：提案进入审阅前先过冲突门——检索现有规则中与新提案语义重复或方向冲突的条目。重复/表述差异可自动合并优化；方向性冲突、跨层冲突、震荡型冲突无法自动解决时，暂停提案并提交用户裁决，裁决结果记录到 `decisions/`。
3. **审阅**：Reviewer 以对抗立场审提案——这条规则会不会过度拟合单次失败？表述是否可执行（agent 能照着做）？（「会不会与现有规则冲突」已由第 2 步覆盖。）
4. **用户确认（Phase 3 期间强制）**：retro 机制刚引入时，每条提案在 Reviewer 通过后还必须经用户显式确认才可落地。当提案质量被证明稳定（建议：连续 10 条提案无驳回/无回滚）后，才可将 L1 放宽为 `l1-auto` 免确认；L2 永远保留人类或 Reviewer + eval 双门。
5. **验证**：L1 变更跑 eval 相关子集；L2 变更跑全量 eval。分数不降级才可合并。L1P 平台卡只做草稿，不做 eval 门禁。
6. **落地**：修改文件，git 提交（message 关联提案 ID），更新 `evals/baseline.json`。例外：L1P 平台知识卡片永不提交，仅沉淀到 `docs/engineering/platform/` 供未来知识库导出。
7. **记录**：提案结果（采纳/拒绝 + 理由）追加到 `decisions/`。

规则卫生（防规则膨胀）：

- 每条新增规则必须带 `source:` 标注（来自哪个提案/issue），无 source 的规则在定期清理时可被移除。
- 单文件规则数设软上限；超过时 retro 必须先做「合并/删除旧规则」再做新增。
- 连续 K 轮 eval 中从未被触发/引用的规则，标记为候选删除。

### 4.5 EXECUTE：Loop Skill（最后实施）

循环入口设计为 **agent 内调用的 skill**（`rsi-loop`），而不是 shell 脚本。理由：

- 与仓库既有架构一致——harness 的逻辑都在 skill/规则文件中，shell 只负责安装；
- 纯 markdown 载体，任何能读 skill 的 agent 运行时都可使用，不绑定特定 CLI；
- 循环状态可对话式接管：中断后任何 agent（或下次会话）读状态文件即可续跑，用户可中途插手调整队列。

skill 结构：

```text
.agents/skills/rsi-loop/
  SKILL.md                  # 循环协议入口
  references/
    preflight.md            # 预检清单
    round-protocol.md       # 单轮流程
    gate-policy.md          # 门禁级别定义
    stop-conditions.md      # 停机条件
```

核心设计决策：

1. **编排者极薄，每轮派生子代理**：宿主 agent 只做预检、取任务、派单、收 verdict、判断 retro 触发、写状态；绝不在自己上下文中执行任务细节（否则多轮后循环状态本身耗尽上下文预算）。每轮子代理冷启动，上下文隔离与 shell 方案等价。
2. **skill 无状态，状态全在文件**：`progress/loop/state.yaml`（轮次、任务队列、门禁级别、累计指标）+ 每轮报告 `progress/loop/<round>.yaml`。
3. **预检清单**：git 工作区干净（`docs/engineering/platform/` 下待人工提交的知识卡除外，属预期状态，见 §4.6）、eval 基线存在、protected files 清单存在、所需工具可用；预检不过不进循环。
4. **停机条件硬编码**：eval 降幅超阈值、连续 N 任务失败、git 状态污染 → 立即停止并产出事故报告，等待人工。
5. **人工终验（不可省略）**：循环跑完指定轮数（或异常停止）后，产出整批总结报告——任务结果、eval 分数变化、本批全部变异清单及 diff 摘要——并停下等待人工最终验收。无人值守不等于无人审阅：循环期间自动合并的变更在人工终验通过前处于「试运行」状态；终验拒绝时按提案 ID 整批 `git revert` 回滚。
6. **门禁级别作为调用参数写入 state**：`observe-only`（只记录不变异，调试回路用）/ `l1-auto`（L1 自动、L2 需批准）/ `all-manual`（所有变异前暂停询问用户）。门禁级别只控制**过程中**的自动化程度，不影响第 5 条的人工终验。
7. **shell 只保留可选薄壳**：`run-loop.sh` 仅做「调起 agent 并 invoke rsi-loop」这一件事，供 cron/CI 等真正无人值守场景使用；交互场景下用户直接要求 agent 跑 N 轮即可。
8. **门禁强制力补强**：skill 自我约束弱于外部脚本，配可选 git pre-commit 钩子对 protected files 做硬校验——即使 agent 违规，提交也会被拒。

### 4.6 平台知识层（L1P）与外部知识库导出

反思回写的经验并非全部平台无关。Windows 特有的修复经验（路径/换行/编码怪癖、PowerShell 与 bash 差异、驱动/工具链版本陷阱、平台相关的依赖约束）若写进通用规则，会污染其他平台的规则上下文。

设计：

- **位置与格式**：`docs/engineering/platform/<platform>/<slug>.md`，一卡一文件；YAML frontmatter 携带 `platform` / `scope` / `source` / `date` / `export_ready` 元数据；`platform/index.md` 负责路由。
- **提交纪律**：L1P 永不自动 commit。循环只在工作区起草卡片，并在轮次报告中列「待人工提交」；未提交的 platform/ 变更是预期状态，不计入 rsi-loop 预检的工作区污染（§4.5 第 3 条）。
- **门禁**：卡片不做 eval 门禁；质量门禁 = Reviewer 审阅 + 人工提交。
- **加载纪律**：只加载与当前运行时匹配 `platform` 且任务涉及 `scope` 的卡片（渐进式披露）。
- **导出（预留，未排期）**：`.rsi/policy.yaml` 的 `platform_knowledge.export.targets` 预留知识库目标（如 Open Viking）；同步步骤读取 `export_ready: true` 的卡片推送，目标未配置时导出为 no-op。
- L1P 内部冲突同样走 §4.4 的提案审阅与防振荡条款，但即使合并结论已达成，卡片也保持未提交，等人工确认。

### 4.7 事件触发源（休眠期自动评估）

评估②（eval 集）的施工段需要 agent，不能指望「空闲的 agent 自触发」——会话闲置时不执行任何代码。触发模型反转：**由事件源在合适时机拉起评估，而不是 agent 监视自身状态**。因此也无需为不同 agent 适配状态监视机制：核心两层 agent 无关，第三层可缺省。

三层触发源：

| 层 | 触发源 | 说明 |
|---|---|---|
| 核心 | git hooks：`post-merge` 立即置标记；`post-commit` 防抖——触及 `docs/engineering/**`（L1P `platform/` 除外）或 `.agents/skills/**` 的提交立即置标记，其余提交每累计 N 次（默认 5）置标记 | 所有 agent 最终都走 git 提交，天然的事件总线；已实现：`evals/install-hooks.sh` + `evals/trigger.sh` |
| 核心 | OS 调度器：cron / 任务计划在夜间或机器空闲时消费标记跑评估 | 机器空闲 ≠ agent 空闲；「工程休眠阶段自动评估」由这层承担，与 rsi-loop 薄壳共用入口 |
| 可选 | agent 内事件（Kimi 会话 cron、Claude hooks 等） | 薄适配器，允许缺失，缺省回退到前两层 |

标记语义（`evals/.eval-pending`，gitignored）：hook 只置标记、不跑评估（hook 内同步拉起 agent 会阻塞用户 git 操作）。消费方 = OS 调度薄壳或下一个 agent 会话：`trigger.sh status` 检查 → 跑完整战役（`setup → 施工 → verify → check`）→ `trigger.sh consume` 清除。`check` 低于基线即停机报告（停机条件不变）。

门禁不变：无人值守触发的评估结果在人工终验前属「试运行」；检测到退步时的动作是停下产报告，不是自动回滚或自动改规则。

## 5. 安全与门禁（横切设计）

1. **Protected files**：`install.sh`、`install.ps1`、`evals/tasks/**`、`evals/run-eval.sh`、`docs/rsi-design.md`（本文件）列入保护清单，任何自动变异不得触碰。
2. **一切变异走 git**：每次回写单独提交，message 含提案 ID；任何时刻 `git revert` 可回滚一轮变异。
3. **Change budget**：单轮变异限制：最多 N 个文件、M 行 diff（建议 N=2, M=40），超限拆成多轮。
4. **防 reward hacking**：
   - eval 任务集与评分脚本不可变异（§4.2）；
   - 规则变更必须能在 eval 上体现收益，禁止「预防性」堆规则；
   - Reviewer 审提案时专门检查「这条规则是否在教 agent 钻评分的空子」。
5. **防振荡**：同一文件的规则，连续两次 retro 不得做方向相反的修改；出现即升级人类仲裁。
6. **人类最终权威**：任何层级的人都可以随时把门禁调回 `all-manual`；L3 永远人类批准。
7. **平台知识提交纪律**：L1P（`docs/engineering/platform/**`）永不自动 commit——循环只起草，人工提交后再由知识库导出流程消费（§4.6）。

## 6. 度量指标

写在前面：**没有指标的 RSI 是随机游走**。dashboard 只需追踪五个数：

| 指标 | 来源 | 健康方向 |
|---|---|---|
| eval pass@1 | `evals/run-eval.sh` | 单调不降 |
| reviewer 首轮通过率 | verdict 聚合 | 上升 |
| 平均审阅往返轮数 | verdict 聚合 | 下降 |
| 提案采纳率 | decisions 记录 | 稳定（过高=提案太琐碎，过低=retro 质量差） |
| 规则回滚率 | git log | 低（高说明变异质量差或 eval 有漏洞） |

## 7. 分阶段实施路线

| Phase | 内容 | 验收标准 | 状态 |
|---|---|---|---|
| 0 | 定义三层边界、protected files、change budget；git 快照约定 | 文档落地，安装器模板同步 | ✅ 已实施 |
| 1 | verdict schema + Reviewer 输出改造 + `evals/results/` 落账 | 跑一个真实任务产出合规 verdict | ✅ 已实施 |
| 2 | eval 任务集（≥10 个任务）+ `run-eval.sh` + 基线 | 能跑出可复现的 pass@1 | ✅ 已实施（基线 10/10，2026-08-28 实测） |
| 3 | retro 机制 + L1 规则回写（人工批准） | 完成一次「失败→归因→规则变更→eval 验证」全闭环 | ✅ 已实施（2026-08-28/29，提案 P1-P3 落地） |
| 4 | L2 Skill 自改进（eval 驱动 + 版本号） | 一次 SKILL.md 变更有 eval 证据支撑 | ✅ 已实施（v1.1.0，RED 证据最小形式） |
| 5 | `rsi-loop` skill 无人值守循环（可选 shell 薄壳供 cron/CI） | `--gate observe-only` 连跑 5 轮产出完整报告 | ✅ 已实施（`skills/rsi-loop/` + `run-loop.sh`，5 轮试跑，2026-08-29 人工终验通过） |
| — | L1P 平台知识层（§4.6，永不自动 commit，预留 Open Viking 等知识库导出） | 协议已实施（2026-09-10）；首次人工提交与知识库导出待启用 | ✅ 已实施 |
| — | 约束冲突同步检查门（§4.4 第 2 步，`references/rule-conflict-check.md`；可解自动优化 / 不可解提交用户裁决） | 协议已实施（2026-09-10）；首次真实提案走查待发生 | ✅ 已实施 |

每个 Phase 独立可交付、可暂停。Phase 0-2 是纯增量（只加不改），风险接近零；Phase 3 是第一个真正意义上的「自我改进」。

## 8. 反模式与已知风险

1. **规则膨胀**：规则只增不减 → 上下文预算被吃光、规则互相矛盾。对策：source 标注 + 软上限 + 候选删除（§4.4）。
2. **过拟合单次失败**：一次偶然的 BLOCKER 被泛化成全局规则。对策：retro 要求 pattern 至少出现 2-3 次才允许提案。
3. **Goodhart 定律**：agent 学会讨好 eval 而非真正变好。对策：eval 集保密性（不可变异）、定期人工抽查真实任务质量、eval 任务定期人工扩充。
4. **变异振荡**：规则反复横跳。对策：方向冲突升级人类仲裁（§5.5）。
5. **上下文污染**：回写的规则质量差，比没有规则更糟。对策：提案审阅检查「可执行性」，eval 不提升不合并。

## 9. 仓库卫生项（随 Phase 0 一并处理）

- README 标题与身份从 `project-init-scripts` 对齐为 `ris-coding-harness`。
- `install.sh` 中 `turbin/project-init-scripts` 远程地址为占位符，需更新为真实地址或保持参数化并注明。
- `init-prompt-for-soft-engieneering.md` 文件名拼写（engieneering → engineering），兼容期内保留旧文件但标注废弃。
