# ris-coding-harness

递归自我改进（RSI, Recursive Self-Improvement）的 Coding Harness。

用一个安装命令把任意工程接入统一的目录约定、渐进式工程规则披露，以及 PM-Workers（PM / Coder / Reviewer）开发流程；在此之上，按 [docs/rsi-design.md](docs/rsi-design.md) 的设计逐步叠加「执行 → 评估 → 反思 → 回写 → 门禁」的自我改进闭环，同时不把某个具体语言、框架或工程的特殊规范硬编码进 Skill。

## 工程建立

### 推荐：单命令安装

在目标工程目录执行：

```bash
curl -fsSL https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.sh | bash -s -- --target .
```

默认 `--mode auto`：

- 空/近空目录：按 `init` 模式创建完整标准工程骨架。
- 已有工程：按 `adopt` 模式接入 Agent 配置，不重排已有源码结构。

### 显式初始化新工程

```bash
curl -fsSL https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.sh | \
  bash -s -- --target ./my-project --mode init
```

### 接入已有工程

```bash
curl -fsSL https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.sh | \
  bash -s -- --target . --mode adopt
```

### 本地 clone 后执行

```bash
git clone git@github.com:turbin/ris-coding-harness.git
./ris-coding-harness/install.sh --target ./my-project --mode init
```

### Windows（PowerShell）

`install.ps1` 是 `install.sh` 的 PowerShell 移植，参数与行为一致（远程下载回退改用 zip 包，无需 curl/tar）：

```powershell
# 本地 clone 后执行
.\ris-coding-harness\install.ps1 -Target .\my-project -Mode init

# 或下载单文件后在目标工程执行
powershell -ExecutionPolicy Bypass -File install.ps1 -Target . -Mode adopt

# 按 agent 分发（与 bash 版参数一致）
.\install.ps1 -Target . -Agent claude,opencode          # 工程内多 agent 接入
.\install.ps1 -Target . -Agent all -Scope user          # 本机所有 agent 全局可用
```

对应冒烟测试：`pwsh ./tests/install-smoke.ps1`。

### 安装器参数

```text
--target PATH          目标工程目录（默认 .）
--mode auto|init|adopt 初始化模式（默认 auto）
--force                覆盖安装器管理的模板文件
--no-git               不初始化 Git 仓库
--no-skill             不安装 PM-Workers Skill
--agent LIST           额外分发 Skill 到指定 agent 目录（逗号分隔，可重复；支持 all）
--scope project|user   agent 目录的作用域：工程内 / 用户主目录（默认 project）
-h, --help             查看完整帮助
```

### 按目标 agent 分发 Skill

默认只安装到通用标准路径 `.agents/skills/`。用 `--agent` 追加各 agent 的原生 skill 目录（已按各官方文档核实）：

| `--agent` | project 作用域（默认） | user 作用域（`--scope user`） |
|---|---|---|
| `claude` | `.claude/skills/` | `~/.claude/skills/` |
| `pi` | `.pi/skills/` | `~/.pi/agent/skills/` |
| `kimi` / `kimi-code` | `.kimi/skills/` | `~/.kimi/skills/` |
| `opencode` | `.opencode/skills/` | `~/.config/opencode/skills/` |
| `codex` | `.codex/skills/` | `~/.codex/skills/` |
| `agents` | `.agents/skills/` | `~/.agents/skills/` |

示例：

```bash
# 工程内同时接入 Claude Code 和 opencode（团队共享，随仓库提交）
./install.sh --target . --agent claude,opencode

# 把 Skill 装到本机所有支持 agent 的用户级目录（跨工程生效）
./install.sh --target . --agent all --scope user
```

curl 远程安装时参数经 `bash -s --` 原样透传，直接追加即可：

```bash
curl -fsSL https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.sh | \
  bash -s -- --target . --agent claude,opencode
```

注：pi / opencode / Codex 也会读取 `.agents/skills/`，所以即使不指定它们也能发现 Skill；`--agent` 用于写入各 agent 的原生首选路径。project 作用域的 agent 目录会进入 Git，适合团队共享；user 作用域只对当前用户生效。

安装器幂等且非破坏性：默认保留已存在文件，只有显式传入 `--force` 才覆盖。

## 安装内容

核心结构：

```text
AGENTS.md                         # 轻量上下文路由入口
docs/engineering/                # 当前工程自己的特殊规则
  index.md                       # 渐进式披露索引
  project.md
  architecture.md
  coding.md
  testing.md
  performance.md
  git.md
  tooling.md
.rsi/                            # RSI 安全策略（protected files / 变更预算 / 门禁）
  policy.yaml
  README.md
.agents/skills/
  pm-workers-engineering/
    SKILL.md                     # PM-Workers 通用工程 Skill
    references/
      context-disclosure.md
      layout-adapter.md
      project-onboarding.md         # 基础设施发现程序（扫描/询问 → tooling/testing 规则）
      verdict-schema.md             # Reviewer 结构化 verdict 规范
      agents/
        pm.md
        coder.md
        reviewer.md
```

使用 `--agent` 时，Skill 还会按参数表复制到 `.claude/skills/`、`.pi/skills/`、`.kimi/skills/`、`.opencode/skills/`、`.codex/skills/` 等对应目录。

`init` 模式还会创建 `src/`、`tests/`、`docs/`、`decisions/`、`issues/`、`conversations/`、`output/`、`progress/`、`scripts/`、`tmp/`、`evals/results/`（及 `evals/` 索引）。

## 使用方法

### 1. 安装后补齐工程规则

安装完成后，填写目标工程中的 `docs/engineering/index.md`，以及只与本工程相关的规则文件（架构、编码、测试、性能、Git、工具链）。这些规则是 L1 层资产，也是 RSI 闭环默认允许自动改进的对象。

也可以不手填：Skill 内置基础设施 onboarding 程序（`project-onboarding.md`）——首个涉及构建/测试的任务触发时，agent 会自动处理：

- **已有工程（adopt）**：扫描 manifest、CI 配置、测试框架等仓库证据，起草 `tooling.md` / `testing.md`，未覆盖项标记 `UNKNOWN` 并向你确认；
- **新工程（init）**：推荐主流技术栈并询问确认，选择结果写入规则文件，重要选型记入 `decisions/`。

硬性规则：agent 不得臆造 build/test 命令——规则文件和仓库证据都缺时会停下来问你（SKILL.md §13 停机条件）。spec/plan 只引用规则文件，不重复承载基础设施信息。

### 2. 调用 Skill 启动多 agent 开发

在已初始化的工程中启动 agent 会话，用一句话发起任务即可。Skill 的激活方式因 agent 而异：

| Agent | 激活方式 |
|---|---|
| Claude Code | 斜杠命令 `/pm-workers-engineering`，或任务匹配 description 时自动触发 |
| pi | `/skill:pm-workers-engineering`（可带参数），或自动触发 |
| Codex | `$pm-workers-engineering` 提及，或自动触发 |
| opencode | 原生 `skill` 工具自动触发；也可直接说「use the pm-workers-engineering skill」 |
| Kimi / Kimi Code | 任务匹配 description 时自动触发；或在提示词中显式指定 Skill 路径 |
| 其他 agent | 在提示词中显式引用 `SKILL.md` 路径（见下方推荐提示词） |

对话触发词： Skill 的 description 已内置触发条件——在对话中提出「用 pm-workers 模式开发」「PM-Workers 开发模式」「PM/Coder/Reviewer 多角色开发」等说法，支持自动激活的 agent 会自行加载该 Skill，无需记命令。

推荐启动提示词（显式锚定流程，任何 agent 都适用）：

```text
按照 pm-workers-engineering SKILL.md 的 PM-Workers 流程完成以下需求：

需求：<一句话目标>
任务来源：<可选——plan/spec/设计文档路径，如 docs/specs/xxx.md；或 issues/ 记录>
约束：<可选，如“不改公开 API”、“不新增第三方依赖”>
验收：<可选，如“新增功能需有测试覆盖”>

要求：PM 拆解 → Coder TDD → Reviewer 对抗审阅；里程碑必须拿到
MILESTONE ACCEPTED；每个里程碑决定按 verdict-schema.md 输出 YAML verdict
到 evals/results/；完成后给出 PM 汇报（DONE / PARTIAL / BLOCKED）。
```

Skill 带参数调用（支持斜杠命令的 agent）：参数会直接传给 Skill，可用于指定 plan/spec：

```text
# pi
/skill:pm-workers-engineering docs/specs/cache-ttl.md

# Claude Code
/pm-workers-engineering docs/specs/cache-ttl.md

# Codex
$pm-workers-engineering docs/specs/cache-ttl.md
```

指定了任务来源文档时，PM 会先读该文档并以它为需求/范围/验收的准绳，而不是仅凭一句话需求拆解。

多 agent 架构在任务内自动运转：

```text
Request → PM 拆解 → Coder TDD → Coder 自审 → Reviewer 对抗式审阅
        → Coder 修复/举证 → Reviewer 验证 → 里程碑验收 → PM 汇报
```

- 运行环境支持子代理时（如 Claude Code subagents、Kimi Code Agent 工具、pi subagent），PM / Coder / Reviewer 会以逻辑独立的角色执行；不支持时按顺序扮演，但 Reviewer 验收门禁不可省略。
- Agent 工作时的上下文加载顺序：`AGENTS.md` → `docs/engineering/index.md` → 任务相关规则 → Skill 角色 references（渐进式披露）。
- 里程碑必须经 Reviewer 验收（`MILESTONE ACCEPTED`）才算完成，不允许实现阶段自我批准。

> 当前版本为「单任务全自动」：每次任务需发起一次。跨任务无人值守循环（`rsi-loop`）见下方 Phase 5。

### 3. RSI 自我改进闭环（Phase 0-5 已实施）

当前版本包含 PM-Workers 静态协作协议；递归自我改进回路的完整设计见 [docs/rsi-design.md](docs/rsi-design.md)，分阶段实施：

| Phase | 内容 | 状态 |
|---|---|---|
| 0 | 三层自改进边界（L1 规则 / L2 Skill / L3 Harness）+ 安全门禁 | ✅ 已实施（`.rsi/policy.yaml`） |
| 1 | 结构化 Reviewer verdict + 结果落账 `evals/results/` | ✅ 已实施（`verdict-schema.md`） |
| 2 | eval 任务集 + pass@1 基线（RSI 的"损失函数"） | ✅ 已实施（`evals/`，20 任务 + `run-eval.sh`，基线 20/20） |
| 3 | retro 归因 + L1 规则回写（第一次完整闭环） | ✅ 已实施（`progress/retro/`、`scripts/retro-aggregate.py`、提案 P1-P3 已落地） |
| 4 | L2 Skill 自改进（eval 驱动） | ✅ 已实施（SKILL.md v1.1.0，RED 证据最小形式，eval 验证） |
| 5 | `rsi-loop` skill 无人值守循环（agent 内调用，shell 仅作可选调度薄壳） | ✅ 已实施（`skills/rsi-loop/`、`run-loop.sh`、`scripts/rsi-protect.sh`，observe-only 5 轮试跑） |

核心原则：任何自改进变更必须经 eval 验证不退化才可合并；eval 任务集与评分脚本列入 protected files，永不自动变异；一切变异走 git 提交，可逐轮回滚。

运行环境配置：`run-loop.sh` 按 `--agent-cmd` → `RSI_AGENT_CMD` → `RSI_AGENT_CANDIDATES`（环境变量或 `progress/loop/agent.env`）→ 内置默认列表 的顺序选择 agent CLI；只把本机实际可用的 agent 列入候选（本仓库即 `progress/loop/agent.env` 的 `RSI_AGENT_CANDIDATES="pi kimi"`）。无人值守场景用 `--headless`（pi 走 `-p`，kimi 走 `-p --print`）。

### 4. 最小闭环（Min-Loop）—— 轻量 spec 执行闭环

完整 RSI 机制（rsi-loop）的**零配置替代**：token 预算有限、只需要「spec → 验收 → 报告」闭环的真实工程，不需要 eval / retro / skill 进化。

- **入口（skill 优先）**：`min-loop` skill。对话触发词：「最小闭环」「min-loop」「跑 spec」。
  - pi：`/skill:min-loop docs/specs/xxx.md`
  - 其他 agent（kimi/claude/opencode/codex）：提示词中显式指定 SKILL.md 路径
- **机制**：同一 agent 会话内按序扮演 PM → Coder(TDD: RED→GREEN) → Reviewer（对抗审阅），达到 `MILESTONE ACCEPTED` 后写报告 `output/specs/<spec>.md` 并汇报 DONE / PARTIAL / BLOCKED。
- **批处理（可选）**：`./run-specs.sh` 遍历 `docs/specs/*.md`，headless 逐个调用（agent 解析同 `run-loop.sh`：`--agent-cmd` / `RSI_AGENT_CMD` / `RSI_AGENT_CANDIDATES`）。
- **零机制承诺**：无子代理、无 state/round/verdict 文件、无 eval、无 retro、无门禁回写；停机条件最小集（build/test 命令未知或验收不可判定时停下询问，不臆造）。
- **与 rsi-loop 的关系**：rsi-loop 的每一轮子代理工作 ≈ 一次 min-loop；min-loop 只交付、不进化，是 rsi-loop 的最小切片。
- **实现分支**：本仓库 `feat/min-loop` 分支承载最小闭环的完整实现（`skills/min-loop/SKILL.md` + `run-specs.sh` + 安装分发）；**main 分支当前不包含该代码**，本章节为说明入口，使用前请 `git checkout feat/min-loop`（或将其合并回 main 后此处同步更新）。

## 设计原则

### 1. Skill 与工程规则分离

Skill 只定义稳定的协作协议：PM 拆解与编排、Coder TDD、Reviewer 对抗式审阅、里程碑门禁、简洁性和资源约束。

具体项目的语言、框架、架构、测试命令、性能上限、Git 流程等，放在 `docs/engineering/`，由 `index.md` 按任务需要渐进加载。

### 2. AGENTS.md 是路由器，不是大而全手册

Agent 首先读取 `AGENTS.md`，再读取 `docs/engineering/index.md`，只加载当前任务需要的规则和源码上下文。

### 3. 已有工程不强制迁移

`adopt` 模式不会创建或重排 `src/` / `tests/` 等源码结构。PM-Workers Skill 会从仓库已有的 manifest、README、CONTRIBUTING、CI、测试配置和源码布局中发现等价结构。

### 4. 幂等和非破坏性

安装器默认保留已存在文件。只有显式传入 `--force` 才覆盖安装器管理的模板文件。

## 开发与测试

本仓库自身的冒烟测试：

```bash
./tests/install-smoke.sh        # macOS / Linux
pwsh ./tests/install-smoke.ps1  # Windows（PowerShell 5.1+ / pwsh 7+）
```

覆盖：`init`/`adopt` 自动模式判断、核心文件落位（含 `.rsi/` 策略与 `evals/results/`）、已有工程不被重排、重复执行的非破坏性、`--agent` 多目标分发与重复传参、未知 agent 的 fail-fast。

## 旧入口

`init-prompt-for-soft-engieneering.md`（已废弃，见 `init-prompt-for-soft-engineering.md`）和 `team-launcher` 保留用于兼容旧工作流；新工程建议直接使用 `install.sh`。

## 许可证

[MIT](LICENSE)
