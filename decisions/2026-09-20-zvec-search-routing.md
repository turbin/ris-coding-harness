# 2026-09-20 — zvec 检索路由分工 + 安装器 `--search` 初始化选项

- 层级：L3（资产新增：安装器选项 + AGENTS 模板路由段）
- 状态：已落地（bash/ps1 双侧 + 冒烟覆盖）
- 关联：用户指令「启用 zvec 与 graphify 的分工，zvec 加入工程初始化选项，默认依赖安装」

## 背景

`zvec-grep`（`zg`，npm 包 `@zvec/zvec-grep`）与 `graphify` 都是用户级检索技能，
且都自称"代码库问题的默认第一跳"（zvec: *default search tool*；graphify:
*first run graphify query*）。能力上互补（zvec=证据检索，graphify=结构图谱），
但路由声明互相竞争；本机 workspace 与各工程此前都没有二者的索引/图，冲突
只是潜在的。

## 决策

1. **检索分工写入用户指令层** `E:\workspace\AGENTS.md`（优先级最高，压掉两个
   skill 的 default 竞争）：精确查找→原生 Grep/Glob；模糊/语义找证据→`zg`；
   结构/关系→graphify；调用链/影响面→CodeGraph。典型链路：zg 取证 →
   graphify/CodeGraph 释结构 → 原生工具核实。
2. **安装器新增 `--search zvec|off`（默认 zvec）**，bash/ps1 对等：
   - AGENTS.md 受管段注入 "Search routing" 分工块；
   - env 阶段探测 `zg`：缺失且有 npm 时 `npm install -g @zvec/zvec-grep`
     （zg 实为 npm 包 wrapper，渠道权威、非臆造）；无 npm 记 UNKNOWN 附指引；
   - 生成 .gitignore 模板增加 `.zvec-grep/`。
3. **索引延迟到首次模糊搜索**：安装期不建索引（首建可能触发本地嵌入模型
   下载，会拖慢 init 且有网络不确定性）；路由段约定首次模糊搜索时
   `zg status` → `zg index`（zvec 技能自身工作流一致）。

## 备选与拒绝

- PreToolUse hook 硬接管 Grep 工具 → 拒绝：精确查找原生工具更快，且 hook
  强制改写违反工具自治；分工用指令层约定即可。
- 安装期自动 `zg index` → 拒绝（理由见决策 3）；如需立即建索引，工程内
  手动跑一次 `zg index` 即可。

## 影响

- `install.sh` / `install.ps1`：新选项 + 校验（非法值 exit 2）+ 模板/模板段
  + env 阶段 + .gitignore 模板；
- `tests/install-smoke.sh` / `tests/install-smoke.ps1`：新增默认路由、
  `--search off`、非法值、env-report zvec 行、无急切索引、gitignore 共 7 组断言；
- 生成工程的 AGENTS.md 多出受管检索分工段（`--search off` 可关闭）；
- PS 侧顺带修复：`Invoke-EnvCommand` 在 PS 5.1 EAP=Stop 下原生 stderr 会抛
  NativeCommandError 的老问题（现临时降级 EAP，符合 env 仅告警契约）；
- **Windows 多 shell 现实**：npm 全局 shim 按 shell 各异（sh/.cmd/.ps1），且
  npm prefix 目录可能根本不在 PATH——PS 侧探测链为 `zg.cmd`/`zg.exe` →
  经 `bash -lc` 探测 → 才落 npm 兜底；重装后按"可执行"复核而非"存在于
  PATH"（2026-09-20 实测：EAP=Stop 下 npm 中断会让 sh wrapper 残留失效，
  PS 直调 `zg` 静默无输出）。

## 回滚

`--search off` 即回到旧行为；移除选项后受管段随下次安装刷新为旧内容。
