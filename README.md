# project-init-scripts

工程初始化与 Agent 软件开发协作配置。

目标：用一个安装命令把工程接入统一的目录约定、渐进式工程规则披露，以及 PM-Workers（PM / Coder / Reviewer）开发流程，同时不把某个具体语言、框架或工程的特殊规范硬编码进 Skill。

## 推荐：单命令安装

在目标工程目录执行：

```bash
curl -fsSL https://raw.githubusercontent.com/turbin/project-init-scripts/main/install.sh | bash -s -- --target .
```

默认 `--mode auto`：

- 空/近空目录：按 `init` 模式创建完整标准工程骨架。
- 已有工程：按 `adopt` 模式接入 Agent 配置，不重排已有源码结构。

### 显式初始化新工程

```bash
curl -fsSL https://raw.githubusercontent.com/turbin/project-init-scripts/main/install.sh | \
  bash -s -- --target ./my-project --mode init
```

### 接入已有工程

```bash
curl -fsSL https://raw.githubusercontent.com/turbin/project-init-scripts/main/install.sh | \
  bash -s -- --target . --mode adopt
```

### 本地 clone 后执行

```bash
git clone https://github.com/turbin/project-init-scripts.git
./project-init-scripts/install.sh --target ./my-project --mode init
```

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

`init` 模式还会创建 `src/`、`tests/`、`docs/`、`decisions/`、`issues/`、`conversations/`、`output/`、`progress/`、`scripts/`、`tmp/` 及对应索引。

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

## 安装器参数

```text
--target PATH
--mode auto|init|adopt
--force
--no-git
--no-skill
```

查看完整帮助：

```bash
./install.sh --help
```

## 旧 Prompt

`init-prompt-for-soft-engieneering.md` 和 `team-launcher` 保留用于兼容旧工作流；新工程建议直接使用 `install.sh`。
