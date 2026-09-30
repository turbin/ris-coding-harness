# 2026-09-24 — 规模门 off 路由指向未安装的 CodeGraph，且 `.gitignore` 未忽略 `.codegraph/`

- 状态：open（安装与否**尚未决定**——2026-09-24 的 "off" 是关闭计划模式的指令，不是本 issue 的裁决；待用户答复）
- 严重级别：P3（路由指向不可用工具，agent 只能回退 grep/读文件；不破坏任何现有功能）
- 来源：2026-09-23→24 图拓扑与检索能力链收尾时发现（`6ee817c` 已把该路由文案写入受管段）

## 现象

1. **路由要一个不存在的工具**：
   - 已提交 `6ee817c` 的规模门 off 路由文案写的是
     "Use `zg query` (semantic retrieval) + CodeGraph (call graphs / blast radius) instead;
     use `zg` for cross-document semantics."；
   - 工作区 `E:\workspace\AGENTS.md` 的 §code-graph-intel 与 §Search routing 同样把 CodeGraph
     作为调用图/blast radius 的首选；
   - 但本机 `codegraph` CLI **不在 PATH**，`E:\workspace` 全深度**没有任何 `.codegraph/` 索引**。
   ⇒ 规模门 off 的大工程里，agent 按路由去找 CodeGraph 会落空。

2. **`.gitignore` 缺口**：仓库 `.gitignore` 模板忽略 `.zvec-grep/`（第 18 行）但**没有 `.codegraph/`**
   ⇒ 一旦给工程建索引，该目录会以未跟踪文件形式污染每个工程的 `git status`。
   （`graphify` 规模门的文件计数忽略清单已含 `.codegraph`，那是计数侧，不是 git 侧。）

## 证据（2026-09-24 实测）

- `command -v codegraph` → 未找到；`find E:/workspace -maxdepth 6 -name .codegraph` → 0 处。
- npm registry 可达：`npm view @colbymchenry/codegraph` → **1.6.0**；`node -v` v24.17.0、`npm -v` 11.13.0。
- pi 侧扩展已在位：`~/.pi/agent/extensions/codegraph.ts`（`codegraph_explore` 工具就绪，等 CLI + 索引）。
- 其余 agent（kimi/claude/opencode/codex）没有对应工具接入，只能经 Bash 调 CLI。

## 待办（用户决定启用时按序执行）

1. `npm i -g @colbymchenry/codegraph` → `codegraph version` 验证；
2. 逐工程 `codegraph init`（索引落 `<project>/.codegraph/`）。候选按价值排序：
   规模门 off 的大工程 `ino`(1575 文件) / `LobsterAI`(1870) / `zotero-android`(2159) /
   `kimi-code`(2518) / `turbo-pi-gateway`(2574)，以及本仓库(265)；
3. **同步补 `.gitignore` 模板**：`install.sh` 与 `install.ps1` 两侧各加 `.codegraph/`，冒烟断言；
4. 首次真实查询验证：pi 的 `codegraph_explore` 与 CLI `codegraph explore/callers/impact` 输出一致；
5. 回滚：各工程 `codegraph uninit`；卸载 `npm rm -g @colbymchenry/codegraph`。

## 影响面

- 不影响已提交功能：规模门 off 文案里的 CodeGraph 只是**首选**，agent 实际会按
  `codegraph` 自身扩展的降级约定退回内置工具（该约定写在 pi 扩展的 promptGuidelines 里），
  工作区 Search routing 也写了「无 `.codegraph/` 时用内置 read/grep 并建议 `codegraph init`」。
- 与 `decisions/2026-09-23-graphify-scale-gate.md` 的「off 路由 = 已定」互补：路由已定，
  但**被路由指向的工具尚未落地**，启用即闭环。
