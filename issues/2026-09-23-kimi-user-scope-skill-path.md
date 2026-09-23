# 2026-09-23 — kimi/kimi-code 用户级 Skill 安装目录与实际加载目录不一致

- 状态：resolved（2026-09-23 修复：bash/PowerShell 两侧用户级目录改为 `~/.kimi-code/skills`，随
  user 级 skill 分发机制一并落地）
- 严重级别：P2（`--scope user --agent kimi` 的 skill 可能静默落到不被加载的目录，
  装完不报错、也不生效）
- 来源：2026-09-23 用户要求「安装初始化时默认安装 c4-architecture /
  mermaid-diagrams 并替换同类 skill」时，核对 skill 分发路径发现

## 现象

- 安装器的 kimi / kimi-code 用户级 skill 目录写死为 `~/.kimi/skills`：
  `install.sh:203`（`kimi|kimi-code) … echo "$HOME/.kimi/skills"`）、
  `install.ps1:202`（`"kimi-code" = @{ project = ".kimi/skills"; user = ".kimi/skills" }`）。
- 本机实际形态：`~/.kimi/skills/` 只有 `graphify`；harness 的 skill
  （`pm-workers-engineering`、`rsi-loop`）与 `zvec-grep`、`project-init` 等都在
  `~/.kimi-code/skills/`。
- 本会话（kimi-code）实际暴露的用户级 skill 路径是
  `C:\Users\Administrator\.kimi-code\skills\…` 与 `C:\Users\Administrator\.agents\skills\…`，
  列表中没有 `~/.kimi/skills` 下的任何条目。

## 佐证

- 仓库自身把 `~/.kimi-code` 当作 Kimi Code home：`scripts/install-agent-hooks.py:6-7`
  （hook 寄宿 `~/.kimi-code/hooks/`、受管块写 `~/.kimi-code/config.toml`）、
  `scripts/compact-archive.py:60`、`scripts/session-recall.py:52`
  （均 `Path.home() / ".kimi-code"`）。
- README §5 表格与 §按目标 agent 分发 Skill 表格中，kimi/kimi-code 的 user 作用域
  同样写 `~/.kimi/skills/`——与上面同源，属同一处待定事实。

## 复现步骤（待执行）

1. `./install.sh --target . --scope user --agent kimi`（在任意已初始化工程内）；
2. 确认文件落到 `~/.kimi/skills/<skill>/SKILL.md`；
3. 新开 kimi-code 会话，查看可用 skill 列表是否出现该 skill。

结果分两种：

- **可见** → kimi-code 同时扫描 `~/.kimi` 与 `~/.kimi-code`，installer 行为正确，
  只需在 README 注明两者关系（本 issue 可关为「文档补充」）；
- **不可见** → installer 的 user 作用域写错目录，需修正。

## 结论（2026-09-23）：判为「不可见」，目录写错

修复前第 1-2 步的落位（`~/.kimi/skills/<skill>/SKILL.md`）可由代码直接确认；第 3 步
（新会话 skill 列表）**未重新执行**，但同会话的既有观测已足以定性：

- 本对话（kimi-code）实际暴露的用户级 skill 路径是
  `C:\Users\Administrator\.kimi-code\skills\…` 与 `C:\Users\Administrator\.agents\skills\…`，
  列表中没有 `~/.kimi/skills` 下的任何条目；
- `~/.kimi/skills/` 只剩历史遗留 `graphify`，其余 harness 相关 skill 全在
  `~/.kimi-code/skills/`；
- 仓库内所有 Kimi Code 相关路径都指向 `~/.kimi-code/`：
  `scripts/install-agent-hooks.py:6-7`、`scripts/compact-archive.py:60`、
  `scripts/session-recall.py:52`（均 `Path.home() / ".kimi-code"`，且支持
  `KIMI_CODE_HOME` 覆盖）。

因此 installer 的 user 作用域写错目录，需要修正——即原「待办（若确认不可见）」分支。

## 修复（已完成）

- `install.sh` 的 `skill_dest()` 中 `kimi|kimi-code` 的 user 分支改为
  `$USER_HOME/.kimi-code/skills`（`USER_HOME="${HOME:-}"`）；
- `install.ps1` 的 `$AgentMap` 中 `"kimi"` / `"kimi-code"` 的 `user` 改为
  `.kimi-code/skills`（用户 home 取 `$env:USERPROFILE` → `$env:HOME` 回退）；
- project 作用域仍为 `<target>/.kimi/skills`（工程内路径不变）；
- 未保留对 `~/.kimi/skills` 的兼容探测：该目录在本机只剩一个不再使用的 skill，
  双写会让「装到哪」不可预期；确需旧路径时手工复制即可。

## 验证

- `tests/install-smoke.sh`：`--scope user --agent claude,kimi-code`（隔离 HOME）断言
  `$FAKEHOME/.kimi-code/skills/<skill>/SKILL.md` 存在、`$FAKEHOME/.kimi/skills` 不存在；
  默认安装（无 `--agent`）断言 user 级 skill 出现在
  `.kimi-code/skills/`、`.claude/skills/`、`.pi/agent/skills/`、`.config/opencode/skills/`、
  `.codex/skills/`、`.agents/skills/` 六处。整体 PASS。
- `tests/install-smoke.ps1`：新增同样的 `-Scope user -Agent claude,kimi-code` 覆盖
  （子进程隔离 `USERPROFILE`/`HOME`/`KIMI_CODE_HOME`）。整体 PASS。
- README §按目标 agent 分发 Skill 表格、§5 hook 表格与本节结论一致（均为
  `~/.kimi-code/`）。

## 影响面

本次变更（`decisions/2026-09-23-diagram-skills-vendoring.md` 的方案 A′）的 user 级
分发正是走这套用户级目录映射，因此该路径的正确性已从「待定事实」升级为本机制的
组成部分；子 agent 挂载 skill 方案若涉及用户级分发，可直接复用本结论。
