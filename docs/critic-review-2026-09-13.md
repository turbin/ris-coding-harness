# Harness Critic Iteration Review · 第二轮（2026-09-13）

> 对象：第一轮评审后实施的全部改动（commits 20e2fee / 3736bdd / bf3767e）。
> 方法：5 个并行只读评审 agent（R1 安装器核心 / R2 迁移与兼容 / R3 可移植性 / R4 协议一致性 / R5 测试盲区），以 docs/harness-design-goals.md 为基线，全部论断经实测或推演验证并附 file:line。
> 结论先行：**本轮改动引入 3 个 P0**（其中两条路径恰是测试盲区），外加 2 个 P1 数据/路由风险。第一轮评审的价值在本轮得到验证——新机制复杂度上升，对抗性复查是必要的。

## 一、P0 发现（必须立即修）

### P0-1 sed 分隔符与 remote 安装路径冲突 → README 主推安装方式完全失败（R1，实测）
- `install.sh:269`：`sed -e "s|@REPAIR@|${repair_hint}|"` 用 `|` 作分隔符且**替换串未转义**；remote 分支的 repair hint 字面含 `curl ... | bash -s --`（`install.sh:464`）。
- 实测：`SCRIPT_DIR` 为空（curl 管道安装的常态）→ `sed: unknown option to 's'`，rc=1，`set -e`（:2）中止——**AGENTS.md 尚未写入，安装完全失败**。本地源路径因 hint 走本地分支而不含 `|` 所以 smoke 全绿：又一个「测试全绿但主路径已断」。
- 次要面：TARGET 含 `&` 时路径被替换成字面 `@REPAIR@`（R3 实测 `/tmp/r3&target` → `/tmp/r3@REPAIR@target`），数据损坏。
- 修复：sed 前对 repair_hint 转义 `sed 's/[&|\\]/\\&/g'`，或改为环境变量传值 / awk 占位注入，彻底退出 sed 替换串游戏。

### P0-2 awk 标记匹配与 grep 检测语义错位 → 用户内容被截断删除（R1，静态+推演）
- 检测用 `grep -qF`（**子串**），替换用 awk `$0 == 标记`（**整行精确**，`install.sh:322-334`）。
- end 标记若带前导空格或 CRLF 行尾（Windows 编辑器极常见）：grep 检出 → awk 永不复位 skip → **begin 之后的全部用户内容被删除**（数据截断）；begin 行缩进/CRLF 则静默不刷新但仍打印 `merge`（假成功）。ps1 正则无此行锚（`install.ps1:313`）→ 双实现分歧。
- 修复：awk 改 `index($0, 标记)` 子串判定与 grep 对齐；awk 未命中 end 时保留原文件并报错，而非静默截断。

### P0-3 `--agent agents`（含 `--agent all`）与迁移自碰撞 → 刚分发的文件被删、自检永久误报（R2，推演+证据链）
- `agents` 类型的分发目录就是 `$TARGET/.agents/skills`（`install.sh:179`、`install.ps1:173`），与 legacy 根路径相同。装完即迁：同源文件逐字节相同 + dst 已存在 → `rm -f`（`install.sh:374-375`）——**删除的正是本轮刚为用户装好的文件**（ps1 同构）。
- 后果链：① 显式要求的落点装完即空；② 收尾自检对 `.agents/skills` 报 missing 并 warn「re-run to repair」——**每次重跑循环复现，永远无法修复**；③ manifest 对已删文件记 `"sha256":"unknown"`（bash）/ 静默丢条目（ps1），双平台不一致。
- 修复：迁移跳过任何属于当次 `SKILL_DESTS` 的路径（或把 migrate 移到分发之前并对重合根跳过）；`.agents/skills` 同时被请求为 dest 时不得报 legacy。

## 二、P1 发现（数据/路由风险，次批次修）

| # | 发现 | 来源 |
|---|---|---|
| P1-1 | **ps1 受管段的修复命令是空白行**：`Show-RepairHint` 用 Write-Host，`Build-AgentsSection` 里 `(Show-RepairHint \| Out-String)` 捕获为空（实测）→ ps1 装的 AGENTS.md 自愈指引失效（`install.ps1:264,477`） | R1 |
| P1-2 | **定制 `.rsi/policy.yaml` 被保留但实质失效**：模板先装到 `.harness/.rsi`，定制版与模板不同 → 留原地，但新受管段只指向 `.harness/.rsi/policy.yaml`，无人告知用户其定制不再是生效副本（`install.sh:366-371`） | R2 |
| P1-3 | **旧版无标记 AGENTS.md 死指针**：merge 只追加不改写，旧正文（顶部写着 use .agents/skills/...）在迁移后指向已搬空的目录 → 核心路由入口自相矛盾（`install.sh:336-343`） | R2 |
| P1-4 | **retro-aggregate 仍锁 verdict v1**：v2 verdict 被判 INVALID → preflight 第 10 项失败 → 循环无法启动（`scripts/retro-aggregate.py:56-57`；`preflight.md:21`）；存量 20 个 v1 verdict 需决策迁移或冻结 | R4 |
| P1-5 | **G1 降级语义未进 skill 本体**：preflight 第 2/4/10 项在目标工程必然失败，rsi-loop SKILL.md 无降级条款 → 目标工程任何自检都跑不起来（基线 :22 的硬承诺只兑现在生成的 AGENTS.md 里） | R4 |
| P1-6 | ps1 `Write-If-Missing` 两个分支都不记录 `InstalledFiles` → ps1 manifest 缺全部 index.md（`install.ps1:421-430`，bash 侧正常） | R1 |
| P1-7 | rsi-loop 的 L2/L3 归属在 policy.yaml（L2）与 gate-policy/rsi-design（L3）之间直接矛盾（`policy.yaml:31-35` ↔ `gate-policy.md:25-26`） | R4 |

## 三、P2 主题归类

1. **双实现分歧簇**（G2 一致性债）：-NoSkill 时 ps1 仍预置 `.harness/skills` 到 dests 且仍校验 -Agent（bash 跳过）；受管段文案 em-dash vs ASCII、merge 空行、generated_at 时区格式、env 报告前导空行；ps1 env 无 600s 超时、& 失败即中止安装（bash 记 rc 继续）；`run-loop.ps1 -DryRun` 在无 agent 机器退出 2 而 bash 先行短路打印（实测）；agent.env 覆盖语义相反（bash source 覆盖 / ps1 保留既有）。（R1/R3）
2. **manifest 完整性簇**：`.gitignore` 与 env-report 两实现均不入 manifest；bash init 模式 files 重复条目；hash 兜底失效产生 `"sha256":""`（管道退出码吞 `||`）；基线承诺的「--check 校验 manifest 哈希」未实现（G1 承诺超前）。（R1/R4）
3. **可移植性硬伤**：迁移空目录清理 `find -empty -delete` 是 GNU 扩展，macOS 静默降级（`install.sh:391,398`）；两个 .ps1 注释含 em-dash（无 BOM + GBK 历史教训相悖）；ps1 空 legacy 根目录残留导致 `--check` 永久误报 legacy；`.rsi` 为普通文件时 ps1 崩溃；install-hooks 排斥 git worktree。（R3/R2）
4. **协议级语义冲突**：SKILL.md「never use --no-verify」 vs policy/hook 允许人工对 L1P 卡 bypass（应分主体表述）；README `agents` 行写 `.harness/skills` 而安装器映射 `.agents/skills`（后者正是迁移要清掉的旧路径）；`--check` 对 `.agents/skills` 同目录既当必需 dest 又报 legacy。（R4/R2）
5. **文档漂移**：7 处裸 `skills/...` 自指在两种布局下均不成立；`verdict-schema.md:26` 权威示例 schema_version:1 却含 v2 字段（自相矛盾）；2 处失效锚点（§4.5.x）；team-launcher 指向旧仓库 URL；round-protocol 内联示例缺 repair 字段。（R4）
6. **测试盲区（与 P0 成因高度重合）**：CLAUDE.md 既有文件两路径、畸形 begin/end 对、TARGET 特殊字符、--force 交互、manifest 内容校验、verdicts v1-WARN 分支、run-loop.ps1 全分支、远程回退自动化、并发安装（固定临时名 `.ris-new`/manifest.tmp 会互踩）——全部无覆盖。（R5）

## 四、修复批次建议

1. **批次 A（P0 止血，半天）**：sed 转义/改注入方式；awk 子串匹配+未命中保护；迁移排除当次 dests。三处都补对应 smoke 用例（特殊字符 TARGET、`--agent agents` 全链路、畸形标记对）。
2. **批次 B（P1，一天）**：ps1 repair-hint 捕获（改 Write-Output）；ps1 Write-If-Missing 记录；定制 policy 迁移指引；旧 AGENTS.md 骨架识别换新；retro-aggregate v2 兼容 + preflight 降级分支 + 层表统一（policy 吸收 rsi-loop=L3）。
3. **批次 C（P2 一致性，一天）**：双实现分歧簇逐条对齐；manifest 完整性（.gitignore 入册、去重、hash 兜底、--check 校验哈希）；`find -delete`→`rmdir`；ps1 ASCII 化；--no-verify 分主体表述；文档清扫（7 处自指、示例版本、锚点、team-launcher）。
4. **批次 D（测试资产，持续）**：R5 排序清单前 10 条；把 tmp/ 下的 e2e/verify 系列正式并入 tests/。

## 五、元结论

本轮 3 个 P0 的共同特征：**都位于测试未覆盖的路径**（remote 分支、agents-dest×migration 组合、标记行畸形输入），且其中两个曾以「全绿」形态通过——与第一轮评审 D4 的预言（「管线自身回归无人发现」）完全吻合。建议把批次 D 的「远程回退 + 特殊字符 + 组合参数」三类用例的优先级提到与批次 A 同列，因为它们是 P0 的永久解药。
