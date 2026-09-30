# Harness 设计目标基线（Design Goals Baseline）

> 状态：已与用户确认（2026-09-11，含第二轮机制/决策二分修订）。本文档是 harness 现有实现的评审准绳：所有 critic review 以此为目标状态，逐条对照现状找差距。
> 本轮约定（Q1=C）：只做评审与改进建议，不改任何实现代码。

## 1. 框架定位

ris-coding-harness 及其接入的工程，是一套**触发并运行「代码构建 → 编译 → 测试验证」完整流程的辅助框架**。它不是业务源码的一部分，而是围绕源码运转的基础设施。

## 2. 设计目标（逐条可验证）

### G1 机制/决策二分与 .harness/ 收敛（2026-09-11 第二轮修订；**2026-09-30 v2 修订**）

核心原则：**「机制」与「决策」分离**。

- **机制层**（harness 运行时实现）：全部收敛到单一 `.harness/` 目录——skills、hook 脚本、`.rsi` 门禁策略、manifest、reports、env 阶段产物。
- **决策层**（构建工程的决策文件）：**v2 起同样落位 `.harness/`**（原第二轮修订要求留外，2026-09-30 经用户明确裁决改为全收敛）——`.harness/docs/engineering/` 规则、`.harness/decisions/`、`.harness/issues/`、`.harness/progress/`、`.harness/conversations/`、`.harness/evals/`。这些内容仍归工程自有（条目由人/agent 撰写），只是物理位置收敛，便于「安装器生成的一切都在 `.harness/` 内」这条可机械检验的边界。
- **边界规则（v2）**：安装器生成的目录**全部**位于 `.harness/`。仓库根只保留四类：① agent 原生发现入口（根 `AGENTS.md`、`CLAUDE.md`）；② 第三方固定发现路径（工程内 agent skill 目录 `.claude/skills` 等）；③ 工程工作区骨架（`src/`、`tests/`、`docs/`、`output/`、`tmp/`、`scripts/`——`scripts/` 供 G6 的 `setup-env` 约定使用）；④ git 产物（`.git/`、`.gitignore`）。
- **版本与迁移**：`.harness/layout-version.txt` 记录目标工程布局版本。无标记但有 `.harness/` → 判定 v1，安装器把根级记录目录整体迁入 `.harness/`（目标冲突时保留根级副本并报告，绝不覆盖/删除数据）；无 `.harness/` → 全新工程，直接按 v2 安装且不触碰工程自带的同名根目录。
- **分发边界**：install 只分发机制层；harness 自身构建过程的元文件（`docs/rsi-design.md`、`decisions/`、`progress/`、`evals/` 任务集与评分脚本、`tests/`、评审报告等）**永不进入目标工程**。
- **仓库同构托管**（Q4）：harness 仓库自身也按同构布局收敛——机制资产（`skills/`、`templates/`）物理迁入仓库的 `.harness/`，install 从 `.harness/` 取源；`install.sh`/`install.ps1`（curl 入口）、README、LICENSE 留仓库根；决策层（docs/、decisions/、progress/、evals/、tests/、run-loop.sh、scripts/ 自托管工具）留仓库根。**注**：harness 仓库自身尚未执行 v2 迁移（其记录目录仍在根级），迁移与否由仓库维护者决定。
- **manifest**：install 维护 `.harness/manifest.json` 受管清单（path/source/content_hash/layer/managed/scope），作为管理边界单一事实源；`--check` 扩展为 manifest 完整性检查。
- **agent 入口**：根 `AGENTS.md` 与 `CLAUDE.md` 由 install 写入目录规则与 skill 注册信息（见 §3 双重属性清单），保留在工程根（agent 原生发现入口）。**合并语义**：已存在则注入/更新标记包裹的受管段（不改写用户原有内容），不存在才创建。
- **rsi-loop 降级语义**（Q2=B）：rsi-loop skill 随装，但在目标工程降级为「仅 observe-only 自检可用」——preflight 明确 eval 相关项（基线、run-eval、verdict 聚合）在目标工程不适用；完整闭环仅 harness 自托管场景运行。

### G2 跨平台：Windows / Linux / macOS

- 安装器与自动化入口必须是 bash（Linux/macOS）+ PowerShell（Windows）双实现，参数与行为一致（含退出码契约）。
- 验证方式（已确认）：本机 Windows 实测 + 双实现逻辑对齐即可，不要求三平台 CI 矩阵。

### G3 跨多个 Agent

- 同一套 skill 与流程在 claude / pi / kimi(kimi-code) / opencode / codex / agents 目录下均可分发与激活（`--agent` 分发机制 + manifest 注册）。
- 自动化 shell 入口不得绑定单一 agent CLI；headless 模式须覆盖全部候选 agent。

### G4 自修复与自愈

- harness 自身资产自检自愈：必需 skill / 配置缺失或不完整时可检测（`--check`）并经安装器补齐；检测范围随 manifest 扩展到全部受管资产。
- 构建与测试失败时的自愈：**有限次自动修复，上限 3 次**——失败后自动归因、尝试修复、重跑验证；3 次未通过则停机交还人工，不得无限循环。

### G5 自动化管线：构建 → 测试构建 → 测试 → code review → 自动提交

- 支持自动进行：代码构建、测试代码构建、自动测试、code review，然后自动提交。
- 自动提交的安全边界（Q3=A）：
  - Reviewer 验收通过后才允许 commit；
  - commit 不 push；
  - 受 `.harness/` 门禁策略（原 `.rsi/policy.yaml`）约束：`observe-only` 下不提交；
  - L1P 平台知识卡维持「永不自动提交」。

### G6 环境依赖自动构建（install 阶段）

- install 过程中自动读取工程目录下的环境依赖脚本，并按依赖内容自动拉取到本地、完成编译环境构建。
- 约定（Q2=A）：
  - 优先执行工程自带的约定路径脚本：`scripts/setup-env.sh`（Linux/macOS）/ `scripts/setup-env.ps1`（Windows）；harness 只负责发现与执行，不臆造脚本内容；
  - 约定脚本缺失时，自动探测生态标准清单（`package.json` / `requirements.txt` / `pyproject.toml` / `pom.xml` / `build.gradle` / `CMakeLists.txt` / `go.mod` / `Cargo.toml` 等）并调用对应包管理器；
  - 与 PM-Workers 硬规则衔接：探测结果必须来自仓库证据，仍无法确定构建/测试命令时停机询问，不得臆造。
- 触发时机：install 完成后**立即运行一次**环境验证 + 构建验证（命令已知时），结果写入 `.harness/` 报告。

## 3. 双重属性清单（机制 + 决策）与归属决定

以下项目兼具机制与决策双重属性，逐项决定「install 动态生成」还是「静态保留随装」：

| # | 项目 | 双重属性体现 | 决定 | 说明 |
|---|---|---|---|---|
| 1 | 根 `AGENTS.md` | 机制：install 写入、路由上下文加载；决策：承载目录约定与工作流入口 | **install 动态生成（存在则注入受管段，不存在才创建）** | 受管段用标记包裹（`ris-coding-harness:begin/end`），内容 = 目录规则、`.harness/` 实际落位路径、已注册 skill、`--agent` 清单。合并规则：已存在且无标记 → 末尾追加受管段，用户原有内容不动；已有标记 → 仅替换标记之间内容（规则/注册表更新）；不存在 → 创建（骨架 + 受管段）。用户原有内容永不改写 |
| 2 | `CLAUDE.md`（新增） | Claude Code 原生入口 | **install 动态生成（同 AGENTS.md 合并语义）** | 薄指针指向 `AGENTS.md`，不复制规则正文；存在则注入/更新受管段，不存在才创建，保持单一事实源 |
| 3 | `docs/engineering/` 8 个规则模板 + index.md | 机制：install 创建骨架、agent 渐进加载；决策：正文 = 目标工程自己的构建规则 | **静态模板保留，随装复制**；骨架动态创建；**v2 落位 `.harness/docs/engineering/`** | 模板是「提问清单」型内容资产，脚本生成无收益；正文填写归工程（keep 语义不覆盖） |
| 4 | `docs/engineering/platform/` L1P 卡 | 同上 + 永不自动提交语义 | **静态保留**；**v2 落位 `.harness/docs/engineering/platform/`** | L1P 纪律不变 |
| 5 | `decisions/` `issues/` `progress/` 目录 + index.md | 机制：install 建目录写路由 index；决策：条目内容归工程 | **目录与 index 动态创建**；**v2 落位 `.harness/` 下** | 条目内容归工程；v1 工程的根级目录由安装器自动迁移 |
| 6 | `evals/results/` + `evals/index.md` | 机制：verdict 落点；内容：工程遥测 | **动态创建**；**v2 落位 `.harness/evals/`** | init 只建 results + index；evals 任务集/评分脚本不分发 |
| 7 | `.harness/` 门禁策略（policy.yaml + README） | 纯机制（Q1） | **静态模板随装**，落 `.harness/` | L3 内容人工修订，不由脚本生成 |
| 8 | skills 内容（pm-workers-engineering / rsi-loop） | 内容 = 协议资产；注册（装到哪些 agent 目录）= 机制 | **内容静态复制 + 注册信息动态**（manifest 记录 skill→agent 路径映射） | rsi-loop 按 G1 降级语义随装 |
| 9 | `.gitignore` | 纯机制 | **动态生成** | 维持现状 |
| 10 | `.harness/manifest.json` | 纯机制（新增） | **动态生成** | install 是唯一写入者；列入受保护文件 |
| 11 | init 骨架（src/tests/docs/…） | 纯机制 | **动态创建** | 维持现状 |

## 4. install 分发边界总表

| 类别 | 内容 | 处置 |
|---|---|---|
| 静态随装（复制进 `.harness/`） | skills（2 个）、`.harness/` 门禁策略模板、**`.harness/docs/engineering/` 规则模板 + platform 卡模板**（v2）、hook 脚本副本（compact-archive/session-recall/install-agent-hooks/compact-recall.*，落 `.harness/scripts/`） | 复制，keep 语义 |
| 动态创建（v2 全部落 `.harness/`） | `AGENTS.md`（注册段）、`CLAUDE.md`、**`.harness/{decisions,issues,progress,conversations,evals}/` + 各 index.md**、`layout-version.txt`、根级工作区骨架（`src/ tests/ docs/ output/ tmp/ scripts/`）、`.gitignore`、`manifest.json`+`layout_version`、env 阶段报告 | install 脚本生成 |
| 留在目标工程根（非 `.harness/`，v2 边界规则） | ① agent 原生发现入口：根 `AGENTS.md`/`CLAUDE.md`；② 第三方固定发现路径：`.claude/skills` 等 agent skill 目录；③ 工程工作区骨架（见上，`scripts/` 供 G6 setup-env 约定）；④ git 产物 `.git/`、`.gitignore` | 工程自有/第三方约定 |
| **永不分发**（harness 构建过程文件） | `docs/rsi-design.md`、`docs/harness-design-goals.md`、`docs/critic-review-*.md`、`decisions/`（仓库自身）、`progress/`、`evals/` 任务集 + `run-eval.sh` + `baseline.json` + `install-hooks.sh` + `trigger.sh`、`tests/`、`scripts/retro-aggregate.py`、`run-loop.sh`、`team-launcher`、`init-prompt*.md` | 仅存于 harness 仓库 |

## 5. 评审维度与对照关系

| 维度 | 对照目标 | 评审重点 |
|---|---|---|
| D1 架构分离 | G1 | 机制/决策二分落位、`.harness/` 收敛（含仓库同构）、manifest、引用面迁移 |
| D2 跨平台跨 agent | G2、G3 | bash/PowerShell 行为一致性（含退出码契约）、仅 bash 存在的自动化入口、agent 矩阵覆盖 |
| D3 自愈 | G4 | 自检自愈覆盖面；构建/测试失败自动修复（≤3 次）落点 |
| D4 自动管线 | G5 | 构建→测试→review→commit 链路；自动 commit 与门禁/保护规则衔接 |
| D5 环境依赖 | G6 | 依赖脚本发现/执行、生态探测、install 后环境与构建验证 |

## 6. 明确的非目标（本轮）

- 不改任何实现代码（Q1=C）；本文件 §2-§4 的基线修订属设计文档更新，不属实现。
- 不引入三平台 CI 矩阵（G2 本机验证即可）。
- 不做 skill 版本漂移比对。

## 7. 决策记录

| 日期 | 决定 |
|---|---|
| 2026-09-11 | Q1=C 仅评审不改码；Q2=A 依赖脚本约定优先+生态探测兜底；Q3=A 门禁管控自动 commit；Q4（原）收敛 .harness/ |
| 2026-09-11 | 自愈扩展到构建/测试失败 ≤3 次自动修复；install 后立即跑一次构建验证；本机 Windows 验证；设计目的写入本文档 |
| 2026-09-11 | G1 修订为机制/决策二分：机制进 `.harness/`、决策留外、构建过程文件永不分发；`.rsi/policy.yaml` 定性为机制（Q1）；rsi-loop 随装但目标工程降级 observe-only 自检（Q2=B）；根 AGENTS.md 保留工程根（Q3）；harness 仓库同构托管（Q4）；双重属性 11 项归属见 §3 |
| 2026-09-11 | AGENTS.md / CLAUDE.md 合并语义：已存在则注入/更新标记包裹的受管段（用户原有内容不改写），不存在才创建——取代旧的「已存在整体 keep」行为（旧行为会导致 adopt 已有 AGENTS.md 的工程时路由规则永远无法写入） |
| 2026-09-30 | **G1 v2 修订（用户裁决）**：安装器生成的一切目录全部收敛 `.harness/`——决策层记录目录（`docs/engineering/`、`decisions/`、`issues/`、`progress/`、`conversations/`、`evals/`）一并迁入，取代第二轮修订的「决策留外」。引入 `layout-version.txt` 版本标记与 v1 → v2 自动迁移（整体搬移、冲突保留根级副本、不删数据）。根级仅保留 agent 原生入口、第三方 agent skill 目录、工程工作区骨架与 git 产物 |
