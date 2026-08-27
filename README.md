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
```

对应冒烟测试：`pwsh ./tests/install-smoke.ps1`。

### 安装器参数

```text
--target PATH          目标工程目录（默认 .）
--mode auto|init|adopt 初始化模式（默认 auto）
--force                覆盖安装器管理的模板文件
--no-git               不初始化 Git 仓库
--no-skill             不安装 PM-Workers Skill
-h, --help             查看完整帮助
```

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
      agents/
        pm.md
        coder.md
        reviewer.md
```

`init` 模式还会创建 `src/`、`tests/`、`docs/`、`decisions/`、`issues/`、`conversations/`、`output/`、`progress/`、`scripts/`、`tmp/`、`evals/results/`（及 `evals/` 索引）。

## 使用方法

### 1. 安装后补齐工程规则

安装完成后，填写目标工程中的 `docs/engineering/index.md`，以及只与本工程相关的规则文件（架构、编码、测试、性能、Git、工具链）。这些规则是 L1 层资产，也是 RSI 闭环默认允许自动改进的对象。

### 2. Agent 进入工程工作

Agent 在已初始化的工程中按以下顺序工作：

1. 读取 `AGENTS.md` 作为上下文路由入口；
2. 读取 `docs/engineering/index.md`，只加载当前任务需要的规则文件；
3. 使用 `.agents/skills/pm-workers-engineering/SKILL.md` 执行 PM-Workers 流程；
4. PM / Coder / Reviewer 的详细职责按角色从 Skill references 渐进加载。

开发流程：

```text
Request → PM 拆解 → Coder TDD → Coder 自审 → Reviewer 对抗式审阅
        → Coder 修复/举证 → Reviewer 验证 → 里程碑验收 → PM 汇报
```

里程碑必须经 Reviewer 验收（`MILESTONE ACCEPTED`）才算完成，不允许实现阶段自我批准。

### 3. RSI 自我改进闭环（设计中）

当前版本包含 PM-Workers 静态协作协议；递归自我改进回路的完整设计见 [docs/rsi-design.md](docs/rsi-design.md)，分阶段实施：

| Phase | 内容 | 状态 |
|---|---|---|
| 0 | 三层自改进边界（L1 规则 / L2 Skill / L3 Harness）+ 安全门禁 | ✅ 已实施（`.rsi/policy.yaml`） |
| 1 | 结构化 Reviewer verdict + 结果落账 `evals/results/` | ✅ 已实施（`verdict-schema.md`） |
| 2 | eval 任务集 + pass@1 基线（RSI 的"损失函数"） | 设计完成 |
| 3 | retro 归因 + L1 规则回写（第一次完整闭环） | 设计完成 |
| 4 | L2 Skill 自改进（eval 驱动） | 设计完成 |
| 5 | `rsi-loop` skill 无人值守循环（agent 内调用，shell 仅作可选调度薄壳） | 设计完成 |

核心原则：任何自改进变更必须经 eval 验证不退化才可合并；eval 任务集与评分脚本列入 protected files，永不自动变异；一切变异走 git 提交，可逐轮回滚。

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

覆盖：`init`/`adopt` 自动模式判断、核心文件落位、已有工程不被重排、重复执行的非破坏性。

## 旧入口

`init-prompt-for-soft-engieneering.md` 和 `team-launcher` 保留用于兼容旧工作流；新工程建议直接使用 `install.sh`。
