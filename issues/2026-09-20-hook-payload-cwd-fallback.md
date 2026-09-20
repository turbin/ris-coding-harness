# 2026-09-20 — hook payload 缺 cwd 时回退 os.getcwd()，归档写进 System32

- 状态：fixed
- 严重级别：P1（所有工程的真实压缩归档从不落入工程 `conversations/`，且污染系统目录）
- 来源：用户要求「验证一下是否产生摘要信息，并成功落盘」——本会话首次真实
  /compact 后触发排查

## 现象

2026-09-20 17:49（本地）本工程会话 `session_b43a41db` 手动 /compact，压缩成功
（`compaction.completed`：148 条消息，140k→32k tokens），简报也在下一条 prompt
注入（含 09:49:24Z 条目），但：

- 本工程 `conversations/index.md` 无任何条目（mtime 停在 09-15）；
- `conversations/archive/`、`conversations/.state/` 均为空；
- 归档实际写在 **`C:\Windows\System32\conversations\`**（index.md、
  `archive/session_b43a41db…/2026-09-20T09-49-24Z.md`、`.state/recall-…` 全套）。

## 复现步骤

1. kimi 服务进程以 `C:\Windows\System32` 为 cwd 启动（Windows 服务/调度器拉起
   的典型特征）；
2. 任意工程内触发 /compact → PostCompact hook 触发 `compact-archive.py`；
3. 检查工程 `conversations/` → 空；检查 `C:\Windows\System32\conversations\`
   → 归档在位。

## 根因

两个脚本解析工程目录的逻辑是
`cwd = payload.get("cwd") or os.getcwd()`。官方文档
（kimi-code docs / customization/hooks）承诺每个 hook 事件的基础 payload 都带
`cwd`，且「hook 命令的工作目录是当前会话的工程目录」；但实测当前 CLI 版本
PostCompact/UserPromptSubmit payload **不含 cwd**，进程 cwd 也不是工程目录而是
服务进程 cwd（System32）→ 静默归档到错误位置。文档承诺与实现不符，脚本却
无条件信任 `os.getcwd()` 这个最不可靠的回退。

## 修复

- `compact-archive.py` / `session-recall.py` 新增 `resolve_cwd()`：
  1) payload `cwd`（存在且为目录）；
  2) `session_index.jsonl` 按 `session_id` 查 `workDir`（最后一条匹配为准）；
- **彻底移除 `os.getcwd()` 回退**：解析失败一律 fail-open 并在 stderr 记原因，
  宁可不归档也不写错位置；
- 冒烟用例 6（claude payload）补上真实契约中的 `cwd` 字段，不再依赖测试进程
  的 getcwd 兜底。

## 回归测试

`tests/compact-recall-smoke.sh` 新增两条用例（在无 `conversations/` 的中性
cwd 下运行，杜绝 getcwd 巧合通过）：

- PostCompact payload **不带 cwd**、仅 `session_index.jsonl` 有 `workDir` →
  归档必须落在 workDir 工程，中性目录不得产生任何文件；
- UserPromptSubmit payload **不带 cwd** → 仍按 workDir 读索引并输出简报。

## 后续加固（同日，TDD，两轮红绿）

按 `docs/plans/2026-09-20-compact-recall-hardening.md` 执行，critic 审查见
`docs/critic-review-2026-09-20.md`（终态 29/29 + install/trigger PASS）：

- **归档回执**：成功归档追加 `conversations/.state/archive-log.jsonl`
  （archived_at/compact_time/session/file；事件日志语义，去重重跑亦追加）；
- **标题回退**：payload 缺 `session_title` 时优先取会话 `state.json` 的
  `title`，缺失回退 `lastPrompt` 首行（≤100 字符；仅 kimi wire 流）；
- **kimi `--check` 漂移自检**：寄宿副本与仓库源哈希一致 + 受管块事件/命令
  完整性；扫描范围限定受管块内（外来 hook 含同名词不误报）；只报告不修复；
- **迭代 2（critic 发现）**：拒绝非绝对路径 payload cwd（防进程 cwd 锚定
  写入）；`--check` 扫描限定受管块；标题优先策展 `title`；
- **契约矩阵**：本轮新增用例 13–19 共 7 条（bogus cwd、不可解析 fail-open、
  相对 workDir、标题回退与优先级、篡改检出、外来词不误报、相对 cwd 拒绝），
  覆盖本次事故全部成因。

## 结果

修复后实机重注册 + 真实会话 E2E：`session_b43a41db` 的 09:49:24Z 归档落入本
工程 `conversations/`，front matter `cwd` 为工程路径；简报注入正常。
`C:\Windows\System32\conversations\` 属 bug 产物，需手动删除：

```sh
rm -rf /c/Windows/System32/conversations   # cmd: rmdir /s /q C:\Windows\System32\conversations
```

加固后用真实会话数据重放（寄宿脚本、无 cwd payload）：归档重生成且带真实
`session_title`（取自 `state.json` 的 `title`），回执首条实机落盘，索引去重
正常（index unchanged）。遗留两项：① codex/claude 真实 payload 键集待采集
（现依赖文档契约，采集后补无-cwd 用例）；② 提交时 `conversations/archive/`
归档文件需与 `conversations/index.md` 索引行同提交，避免索引悬空引用。
