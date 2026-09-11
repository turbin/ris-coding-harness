# Harness Critic Iteration Review（2026-09-11）

> 评审方式：5 个并行只读评审 agent（D1-D5），以 `docs/harness-design-goals.md`（已确认的 6 条设计目标 G1-G6）为唯一准绳，对现有实现做差距分析。每个论断附 file:line 证据，退出码与 CLI 行为均经本机实测。完整原文见附录。
> 本轮约定：仅评审与建议，不改代码（Q1=C）。

## 一、总体结论

现有实现在「安装器双平台对齐、skill 分发矩阵、RSI 变异纪律、资产自检自愈（--check）」四个方面基础扎实；但对照 G1-G6，**三条主线缺口均为零落地或接近零落地**：环境依赖自动构建（G6）、构建/测试失败自动修复（G4 后半）、自动管线终点的任务级自动 commit（G5 后半）。此外发现两类跨维度的结构性问题：**自动化资产不随安装器分发**（目标工程内 rsi-loop 必然 preflight 失败）与**保护清单/策略 glob 多副本漂移**（三份清单不一致，静默降级不可见）。

各目标达成度速览：

| 目标 | 达成度 | 主缺口 |
|---|---|---|
| G1 分割点收敛 .harness/ | ★★☆ 部分分离，无收敛 | 4 个顶层散布点、~210 处路径硬编码、无 manifest |
| G2 跨平台 | ★★★☆ 安装器对齐良好 | 6 个自动化入口仅 bash；macOS bash 3.2 必坏；退出码契约两侧不一致 |
| G3 跨 agent | ★★★☆ 分发矩阵完备 | headless 仅适配 pi/kimi，claude/codex/opencode 会挂起；自动化层不随装 |
| G4 自愈 | ★★☆ 资产自检已达标 | 失败修复循环缺失；与 rsi-design §4.7「只停不修」正面冲突未裁决 |
| G5 自动管线 | ★★☆ 前段有骨架 | BUILD→TEST 无统一协议；verdict 无证据字段；任务级 commit 与门禁均零落地 |
| G6 环境依赖 | ☆ 全零落地 | 安装器完全不感知依赖；但 agent 期 onboarding 规范可直接复用 |

## 二、跨维度综合缺口矩阵

### P0（实现前必须解决，或已实测证实的功能性缺陷）

| # | 缺口 | 来源 | 说明 |
|---|---|---|---|
| P0-1 | headless 映射缺失：`claude -p` / `codex exec` / `opencode run` 未适配，cron/CI 下选到即挂起 | D2-1 | 已对照官方文档核实；kimi `-p`/`--print` 疑似冗余待核 |
| P0-2 | 退出码契约不一致：invalid `--mode`/`--scope`/未知选项 sh=2、ps1=1（实测）；`--target` 缺值 sh=1 | D2-2 | 与 `--help` 自述「2 on usage errors」不符，CI 判定两平台不一致 |
| P0-3 | 自动化资产不随安装器分发：evals/run-eval.sh、trigger.sh、install-hooks.sh、rsi-protect.sh、retro-aggregate.py 均不分发，目标工程 preflight 第 2/4/10 项必失败 | D1-B、D2-6 | install-hooks.sh 写死的 `$ROOT/evals/trigger.sh` 在目标工程不存在（D1 差距 7） |
| P0-4 | G5：Coder 契约无显式 BUILD→TEST 阶段（"Verify" 一个词），构建环节完全缺失，编译失败与测试失败不可区分 | D4-1 | 自动管线的起点缺位 |
| P0-5 | G5：verdict schema 无 build/test 证据字段（命令/退出码/通过数/日志），「Reviewer 通过」可能只基于主观分 | D4-2 | 自动提交的前置证据链断裂，reward hacking 面扩大 |
| P0-6 | G5：任务级自动 commit 零落地；policy.yaml 无 `task_commit` 段，observe-only 对任务提交无约束 | D4-3/4 | 直接加「跑完即 commit」会击穿 observe-only 语义 |
| P0-7 | G6：install 期 env 阶段（setup-env 发现/执行 + 生态探测 + install 后构建验证 + 报告）整体缺失 | D5 全部 | 改进方案已齐备（见 D5 R1-R7 + 映射表草案 + 护栏设计） |

### P1（核心能力补齐，次批次落地）

| # | 缺口 | 来源 |
|---|---|---|
| P1-1 | G4：构建/测试失败自动修复（≤3 次）协议缺失，无次数上限、无归因要求、无状态承载 | D3-1/3 |
| P1-2 | G4 前置裁决：rsi-design.md:260 与 stop-conditions.md #1「回归只停不修」与 G4 正面冲突，须先修订文本（L3 资产，人工决策） | D3-2 |
| P1-3 | 受保护清单三副本漂移：policy.yaml 只含 3 条，gate-policy.md 与 rsi-protect.sh fallback 多含 rsi-design.md、install.sh、install.ps1；且 python3 缺失时 rsi-protect 静默降级 | D1、D3-6、D2-5 |
| P1-4 | 策略层 glob 硬编码于 ≥6 文件（policy.yaml / trigger.sh / rsi-protect.sh / gate-policy.md / preflight.md），布局一改需同步 | D1 差距 4 |
| P1-5 | G1：manifest（.harness/manifest.json）缺失——--check 只能查 skill 存在性，无法查完整性/越界/残留 | D1-6、D3-5 |
| P1-6 | macOS 原生 bash 3.2 无 mapfile，run-eval.sh 开箱即坏 | D2-4 |
| P1-7 | python3 假设过强（Windows 惯用 python/py），需三级回退 | D2-5 |
| P1-8 | 无 .gitattributes，autocrlf 环境下 clone 即让全部 .sh 变 CRLF 不可执行 | D2-7 |
| P1-9 | install-hooks.sh 在自定义 core.hooksPath 下静默失效（`|| true` 吞错） | D2-8 |
| P1-10 | run-loop.sh 无 PowerShell 等价物（Windows 无 Git Bash 则循环链路不可用） | D2-3/7 |

### P2（一致性/健壮性收尾）

sh 的 `--agent` 大小写不归一化、空段处理分叉；.gitignore 内容分叉（Thumbs.db）；ps1 `Get-RelPath` 前缀匹配可截短兄弟目录；`--check` 覆盖面扩展到全部受管资产；SPAWN 基础设施失败允许 1 次重派；冒烟测试补对称断言与 `--scope user` 用例；废弃入口清理；commit 信息规范（task-id+milestone、禁 `git add -A`、禁 `--no-verify`、协议禁 push 双重声明）。

## 三、建议落地顺序（五批，考虑依赖关系）

1. **批次一（小而独立，P0）**：P0-1 headless 映射 + P0-2 退出码契约统一（顺带 P2 的 --agent 归一化、.gitignore 抹平）+ P1-8 .gitattributes。半天量级，全是实测过的缺陷。
2. **批次二（G6 环境，P0）**：D5 R1-R5——install 期 env 阶段 + `.harness/reports/env-report.md` 报告 + `--skip-env`/`--dry-run-env`/`--strict-env` 护栏 + 生态探测映射表（bash/ps1 双实现）+ 降级语义（UNKNOWN 记录转交，非交互不停机）。前置：先新建 `.harness/` 目录（新目录无迁移成本，G1 收敛的第一块砖）。
3. **批次三（G5 管线，P0）**：D4 建议 1-3——SKILL.md BUILD→TEST 显式阶段 → verdict schema v2 证据字段 → policy.yaml `task_commit` 段 + rsi-protect.sh 扩展（校验 verdict accepted、硬拒 platform/**、统一 fallback 清单）。注意 policy.yaml 与 rsi-design.md 属 L3，改动需人工决策（见第四节）。
4. **批次四（G4 自愈，P1）**：先做 P1-2 文本修订（L3，人工），再落 Coder 有界修复循环（挂点 A）+ repair_attempts 状态字段 + 变异后回归修复窗口（挂点 B，含 revert 兜底）。与批次二的 env-report 共享命令来源（tooling.md > env-report > 停机询问）。
5. **批次五（G1 收敛，P1 大迁移）**：D1 建议 1-5——资产所有权三分类冻结 → manifest 规格 + 双安装器实现 → 策略 glob 单源化/过渡期多 glob → skill 查找双路径兼容 → adopt 迁移逻辑（hash 一致才搬移，定制过标 legacy）。一个版本周期内新旧共存。

P2 项穿插在相邻批次收尾。

## 四、需要用户裁决的事项（实现前）

1. **L3 文本修订授权**：`docs/rsi-design.md` §4.7（「回归只停不修」→「修复窗口 ≤3 → revert 兜底 → 停」）与 `stop-conditions.md` #1——两者是 G4 的前置，且属 L3 资产，按其自身规则必须人工修订授权。
2. **policy.yaml 新增 `task_commit` 段**：任务级 commit 门禁（observe-only 禁止 / 范围限定 / 禁 push）写入 L3 策略文件，同样需人工确认。
3. **docs/engineering 所有权**：D1 建议不把 `docs/engineering/` 正文搬进 `.harness/`（L1 工程自有资产语义），仅收敛 harness 资产——与 G1「所有资产收敛」的字面表述有出入，需确认按此解释执行。
4. **根 AGENTS.md 处置**：保留在工程根（agent 原生入口），manifest 中登记，不搬进 `.harness/`。
5. **自动化资产分发边界**：最小自动化集（evals/、rsi-protect.sh 等）随安装器分发，还是声明「RSI 闭环仅自托管场景」？（D1 建议 6 / D2 建议 6）

---

## 附录 A：D1 架构分离（完整原文）

**A. 安装器落位资产（install.sh 与 install.ps1 行为一致）**

| 资产 | 落位路径 | 证据 |
|---|---|---|
| 路由入口 | `<target>/AGENTS.md` | install.sh:240；install.ps1:299 |
| 工程规则 | `<target>/docs/engineering/*.md` + `platform/**` | install.sh:241-250；install.ps1:300-309 |
| Skill | `<target>/.agents/skills/`（无条件默认），`--agent` 追加 `.claude/.pi/.kimi/.opencode/.codex/.agents` 对应目录 | install.sh:160,262-269,135-145；install.ps1:173,311-318,136-144 |
| RSI 策略 | `<target>/.rsi/`（policy.yaml + README） | install.sh:271-277；install.ps1:320-326 |
| init 骨架 | `src/tests/docs/decisions/issues/conversations/output/progress/scripts/tmp` 各带 index.md + `evals/results/` + `evals/index.md` | install.sh:286-295；install.ps1:337-346 |
| 路由索引 | decisions/issues/progress 目录存在时补 index.md | install.sh:297-302；install.ps1:348-353 |
| 其他 | .gitignore（缺失时写入）、git init | install.sh:304-337,339-354；install.ps1:355-408 |

**B. 关键结构性事实**

- **不随安装器分发的 RSI 运行时资产**：`evals/tasks|run-eval.sh|baseline.json`、`evals/install-hooks.sh`、`scripts/rsi-protect.sh`、`run-loop.sh`、`docs/rsi-design.md` 均不在安装范围内。evals/README.md:71-76 却要求「每个目标工程手动执行一次 install-hooks」，而 install-hooks.sh 写出的 hook 调用 `$ROOT/evals/trigger.sh`（install-hooks.sh:57-58）——该路径只在 harness 仓库自托管时存在。
- **策略层 glob 与目录布局强耦合**：policy.yaml 四层（L1=`docs/engineering/**`、L1P=`docs/engineering/platform/**`、L2=`.agents/skills/**`、L3=`.rsi/**`，templates/project/.rsi/policy.yaml:22-25）；同组路径又硬编码在 evals/trigger.sh:50-51、scripts/rsi-protect.sh:5,11,19,28、gate-policy.md:24-34、preflight.md:12,14。
- **受管清单存在三份会漂移的副本**：policy.yaml:6-9、rsi-protect.sh:19 与 :28、gate-policy.md:30-36——无单一事实源。
- **幂等非破坏承诺**：keep 语义（install.sh:110-132；install.ps1:204-222；README.md:107,281-282）；**没有任何删除/搬移旧资产的代码路径**。
- **user scope 写到 `$HOME`**（install.sh:137-142），天然在工程 manifest 边界之外。
- **run-loop.sh 已承认双路径现实**：`skills/rsi-loop/SKILL.md, or .agents/skills/rsi-loop/ in the target project`（run-loop.sh:82）。
- **manifest 尚不存在**，且 "manifest" 一词在仓内均为「包清单」语义。

**C. 路径硬编码引用面统计**：`.agents/skills` ~44 处/17 文件；`.rsi/` ~34 处/24 文件；`docs/engineering` ~99 处/28 文件；`AGENTS.md` ~33 处/15 文件。

**差距清单（10 条）**：资产分散 vs 单一 .harness/；docs/engineering 的语义张力（工程自有 L1 资产不宜搬入）；根 AGENTS.md 双重身份；策略/触发/保护三处 glob 硬编码；keep 语义与收敛互斥（旧路径残留、双 skill 并存）；manifest 缺失；RSI 运行时资产不随装；user scope 越界（需显式豁免）；测试断言绑死旧路径；废弃入口仍传播旧路径。

**改进建议**：① 先冻结资产所有权三分类（harness-受管 / 工程自有 / agent-原生）→ 基线文档，P0；② manifest 规格 + 双安装器实现（`.harness/manifest.json`，managed_copy/write_if_missing 为插入点），P0；③ 策略 glob 单源化/过渡期多 glob，P1；④ skill 查找顺序兼容层（先 .harness/ 后 .agents/），P1；⑤ 安装器迁移逻辑（hash 一致才搬移、定制过标 legacy、--check 报残留），P1；⑥ RSI 运行时分发边界明确，P2；⑦ 根 AGENTS.md 保留在根 + manifest 登记，P2；⑧ 清理废弃入口，P2。

**manifest 设计要点**：字段 `path/source/content_hash/harness_version/installed_at/layer/managed/scope/legacy_path`；安装器每次 keep/write 增量更新；manifest 列入 protected_files（L3）；消费者为 --check 完整性自检、rsi-protect.sh（替代三份漂移 fallback）、G4 自愈。

## 附录 B：D2 跨平台跨 agent（完整原文）

**已对齐（实测验证）**：安装器双实现参数面一致；`--check` 三态语义、零写入、互斥退出码逐行对齐且实测一致；agent 目录映射三方一致（README = skill_dest = $AgentMap）；冒烟测试 --check 用例两侧一一对应；工作区 .sh 均为 LF。

**关键事实（本机实测）**：本机无 pwsh（仅 PowerShell 5.1）；`python3` 来自无关项目资源，Windows 常规环境不可用。退出码实测：invalid `--mode`/`--scope`/未知选项 sh=2、ps1=1；未知 agent、`--check --no-skill` 两侧均 2；`--target` 缺值 sh=1。

**差距清单（9 条）**：① headless 只适配 pi/kimi，claude/codex/opencode 会挂起在交互 TUI（官方用法已核实：`claude -p`、`codex exec`、`opencode run`）；② 用法错误退出码不一致且与文档承诺不符；③ 自动化入口几乎全为 bash 单实现（6 个入口；Git Bash 语法层面均可跑）；④ run-eval.sh 依赖 bash 4+（mapfile），macOS 原生 bash 3.2 直接失败；⑤ python3 假设过强，rsi-protect.sh 在无 python3 时静默降级、用户定制被忽略；⑥ 自动化资产不随安装器分发，目标工程 preflight 必失败；⑦ 无 .gitattributes 保护行尾；⑧ install-hooks.sh 在自定义 core.hooksPath 下写错 ROOT 且 `|| true` 吞错；⑨ 细碎不一致集合（--agent 大小写/空段、.gitignore 分叉、Get-RelPath 前缀截短、run-loop.sh:96 不加引号、kimi -p/--print 疑冗余、README 参数表未注明 PS 侧限制、冒烟覆盖不对称）。

**改进建议（10 条）**：P0 补全 headless 映射 + 统一用法退出码为 2 并写「退出码契约」小节；P1 .gitattributes、run-eval.sh 去 mapfile 化、python 三级回退（python3→python→py）+ rsi-protect 显式告警、安装器分发最小自动化集或文档声明、run-loop.ps1 薄移植或 README 声明 Windows=Git Bash、install-hooks.sh 用 `git rev-parse --show-toplevel`；P2 行为抹平小项 + 冒烟对称断言。

## 附录 C：D3 自修复自愈（完整原文）

**现状**：安装器自检自愈已达标（--check/-Check 三态 + keep 补齐 + AGENTS.md 自检指引，冒烟覆盖全链路）；rsi-loop preflight 11 项任一失败即停、无修复尝试；停机条件 7 条硬编码（#1 eval 回归立即硬停、#2 连续 3 轮 rejected/缺 verdict 硬停、停机后零 mutation）；PM-Workers Coder 失败行为无次数边界（§13 只管「语义走不下去」，verdict `rounds` 是审阅往返非修复次数）；SPAWN 失败与任务失败不区分，一次抖动消耗一轮预算；state.yaml/round yaml 均无 repair 字段，--resume 后计数会丢；change_budget 只约束 RSI 规则回写、不覆盖任务内修复；事件触发链（trigger.sh check 失败）现状直接停机。

**差距（6 条）**：① 构建测试失败自动修复完全缺失；② **G4 与 rsi-design.md:260/stop-conditions #1「只停不修」正面冲突未裁决**；③ 修复尝试无状态承载；④ 基础设施失败与任务失败不区分；⑤ --check 只查 SKILL.md，.rsi/policy.yaml 缺失时门禁静默降级不自知；⑥ protected 三处清单不一致（模板 policy 少 rsi-design.md/install.sh/install.ps1）。

**改进建议**：Coder 契约落有界修复循环（P1/高）；先修订 rsi-design §4.7 + stop-conditions #1 再实现（P1/高，L3 走人工）；round/state yaml 补 `repair_attempts`/`repair_exhausted`/`repair_attempts_total`（P1/高）；SPAWN 失败允许 1 次重派不计入停机条件 #2（P2/中）；--check 扩展为受管资产清单检查（P2/高）；统一 protected 清单（P2/高）。不建议把 max_attempts 放进 policy.yaml 做配置——硬编码在协议文本更简单安全（高）。

**落点设计**：挂点 A（主）= Coder Verify 后：失败→归因→修复→重跑，同一症结 ≤3 次（以失败输出变化判症结），3 次未过按 §13 停、落 issues/ 交 PM；挂点 B = MUTATE 后 eval 回归：修复窗口 ≤3 → revert 提案 commit 兜底 → incident 报告 → 硬停（前提：先完成文本修订）；挂点 C（可选）= trigger.sh check 失败走同一语义。衔接关键：轮内修复耗尽 → 该轮 rejected → **天然落入现有停机条件 #2**（3 任务 × 3 次 = 9 次后必停），零新增停机机制；修复只发生在停机判定之前，「停机后零 mutation」始终成立；修复合入仍属试运行，人工终验不可绕过。

## 附录 D：D4 自动管线（完整原文）

**现状**：Coder 循环 `Inspect → RED → GREEN → REFACTOR → Verify → …`（SKILL.md:256）中 Verify 仅一词，构建环节完全缺失（构建命令只在 tooling.md 占位与 onboarding 发现程序中）；Reviewer 门禁协议完整（禁裸 LGTM、verdict 必需、PM 不能 silently 覆盖），但 verdict schema 无 build/test 证据字段（仅主观 1-5 分）；流程止于 PM 汇报，无 commit 环节（README.md:229「单任务全自动」不含提交）；§13 停机无条件计数协议；任务级 commit 为零而 RSI 变异级有完整纪律（一变异一 commit、带提案 ID）；**gate 三级只定义于 RSI 循环**，policy.yaml 无任务级 commit 条目；rsi-protect.sh 只做路径拦截，不读 gate、不校验 Reviewer 验收；push 纪律零覆盖；eval（沙盒 pass@1）与任务级 build/test 两套体系互不联动。

**差距（7 条）**：无统一构建→测试协议；测试执行无结构化载体；自动提交未实现且与 rsi-loop 整合时多任务变更叠加违反「工作区干净」预检；任务级 commit 无门禁挂点；无 push 禁令；无失败重试计数；eval 无法检验管线自身回归。

**改进建议**：**总体推荐分层落地——协议扩展进 pm-workers SKILL.md，强制门禁外置到钩子/薄壳层，不新建独立 pipeline skill**（理由：门禁已是 SKILL.md 一部分，拆新 skill 会让门禁定义漂移；rsi-design.md:231 自认「skill 自我约束弱于外部脚本」）。P0：Coder contract 显式 BUILD→TEST 阶段（从 tooling.md/testing.md 读命令）；verdict schema v2 增 `build: {command,status}`、`tests: {command,passed,failed,log}`；policy.yaml 增 `task_commit:` 段。P1：rsi-protect.sh 双模式扩展（staged 含 platform/** 拒绝；统一 fallback 清单）；G4 重试计数挂钩（`fix_attempts` 进 verdict）。P2：commit 信息规范（task-id+milestone、与 RSI 提案 ID 命名空间分开、禁 --no-verify）；eval rubric 增 verdict 字段完备性机械检查。

**自动 commit 安全设计要点**：gate 三级映射任务级——observe-only 不 commit / l1-auto 验收且证据齐后自动 commit / all-manual 先询问；钩子校验对应 verdict 文件存在且 `decision: accepted`（机器可判的硬拦截），验收语义仍由协议承载；L1P 平台卡钩子直接拒绝（比协议更硬），PM 汇报继续列 awaiting human commit，同时保留「未提交平台卡不算工作区污染」否则 rsi-loop 预检误停；禁止 `git add -A`；不 push 协议+文档双重声明；失败路径 fail-closed（build/test 失败或 verdict 缺失时 commit 必不发生）。

## 附录 E：D5 环境依赖（完整原文）

**现状**：G6 零落地（全仓 `setup-env` 仅命中基线文档；安装器全部动作 = 复制模板/skill/.rsi + init 骨架 + .gitignore + git init，从不执行目标工程内任何代码）；模板对依赖只有占位符；环境发现仅存在于 agent 期（project-onboarding.md:22-27 扫描顺序、:31-33 UNKNOWN 标记、:44-46 不臆造硬规则，触发条件是「任务需要构建/测试」与 install 无关）；安装器无任何交互确认机制，安装后自检失败仅 warn 不改退出码；D3 的 ≤3 次修复同样未实现——两者是可一并设计的空档。

**差距（6 条）**：约定脚本发现+执行缺失；探测→安装→验证映射缺失；验证流程与报告落点缺失；「停机询问」在非交互 install 期无承载机制；执行工程自带脚本的安全性无护栏（任意代码执行入口）；与 D3 无共享「命令来源 + 失败证据」通道。

**改进建议**：R1（P0/高）env 阶段插入 .gitignore 之后、git init 之后、summary 之前；--check 完全跳过；新增 --skip-env/--dry-run-env。R2（P0/高）验证失败默认不阻断不回滚，新增 --strict-env 使失败升级退出码 3。R3（P0/高）「停机询问」降级为记录+转交（UNKNOWN 写报告，确认发生在 agent 期 onboarding）。R4（P1/中）报告落 `.harness/reports/env-report.md` 覆盖写，不写 tooling.md（绕过用户确认）。R5（P1/中）映射表=单一数据表+双语言薄执行器；注意 set -euo pipefail 会杀死探测命令（须显式包裹）、PowerShell 5.1 无 &&。R6（P1/中）与 D3 衔接=共享命令来源，install 只跑一次不修复；preflight 增「读 env-report」。R7（P2/中）约定脚本路径写入模板与 skill 文档闭环。

**生态映射表草案**（只装依赖不构建产物；构建验证仅当命令有仓库证据）：package.json 按锁文件分发 npm ci/pnpm/yarn，无锁文件标 UNKNOWN；requirements.txt 不擅自创建 venv（无则 UNKNOWN）；pyproject.toml 按锁文件分发 poetry/uv/pip -e；go.mod → go mod download；Cargo.toml → cargo fetch；pom.xml mvnw/mvn dependency:resolve；build.gradle gradlew/gradle（无 wrapper 无全局→UNKNOWN）；CMakeLists.txt 有 vcpkg/conan→UNKNOWN，否则 cmake configure 即验证。多清单并存不算歧义，同生态多候选无法消歧=UNKNOWN。

**安全护栏**：只执行目标工程内 scripts/setup-env.sh|.ps1（信任模型=用户 adopt 该工程即授信）；执行前逐行打印将运行命令；--dry-run-env 只打印；每条命令带超时（默认 10 分钟）；失败不重试不回滚；cwd=TARGET；--check 路径零执行；重复 install 幂等；ps1 以 -File 子进程调用并明示执行策略。

**与 D3 衔接一句话**：install 期 env 阶段是「证据生产者」（跑一次、写报告、不修复），任务期 D3 是「证据消费者」（读报告取命令、≤3 次归因-修复-重跑、3 次后交人工）；命令唯一来源优先级：tooling.md（经确认）> env-report（探测缓存）> 停机询问。
