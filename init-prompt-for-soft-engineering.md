# 代码开发工程初始化

该工程初始化方式已从“大型初始化 Prompt”迁移为可重复执行的安装器。

推荐直接运行：

```bash
curl -fsSL https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.sh | bash -s -- --target .
```

默认 `auto` 模式会自动判断：

- 新/近空工程 → `init`：创建标准工程目录、索引、`AGENTS.md`、工程规则目录和 PM-Workers / rsi-loop Skills。
- 已有工程 → `adopt`：只接入 Agent 与工程规则配置，不强制改变源码布局。

显式初始化：

```bash
./install.sh --target ./my-project --mode init
```

接入已有工程：

```bash
./install.sh --target . --mode adopt
```

Windows（PowerShell 安装器）：

```powershell
.\install.ps1 -Target .\my-project -Mode init
```

## 目录约定

初始化/接入后，工程遵循统一目录语义（详见 `AGENTS.md` 与 `docs/engineering/index.md`）：

- `docs/engineering/` — 工程规则（按需渐进加载）
- `decisions/` — 架构与技术决策
- `issues/` — 缺陷与问题记录
- `progress/` — 任务与里程碑状态、RSI 循环状态
- `evals/` — 评估任务、结构化 verdict、基线
- `.rsi/` — RSI 安全策略（protected files、change budget、门禁级别）

## RSI 循环

工程接入后可按 `docs/rsi-design.md` 启用递归自我改进闭环：

- PM-Workers 协议负责「做任务」（`.agents/skills/pm-workers-engineering/`）
- rsi-loop skill 负责「跑循环」（`.agents/skills/rsi-loop/`，无人值守可选 `run-loop.sh`）
- 变异受 `.rsi/policy.yaml` 门禁与 protected files 保护
