# 2026-09-23 — graphify 规模门：init/adopt 阶段按工程文件数决定是否启用 graphify

- 层级：L3（资产新增：安装器选项 + 仓库级阈值配置 + AGENTS 模板路由段）
- 状态：已落地（bash/ps1 双侧 + 双冒烟覆盖）
- 关联：`decisions/2026-09-20-zvec-search-routing.md`（graphify 路由的出处）、
  `decisions/2026-09-21-ponytail-integration.md`（同属"按证据收敛工具范围"的路线）

## 背景

graphify 自称代码库问题的第一跳，但它的图质量随工程规模迅速退化：节点爆炸后
社区结构、god node 与跨文件关系的信噪比下降，`graphify-out/` 也会变成仓库里
最大的一块本地产物。此前路由段无条件写着"结构/关系/架构 → graphify（存在
`graphify-out/` 时）"，等于把"该不该建图"完全交给模型临场判断——没有可审计的
判据，也没有工程级的一致答案。

## 决策

1. **口径 = 文件数**（先用这个，后续按 graphify 实际运行提示校准）：
   - 有 `.git`：`git ls-files | wc -l`（只算被跟踪文件，天然排除依赖与构建产物）；
   - 无 `.git`：遍历文件并按忽略清单剪枝 `.git`、`node_modules`、`.venv`、`venv`、
     `target`、`build`、`dist`、`out`、`__pycache__`、`.next`、`.gradle`、`.idea`、
     `.cache`、`.zvec-grep`、`.codegraph`；
   - 计数发生在本次安装写入之前，判的是工程自身规模，不是 harness 落位后的文件数。
2. **阈值 = 483**，锚点工程 `zotero-plugin-ai4paper`（2026-09-23 全工作区 33 个
   工程目录按文件数取中位）。
3. **判定**：`文件数 ≤ 阈值` → graphify **on**；`> 阈值` → **off**。
4. **阈值落点**：仓库级配置 `.harness/graphify-threshold.txt`（纯文本、可 grep、
   `#` 注释），安装器读该文件取值；文件缺失或值非法时回退内置默认 483 并在
   stderr 告警。改阈值不必动安装器代码。
5. **覆盖开关** `--graphify auto|on|off`（PowerShell 侧 `-Graphify`），默认 `auto`
   按阈值判定；非法值退出码 2，与既有用法错误契约一致。
6. **结论三处落点**：① `.harness/manifest.json` 的 `graphify` 块
   `{decision, metric, value, threshold, source}`；② 受管 `AGENTS.md` 路由段注入
   对应文案（on 保留 graphify 一行并提示首次使用前 `graphify update .`；off 换成
   显式禁用文案——不要使用 graphify、不要构建 `graphify-out/`，结构类查询改用
   `zg query` + CodeGraph）；③ 安装输出一行结论（如 `graphify off (500 files > 483)`）。
7. **与 `--search off` 的关系**：graphify 条目位于 `@SEARCH@` 注入块内，
   `--search off` 时整块不注入，graphify 路由随之跳过；manifest 的 `graphify` 块与
   输出结论不受 `--search` 影响，始终记录（该关系写进 `--help` 与 README）。

## 备选与拒绝

- **LOC（代码行数）** → 拒绝：同为 22 万行级的两个工程图规模差近一倍
  （zotero-plugin-ai4paper 222k LOC→5,458 节点 vs ino 221k LOC→10,314 节点），
  LOC 与图规模不同构，不能当判据。
- **图节点数 / `graph.json` 体积** → 拒绝作为 init 阶段判据：init 时图还不存在，
  用它等于要求"先建图才知道该不该建图"；且文件数与图规模的排序本身背离
  （483 文件→5,458 节点，而 2,574 文件的 turbo-pi-gateway 无 graph.json），
  体积中位候选也分散（npt-lobster 5.2MB / zotero-plugin-ai4paper 20.4MB）。
- **备选中位 666（WrenAI）** → 不采用：该数字来自剔除近空目录后的重算，锚定的是
  "筛过的样本"而非工作区真实分布；保留在记录里供校准参考，不作为默认值。
- **安装期自动建图/删图** → 拒绝：建图是重活且带网络不确定性，判定只决定"路由怎么
  写"，不代模型执行图操作。

## 校准协议

阈值是待校准参数，不是恒值：graphify 在真实工程上的运行提示（节点数、截断、
降级/不可信的告警，以及 `graphify-out/` 体积）是校准信号。收到这类信号后，改
`.harness/graphify-threshold.txt` 的 `threshold:` 一行即可生效，同步更新本记录的
锚点与日期；口径若要从文件数换成别的度量，则需另开决策记录。

## 待办

- ~~**工作区级 AGENTS.md 路由一致性**~~ 已解决（2026-09-23，方案①）：`E:\workspace\AGENTS.md`
  §graphify Rules 首条补工程级覆盖规则——受管段标注 DISABLED 的工程不使用 graphify、不建
  `graphify-out/`，改用 `zg` + CodeGraph。
- ~~**模型按需补全拓扑形态**~~ 已决策（2026-09-23，形态③：现算 + 落盘缓存）：
  见 `decisions/2026-09-23-topology-synthesis.md`（`architecture-topology` skill，user 级）。
  首次真实使用后的合成质量/成本校准仍开放。

## 影响

- `install.sh` / `install.ps1`：新选项 + 校验（非法值 exit 2）+ 阈值读取 + 文件计数
  + 路由段条件注入 + manifest 块 + 输出结论 + `--help`；
- `tests/install-smoke.sh` / `tests/install-smoke.ps1`：新增 auto-on、auto-off（500
  文件）、`--graphify on|off` 覆盖、非法值 exit 2、阈值文件驱动与缺文件回退、
  `--search off` 不注入但仍记录共 6 组断言；
- 受管段多出 graphify 启用/禁用条目（禁用文案即"不建图"的工程级声明）；
- 生成工程的 manifest 多出 `graphify` 块，供 agent 期与审计复用。

## 回滚

`--graphify on` 即恢复旧行为（无条件 graphify 路由）；移除选项后受管段随下次安装
刷新为旧内容。
