# 2026-09-19 — kimi 全局 hooks 寄宿在"最后安装工程"的绝对路径上

- 状态：fixed
- 严重级别：P1（单工程删除/移动 = 所有 kimi 工程 compact-recall 失效）
- 来源：其他工程安装时反馈「hook 脚本现寄宿在本工程 scripts/ 下，若日后
  删除/移动本工程，重跑安装器刷新指向即可」

## 现象

用户级 `~/.kimi-code/config.toml` 的受管 `[[hooks]]` 块中，command 指向
**最后跑过安装器的那个工程**的绝对路径。实测（2026-09-19）：

```
command = 'powershell … -File "E:/workspace/webprotege/scripts/compact-archive.ps1"'
command = 'powershell … -File "E:/workspace/webprotege/scripts/session-recall.ps1"'
```

后果：

1. 删除/移动 webprotege（或任何最后安装的工程）→ 所有 kimi 工程的
   PostCompact 归档与 UserPromptSubmit 回顾全部失效；
2. 每在新工程执行安装器，全局指向就被改写到新工程，形成隐式依赖链。

## 复现步骤

1. 在工程 A 执行 `install.sh --agent kimi`，查看 `~/.kimi-code/config.toml`
   受管块 → 指向 A 的 `scripts/`；
2. 在工程 B 再执行一次 → 受管块改指 B；删除 B 后在任意工程触发 /compact →
   hook 静默失效（脚本 404，fail-open）。

## 根因

`scripts/install-agent-hooks.py install_kimi()` 把 `f"{root}/scripts/…"` 写入
用户级配置——机制上是"用户级配置 + 工程级路径"的错配。而 hook 脚本本身
**可迁移**：`compact-archive.py` 归档到 `<cwd>/conversations/`、按 hook stdin
的 session_id/cwd 解析工程（见其模块 docstring），不依赖脚本自身所在路径。

## 修复

- `install_kimi()` 把 6 个脚本（compact-archive.{sh,ps1,py}、
  session-recall.{sh,ps1,py}）从安装源复制到用户级稳定目录
  `$KIMI_CODE_HOME/hooks/`（幂等覆盖），注册 command 指向该目录；
- 工程内 `scripts/` 副本保留（claude/codex 的工程级 hook 仍需要）；
- 迁移零成本：受管块有 BEGIN/END 标记，任意工程重跑安装器即整体替换。

## 回归测试

`tests/compact-recall-smoke.sh` 新增用例：`KIMI_CODE_HOME` 指向沙箱，跑两次
kimi 安装，断言受管块唯一、command 指向 `$KIMI_CODE_HOME/hooks/`、脚本副本
在位、外来 `[[hooks]]` 条目保留。

## 结果

修复后实机重注册，全局 hooks 不再依赖任何工程路径。
