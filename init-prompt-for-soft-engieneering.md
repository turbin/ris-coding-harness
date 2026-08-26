# 代码开发工程初始化（兼容入口）

该工程初始化方式已从“大型初始化 Prompt”迁移为可重复执行的安装器。

推荐直接运行：

```bash
curl -fsSL https://raw.githubusercontent.com/turbin/project-init-scripts/main/install.sh | bash -s -- --target .
```

默认 `auto` 模式会自动判断：

- 新/近空工程 → `init`：创建标准工程目录、索引、`AGENTS.md`、工程规则目录和 PM-Workers Skill。
- 已有工程 → `adopt`：只接入 Agent 与工程规则配置，不强制改变源码布局。

显式初始化：

```bash
./install.sh --target ./my-project --mode init
```

显式接入已有工程：

```bash
./install.sh --target . --mode adopt
```

## 初始化后的规则体系

- `AGENTS.md`：轻量路由入口，不承载所有工程规范。
- `docs/engineering/index.md`：项目特殊规范索引，按任务渐进式披露。
- `docs/engineering/*.md`：架构、编码、测试、性能、Git、工具链等项目规则。
- `.agents/skills/pm-workers-engineering/SKILL.md`：通用 PM-Workers 开发协作 Skill。
- `progress/`：长时任务与里程碑状态。
- `decisions/`：重要架构/技术决策。
- `issues/`：问题、Bug 与复现记录。
- `conversations/`：仅在用户明确要求时保存对话。

完整行为和参数见 `README.md` 与 `./install.sh --help`。
