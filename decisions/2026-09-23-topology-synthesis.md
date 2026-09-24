# 2026-09-23-topology-synthesis — 图拓扑空缺的按需合成 + 落盘缓存（architecture-topology skill）

- 来源：用户 2026-09-23 决策——大工程禁用 graphify 后缺失的图拓扑能力「由模型调用工具现算补全」；形态选 ③（按需现算 + 落盘缓存）
- 目标层：L2（新增 `.harness/skills/architecture-topology/`，skill-scope 判 `user`/all）+ L3 邻接（install.sh/install.ps1 受管段注册、`.harness/skill-scope.txt`、README）
- 状态：adopted

## 背景

能力盘点（同日实测）：

- graphify 的独占层是**图拓扑**（社区/聚类、god nodes、`path "A" "B"`、跨仓库 `merge-graphs`、wiki），在大型工程上退化（用户判断），已由规模门禁用；
- zvec 覆盖「本地 md/txt 的跨文档语义」（hybrid 检索，markdown 保标题结构），但无图；PDF/Office 不索引；
- CodeGraph 覆盖调用图/影响面（当前未安装、无 `.codegraph/` 索引），不摄入文档、无语义层。

⇒ 大工程的图拓扑走「按需合成 + 缓存」：**不是替代索引，而是明确标注生成时间的缓存快照**。

## 决策

1. **形态 ③**：按需现算 + 落盘缓存 `docs/architecture/topology.md`；frontmatter 记 `generated_at` + `basis`（git HEAD、构建清单摘要、跟踪文件数），basis 任一变化 ⇒ 缓存失效 ⇒ 重算；回答时必须报缓存年龄。
2. **以退役 skill 为基线改造**：`generating-architecture-design-docs`（备份 `tmp/replaced-skills/`）保留其构建清单主干、限额采样、交叉验证、`未确认` 标注、`scripts/mermaid-check.js` 与真渲染纪律；收窄为单一拓扑缓存，加限额（40 模块 / 10 枢纽 / 5 路径 / 每模块 10 文件）。
3. **落位**：`.harness/skills/architecture-topology/`（homegrown，来源记于 `ORIGIN.md`，非 vendor 无上游 LICENSE）；`.harness/skill-scope.txt` 判 `user`/all；受管 AGENTS.md「User-level skills」段注册一行（bash/ps1 两侧）。
4. **边界**：CodeGraph 管代码级调用路径与影响面；图语法归 `mermaid-diagrams`、C4 文档约定归 `c4-architecture`；graphify 可用且图新鲜时优先 graphify——本 skill 只是规模门禁用后的 fallback。

## 验证

- `./tests/install-smoke.sh` / `powershell -File tests/install-smoke.ps1` → PASS（本次变更后执行，记录见会话）。
- 真实用户级分发：6 个 agent 用户目录出现该 skill（与 c4/mermaid 同机制）。

## 待办/边界

- 首次真实使用（某个被规模门禁用的大工程）尚未发生：合成质量、token 成本、缓存命中率需实战校准；`未确认` 项靠后续任务消化。
- 工作区级 `E:\workspace\AGENTS.md` §graphify 的工程级覆盖规则已同日补齐（①方案）。
- 本 skill 不替代 CodeGraph/zvec 的检索职责；`docs/architecture/topology.md` 是生成物，永不与 `docs/engineering/*` 手写规则混写。
