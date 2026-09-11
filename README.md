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
--check                只检测必需 Skill 是否齐备，不写任何文件
--skip-env             跳过环境依赖构建阶段
--dry-run-env          只打印将执行的依赖安装命令，不实际执行
--strict-env           环境依赖构建失败时以退出码 3 结束（默认仅告警）
--agent LIST           额外分发 Skill 到指定 agent 目录（逗号分隔，可重复；支持 all；
                       PowerShell 侧 -Agent 不支持重复传参，用逗号分隔或数组）
--scope project|user   agent 目录的作用域：工程内 / 用户主目录（默认 project）
-h, --help             查看完整帮助
```

退出码契约（bash 与 PowerShell 一致）：

| 退出码 | 含义 |
|---|---|
| 0 | 安装成功（env 阶段失败默认不改变退出码） |
| 1 | `--check` 检测到 skill 缺失/不完整 |
| 2 | 用法错误（未知选项、缺参数值、非法 `--mode`/`--scope`、`--check` 与 `--no-skill` 同用） |
| 3 | `--strict-env` 下环境依赖构建失败 |

注：PowerShell 参数绑定错误（如 `-Target` 缺值）由运行时产生，退出码为 1，属已知偏差；其余用法错误两侧均为 2。

### 按目标 agent 分发 Skill

默认只安装到通用标准路径 `.harness/skills/`。用 `--agent` 追加各 agent 的原生 skill 目录（已按各官方文档核实）：

| `--agent` | project 作用域（默认） | user 作用域（`--scope user`） |
|---|---|---|
| `claude` | `.claude/skills/` | `~/.claude/skills/` |
| `pi` | `.pi/skills/` | `~/.pi/agent/skills/` |
| `kimi` / `kimi-code` | `.kimi/skills/` | `~/.kimi/skills/` |
| `opencode` | `.opencode/skills/` | `~/.config/opencode/skills/` |
| `codex` | `.codex/skills/` | `~/.codex/skills/` |
| `agents` | `.harness/skills/` | `~/.harness/skills/` |

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

注：pi / opencode / Codex 也会读取 `.harness/skills/`，所以即使不指定它们也能发现 Skill；`--agent` 用于写入各 agent 的原生首选路径。project 作用域的 agent 目录会进入 Git，适合团队共享；user 作用域只对当前用户生效。

安装器幂等且非破坏性：默认保留已存在文件，只有显式传入 `--force` 才覆盖。

### 必需 Skill 自检与自愈

安装器把源仓库 `skills/` 下的每个目录视为必需 Skill（当前为 `pm-workers-engineering`、`rsi-loop`）。`--check`（PowerShell 为 `-Check`）只检测不写入：逐项输出 `ok` / `incomplete` / `missing` 状态行，全部齐备退出码 0，有缺失退出码 1 并打印修复命令，参数错误（如与 `--no-skill` 同用）退出码 2。

```bash
./install.sh --target . --check          # 检测 .harness/skills/
./install.sh --target . --check --agent claude   # 同时检测 .claude/skills/
```

Skill 目录不完整（如 `SKILL.md` 被删）时，直接重跑安装器即可补齐——安装器按文件级 `keep` 语义只补缺失文件，不覆盖已有定制。

初始化生成的 `AGENTS.md` 内置了同一套自检指引：agent 在工程内开始任务前会验证必需 Skill，发现缺失时先向用户报告并在确认后修复（无人值守且已授权时可直接执行），不会用自创流程顶替 PM-Workers。

### 环境依赖自动构建（install 阶段）

安装器在文件落位后自动执行环境依赖构建（`--skip-env` 跳过）：

1. **约定脚本优先**：发现 `scripts/setup-env.sh`（bash）/ `scripts/setup-env.ps1`（PowerShell）时执行它——harness 只发现和执行，不臆造内容；
2. **生态探测兜底**：无约定脚本时，按仓库证据探测 `package.json`（npm ci / pnpm / yarn，按锁文件消歧；含 `scripts.build` 时追加构建验证）、`requirements.txt`（仅在 `.venv` 已存在时安装）、`pyproject.toml`（poetry/uv 按锁文件）、`go.mod`、`Cargo.toml`、`pom.xml`、`build.gradle(.kts)`、`CMakeLists.txt`（有 vcpkg/conan 时转人工），并调用对应包管理器只装依赖不构建产物；
3. **不确定即停**：工具缺失、锁文件歧义、无 venv 等情况记为 UNKNOWN（写入报告，不臆造命令），真正的确认发生在 agent 期 onboarding；
4. **报告落账**：全过程（命令、退出码、耗时、UNKNOWN 清单）写入 `.harness/reports/env-report.md`，agent 期复用为证据；
5. **安全边界**：默认失败仅告警不阻断（`--strict-env` 升级为退出码 3）；`--dry-run-env` 只打印不执行；bash 侧命令带 10 分钟超时（无 `timeout` 命令的平台不限制）；不重试、不回滚已写文件。

`--check` 模式完全不执行 env 阶段（零写入承诺不变）。

### run-loop headless 支持矩阵

`run-loop.sh --headless` 已按各 CLI 官方用法适配：`pi -p`、`kimi -p`、`claude -p`、`codex exec`、`opencode run`；未适配的 CLI 回退为「整条提示词作为单个参数传入」并在 stderr 告警。

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
  platform/                      # 平台知识卡（L1P，永不自动 commit，预留知识库导出）
.rsi/                            # RSI 安全策略（protected files / 变更预算 / 门禁）
  policy.yaml
  README.md
.harness/skills/
  pm-workers-engineering/
    SKILL.md                     # PM-Workers 通用工程 Skill
    references/
      context-disclosure.md
      layout-adapter.md
      project-onboarding.md         # 基础设施发现程序（扫描/询问 → tooling/testing 规则）
      verdict-schema.md             # Reviewer 结构化 verdict 规范
      platform-knowledge.md         # L1P 平台知识卡（永不自动 commit）
      agents/
        pm.md
        coder.md
        reviewer.md
```

使用 `--agent` 时，Skill 还会按参数表复制到 `.claude/skills/`、`.pi/skills/`、`.kimi/skills/`、`.opencode/skills/`、`.codex/skills/` 等对应目录。

`init` 模式还会创建 `src/`、`tests/`、`docs/`、`decisions/`、`issues/`、`conversations/`、`output/`、`progress/`、`scripts/`、`tmp/`、`evals/results/`（及 `evals/` 索引）。

## 使用方法

### 1. 安装后补齐工程规则

安装完成后，填写目标工程中的 `docs/engineering/index.md`，以及只与本工程相关的规则文件（架构、编码、测试、性能、Git、工具链）。这些规则是 L1 层资产，也是 RSI 闭环默认允许自动改进的对象（`docs/engineering/platform/` 下的平台知识卡除外——它们属 L1P 层，永不自动 commit）。

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
| 0 | 三层自改进边界（L1 规则 / L2 Skill / L3 Harness）+ 安全门禁 | ✅ 已实施（`.harness/.rsi/policy.yaml`） |
| 1 | 结构化 Reviewer verdict + 结果落账 `evals/results/` | ✅ 已实施（`verdict-schema.md`） |
| 2 | eval 任务集 + pass@1 基线（RSI 的"损失函数"） | ✅ 已实施（`evals/`，20 任务 + `run-eval.sh`，基线 20/20） |
| 3 | retro 归因 + L1 规则回写（第一次完整闭环） | ✅ 已实施（`progress/retro/`、`scripts/retro-aggregate.py`、提案 P1-P3 已落地） |
| 4 | L2 Skill 自改进（eval 驱动） | ✅ 已实施（SKILL.md v1.1.0，RED 证据最小形式，eval 验证） |
| 5 | `rsi-loop` skill 无人值守循环（agent 内调用，shell 仅作可选调度薄壳） | ✅ 已实施（`skills/rsi-loop/`、`run-loop.sh`、`scripts/rsi-protect.sh`，observe-only 5 轮试跑） |
| — | L1P 平台知识层（永不自动 commit，预留 Open Viking 等知识库导出） | ✅ 已实施（2026-09-10） |
| — | 约束冲突同步检查（`references/rule-conflict-check.md`；可解自动优化 / 不可解提交用户裁决） | ✅ 已实施（2026-09-10） |
| — | 事件触发评估（git hook 防抖置标 + `trigger.sh` 消费；休眠期由 OS 调度器拉起，见设计 §4.7） | ✅ 已实施（2026-09-10） |

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
./tests/trigger-smoke.sh        # 事件触发 hook 的置标/防抖/消费生命周期
```

覆盖：`init`/`adopt` 自动模式判断、核心文件落位（含 `.harness/.rsi/` 策略与 `evals/results/`）、已有工程不被重排、重复执行的非破坏性、`--agent` 多目标分发与重复传参、未知 agent 的 fail-fast、`--check` 三态（missing / ok / incomplete）与零写入保证、退出码契约（用法错误 = 2）、env 阶段四态（dry-run 不执行 / 失败仅告警 / `--strict-env` 退出 3 / `--skip-env` 零写入）。

## 旧入口

`init-prompt-for-soft-engieneering.md`（已废弃，见 `init-prompt-for-soft-engineering.md`）和 `team-launcher` 保留用于兼容旧工作流；新工程建议直接使用 `install.sh`。

## 许可证

[MIT](LICENSE)
