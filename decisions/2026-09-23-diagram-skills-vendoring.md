# 2026-09-23-diagram-skills-vendoring — vendor 图示/架构文档技能（c4-architecture + mermaid-diagrams）

- 来源：用户 2026-09-23 需求「使用这两个 skill 替换原先功能重叠的 skill」→ 追加「更新 install 脚本，安装初始化过程中默认安装这两个 skill 并完全替换原先同类 skill」
- 目标层：L2（新增 `.harness/skills/c4-architecture/`、`.harness/skills/mermaid-diagrams/`）+ L3 邻接（install.sh / install.ps1 受管路由段、README、tests）
- 状态：adopted（集成落地；同日追加方案 A′ 改为用户级唯一分发，见下）

## 动机

原先承担「架构文档 / 图示」职责的是用户级 skill `generating-architecture-design-docs`（kimi-code 用户目录）。
harness 侧此前**没有任何图示或架构文档技能**（`grep -riI "mermaid|c4-architecture|architecture diagram"` 排除 tmp/conversations 后零命中），
故本次对目标工程是「新增能力」，对用户环境是「同类替换」。

## 决策

1. **两个 skill 均按上游原样 vendor**，不做预先改造：仅丢弃上游 `README.md`（面向用户的 SKILL.md 副本）、frontmatter 增加 `version`/`upstream` 溯源字段，其余逐字节一致。
   理由：用户明确要求「先替换、后讨论优化」；输出位置映射与渲染校验属改造项，另行决策。改造点与已知冲突写入各自 `UPSTREAM.md`。
2. **安装侧零机制改动**：installer 本就按 `$SOURCE_ROOT/skills/*/` 全量枚举，新增目录自动进入 `.harness/skills/` 与每个 `--agent` 目标，并自动纳入 `--check` 必检项与 manifest 的 `skills` 列表；
   脚本改动仅为受管 AGENTS.md 路由段的 2 行注册（bash/ps1 两侧同步）。
3. **「完全替换原先同类 skill」的核查结论**：安装器从未分发过同类 skill——`.harness/skills/` 历史上仅 `pm-workers-engineering` / `ponytail` / `rsi-loop`，且 `git log --all -- '*generating-architecture-design-docs*'` 为空。
   因此 harness 侧没有可删除对象；被替换的是用户级 `generating-architecture-design-docs`（已退役，备份于 `tmp/replaced-skills/`）。
4. **分发方案 A′（2026-09-23 追加，覆盖上条 2 的「零机制改动」）**：两个 skill 判为**用户级（user scope）唯一权威**，
   仓库侧不再向目标工程 `.harness/skills/` 或工程内 `--agent` 目录下发它们，改为只装到各 agent 的**用户级** skill 目录。
   机制：新增仓库级清单 `.harness/skill-scope.txt`（纯文本，`<skill> <scope> [agents]`，`#` 注释），
   未列出的 skill 一律按现状 `project` 处理——默认行为不变、回归面最小；
   两个 skill 均标 `user all`（`all` = claude / pi / kimi / kimi-code / opencode / codex / agents，kimi 与 kimi-code 同目录、按路径去重）。
   理由：用户级副本是跨工程生效的唯一一份，避免「用户级 + 工程内」两份并存导致 agent 触发同名 skill 时来源不确定（原「权威层未定（乙）」）。
   user 级落点用 `skill_dest <agent> --scope user` 那套映射，并修掉 kimi/kimi-code 的 user 目录
   （`~/.kimi/skills` → `~/.kimi-code/skills`，见 `issues/2026-09-23-kimi-user-scope-skill-path.md`）。

## 落地内容

### 阶段一（原方案：随工程分发）

- `.harness/skills/c4-architecture/`：SKILL.md + `references/{c4-syntax,common-mistakes,advanced-patterns}.md` + LICENSE + UPSTREAM.md。
- `.harness/skills/mermaid-diagrams/`：SKILL.md + `references/*.md`（7 个图类型）+ LICENSE + UPSTREAM.md。
- 上游：`softaworks/agent-toolkit @ 3027f20f3181758385a1bb8c022d4041dfb4de84`（MIT）。
- 用户环境：kimi-code 用户级 skill 目录完成同类替换（两个新 skill 就位，旧 skill 退役到 `tmp/replaced-skills/`）。

### 阶段二（方案 A′：用户级唯一分发）

Skill 源仍留在 `.harness/skills/{c4-architecture,mermaid-diagrams}/`（仓库即分发源），但不再进目标工程的 `.harness/skills/`：

- `.harness/skill-scope.txt`（新增）：仓库级 scope 清单，`c4-architecture user all`、`mermaid-diagrams user all`。
- `install.sh` / `install.ps1`：
  - 新增 scope 解析（`skill_scope` / `skill_scope_agents`，PS 侧 `Get-SkillScope` / `Get-SkillScopeAgents`）；
    未列出 → `project`，`agents` 缺省 → `all`。
  - 分发循环按 skill 取目标：`user` 级走清单 `agents`（指定 `--agent` 时取交集）的用户级目录并先 `mkdir` 校验可写，
    `project` 级维持原 `SKILL_DESTS` 行为；沿用 `managed_copy` 的 `keep` 语义（非破坏、幂等），`--no-skill` 仍全跳过。
  - `--check`：按 skill 的 scope 分别查工程内目标 / 用户级目录，输出格式与措辞不变（用户级目标显示绝对路径），
    缺失/不完整仍退出 1；`HOME`（PS 侧 `USERPROFILE`/`HOME`）未设置或不可写时输出可读错误并以退出码 1 结束，不静默成功。
  - `write_manifest`：`skills` 只列工程内安装的 skill，新增 `user_skills`（用户级 skill 名）、
    `skill_scope`（skill → `project`/`user`）、`user_agent_destinations`（用户级落点，绝对路径）；
    `schema_version` 保持 1，既有字段与 `sha256` 不变。
  - 修 kimi/kimi-code 用户级目录：`~/.kimi/skills` → `~/.kimi-code/skills`（两侧同步）。
  - 受管 AGENTS.md 路由段：新增「**User-level skills (agent user directories, outside this project)**」小节，
    两行注册改为用户级表述（举例 `~/.kimi-code/skills/…`、`~/.claude/skills/…`，说明不属于本工程、直接调用）。
- `README.md`：新增 §Skill 分发范围（project / user）+ 清单格式；`--agent` 映射表补 user 列修订
  （kimi/kimi-code → `~/.kimi-code/skills/`，`agents` 行 project/user 两列纠正为 `.agents/skills/`、`~/.agents/skills/`）；
  必需 Skill 自检节区分两级；安装内容树把两个 skill 移出 `.harness/skills/`，改为用户级落点示意图；
  退出码表第 1 行补充「用户级落点不可用」。
- `tests/install-smoke.sh` / `tests/install-smoke.ps1`：
  - 全程隔离用户主目录（bash `HOME`/`USERPROFILE`/`KIMI_CODE_HOME`；PS 侧因 `$HOME` 在进程启动时绑定，
    改为用隔离环境重新拉起自身子进程（子进程 cwd 也指向隔离目录，避免 PowerShell 在 profile 被改写时把
    `Microsoft\Windows\PowerShell\ModuleAnalysisCache` 之类的缓存写进仓库工作树）），确保绝不写入真实 `C:\Users\Administrator\…`；
  - 断言两个 skill **不在** `<target>/.harness/skills/`、**不在**任何工程内 `--agent` 目录，
    而在 fake home 的 6 个用户级目录；`--check` 对用户级副本报 `ok` 且退出 0；
    删/移用户级副本报 `incomplete` / `missing` 且退出 1，重跑安装器即自愈；
    manifest 的 `user_skills` / `skill_scope` / `user_agent_destinations` 形状；
  - PS 侧补齐 `-Scope user` 覆盖（`~/.kimi-code/skills/`，且不写退役的 `~/.kimi/`）；
  - 原先「c4/mermaid 在 `.harness/skills/`」「AGENTS.md 含 `skills/c4-architecture/SKILL.md`」的断言按新语义改写为否定式 + 用户级断言。

## 验证

### 阶段一（原方案）

- `./tests/install-smoke.sh`：PASS。
- `powershell -File tests/install-smoke.ps1`（PowerShell 5.1）：PASS；required skills 列出 5 项且全部 `ok`。
- 真实 `init` / `adopt` 抽验：两 skill 落位、`--check` 输出 `ok .harness/skills/{c4-architecture,mermaid-diagrams}` 且退出 0、manifest 收录两者、`--agent claude,opencode` 分发到 `.claude/skills/` 与 `.opencode/skills/`。
- `./evals/run-eval.sh verdicts`：20 files, 0 hard violations（存量 v1 告警为历史 verdict，与本次变更无关）。

### 阶段二（方案 A′）

- `./tests/install-smoke.sh`：PASS。新增断言覆盖：两 skill **不在** `<target>/.harness/skills/`、**不在**任何工程内 `--agent` 目录，
  而在隔离 home 的 6 个用户级目录；`--check` 对其报 `ok` 且退出 0，删/移副本报 `incomplete` / `missing` 且退出 1、重跑安装器自愈；
  `--agent claude` 收窄到 `~/.claude/skills/`；manifest 的 `user_skills` / `skill_scope` / `user_agent_destinations` 形状；
  `--scope user --agent claude,kimi-code` 落到 `~/.kimi-code/skills/` 且不再创建 `~/.kimi/`。
  测试全程把 `HOME`/`USERPROFILE`/`KIMI_CODE_HOME` 指向临时目录，并以「运行前后真实 home 关键路径
  （各 agent 的 skill 目录、`settings.json`、`config.toml` 等 58 条记录）的 path+size+mtime 快照 diff」证明未写真实用户目录（diff 为空）。
- `powershell -NoProfile -ExecutionPolicy Bypass -File tests/install-smoke.ps1`：PASS（PowerShell 5.1）。
  PowerShell 侧因 `$HOME` 在进程启动时绑定，测试用隔离的 `USERPROFILE`/`HOME`/`KIMI_CODE_HOME` **重新拉起自身子进程**再跑主体；
  并补齐原先缺失的 `-Scope user -Agent claude,kimi-code` 覆盖。
- 手工 E2E（`HOME=<tmp>`）：`./install.sh --target <tmp>/proj --mode init --no-git --skip-env` 退出 0 →
  `.harness/skills/` 仅 `pm-workers-engineering` / `ponytail` / `rsi-loop`，工程内无 `.claude`/`.kimi`/`.codex`；
  fake home 的 `.claude/skills`、`.pi/agent/skills`、`.kimi-code/skills`、`.config/opencode/skills`、`.codex/skills`、`.agents/skills`
  各含两个 skill；`--check`（同一 HOME）17 行全 `ok` 且退出 0；manifest：
  `user_skills=["c4-architecture","mermaid-diagrams"]`、`skill_scope` 5 项正确、`user_agent_destinations` 6 条绝对路径，
  `schema_version` 仍为 1 且 `sha256` 字段不变。
- 只读性：不带 HOME 覆盖、指向已存在临时目标跑 `--check` → 退出 1，输出如实反映本机真实 home
  （仅 `.kimi-code/skills/` 已有这两个 skill，其余 5 处 `missing`）；运行前后真实 home 七个目录的快照完全一致 → `--check` 零写入。
- 错误路径：`HOME` 未设置 → install 与 `--check` 均输出 `error: HOME is not set; …` 并退出 1（未写任何文件）；
  `HOME` 指向普通文件 → `error: cannot write user-level skill directory: …` 退出 1（不静默成功）；
  `--no-skill` → 不碰 home、不碰 `.harness/skills/`，manifest 的 `user_agent_destinations` 为空数组。

## 遗留

- **触发冲突（已解决，2026-09-23 方案 A）**：`mermaid-diagrams` 删除 `references/c4-diagrams.md`（410 行，与 `c4-architecture/references/c4-syntax.md` 重复），description 与图类型表移除 C4 触发并留指针；C4 由 `c4-architecture` 单一持有。用户级副本与仓库源的同步对齐由方案 A′ 定案（见下）。
- **权威层已定（方案 A′，原「未定（乙）」）**：两个 skill 的**用户级副本是唯一权威**——installer 不再把它们装进工程内；
  仓库 `.harness/skills/{c4-architecture,mermaid-diagrams}/` 仅作分发源与 `--check` 校验源，
  实际生效副本在 `~/.kimi-code/skills/`、`~/.claude/skills/` 等 agent 用户目录（清单 `.harness/skill-scope.txt` 指定 `all`）。
- **输出位置**：c4 上游写死 `docs/architecture/c4-*.md`，harness 布局的架构规则在 `docs/engineering/architecture.md`（受管 AGENTS.md 路由段已提示写到工程既有架构文档位置）。
- **校验缺失**：上游只建议人工在 Mermaid Live 校验；被退役 skill 的 `scripts/mermaid-check.js` 与「自测结构检查通过仍解析失败」的实测结论未继承。
- **挂载粒度（部分解决）**：installer 现有 per-skill × per-agent 路由（`.harness/skill-scope.txt` 的 `agents` 列），但仅对 user scope 生效；
  project 级 skill 仍对所有目标目录全量下发、全量必检。子 agent 挂载 skill 的方案待讨论。
- **行为变更提示（需持续留意）**：安装器现在**默认**写工程外路径（各 agent 用户目录），
  「安装器只动目标工程 + `--scope user` 显式请求才写 home」这一旧假设不再成立；
  涉及 installer 的后续变更（尤其 hooks/权限类）需重新审视该副作用，测试必须隔离 HOME。
  **跨平台陷阱（本次实测）**：python 的 `Path.home()` 在 Windows 上忽略 `HOME`，只看 `USERPROFILE`/`HOMEDRIVE`，
  因此 bash 侧仅设 `HOME` 的 `--scope user` 运行仍会让 `install-agent-hooks.py` 写进真实 profile
  （本次在一次手工 `--scope user --agent all` 抽验中命中：真实 `~/.codex/hooks.json` 被写入指向临时工程的 hook 命令）。
  两侧冒烟测试现已同时设置 `USERPROFILE` 与 `KIMI_CODE_HOME`；后续任何在 Windows 上跑 `--scope user` 的脚本都必须照做，
  或显式声明「允许写真实 profile」。
- **eval 门禁**：本变更触及 `.harness/skills/**` 与 install 脚本，提交时置 `evals/.eval-pending`；变更为纯增量且与 pass@1 正交，完整回归随下一次协议战役。
- **protected files**：`install.sh` / `install.ps1` 在 `.harness/.rsi/policy.yaml` 保护清单内，本次修改经用户显式指示。
