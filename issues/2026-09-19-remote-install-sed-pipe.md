# 2026-09-19 — 远程 curl|bash 安装因 repair hint 管道符撞 sed 定界符而中断

- 状态：fixed
- 严重级别：P0（远程安装完全不可用）
- 来源：其他工程安装时反馈「上游 sed bug，远程 curl | bash 安装在带 --agent 时必现」

## 现象

远程安装（`curl -fsSL …/install.sh | bash -s -- --target . --agent kimi`）在生成
AGENTS.md 受管段阶段报错退出，目标工程内除空目录外什么都没写出：

```
sed: -e expression #1, char 101: unknown option to `s'
```

本地 clone 后执行同一命令不复现（repair hint 不含管道符）。

## 复现步骤

1. `curl -fsSL https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.sh | bash -s -- --target /tmp/demo --agent kimi`
2. 观察报 `sed: unknown option to 's'`，退出码非 0，`/tmp/demo` 无 AGENTS.md。

最小复现（等价表达式）：

```bash
hint='curl -fsSL https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.sh | bash -s -- --agent kimi'
printf 'x\n' | sed -e "s|@REPAIR@|${hint}|"   # → sed: unknown option to `s'
```

## 根因

`install.sh` 的 `build_agents_section()` 把 repair hint 插值进
`sed -e "s|@REPAIR@|${repair_hint}|"` 的**替换串**。远程模式下
`print_repair_hint` 走 else 分支，hint 为
`curl -fsSL …/install.sh | bash -s -- --target "…" --mode adopt`，其中的管道符
`|` 与 sed 定界符 `|` 冲突 → sed 解析失败；`set -euo pipefail` 使整个安装中断。
带不带 `--agent` 均触发（管道符来自 curl|bash 形态本身，与 --agent 无关；
反馈方当时只测了带 --agent 的组合）。

修复方案取舍：`s/[&|\\]/\\&/g` 式转义在本机 Git Bash sed 上实测产出**损坏的**
替换结果（非报错、静默错字），不可用；改用 awk 行拼接（与同文件
`merge_managed()` 已有模式一致），hint 经临时文件 + `getline` 注入，不经过
sed 替换串。

## 修复

- `install.sh build_agents_section()`：`@BEGIN@/@END@` 仍走 sed（常量、无特殊
  字符）；`@REPAIR@` 行改为 awk 从临时文件 getline 拼接。
- 回归测试：`tests/install-smoke.sh` 提取真实函数体、桩掉 `print_repair_hint`
  为含 `|` 的远程形态，断言输出含管道原文、无残留占位符（修复前为红）。

## 结果

修复后回归测试绿；本地安装冒烟（install-smoke.sh）全量通过。
