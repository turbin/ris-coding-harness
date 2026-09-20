# 2026-09-19 — skill/hook 生效时机缺文档

- 状态：fixed
- 严重级别：P3（产品行为，非 bug；安装后体验断层）
- 来源：其他工程安装时反馈「工程级 skill 需新会话加载；config.toml 的 hook
  变更可在 TUI 里 /reload 立即生效，或下次启动自动加载」

## 现象

安装器完成 skill 分发与 hook 注册后，不告知生效时机：用户在已开着的会话里
找不到新 skill、hook 也没跑，误以为安装失败。

实际行为（kimi-code 产品语义）：

- 工程级 skill：**新会话**加载，已开会话不可见；
- `config.toml` hook 变更：TUI 里 `/reload` 立即生效，或下次启动自动加载。

## 复现步骤

1. 在运行中的 kimi-code 会话里对当前工程执行 `install.sh --agent kimi`；
2. 立即 `/skills` 查看 → 新 skill 不在；触发 /compact → hook 未注册生效。

## 根因

README §5（compact-recall）与安装器输出均未写生效时机。

## 修复

- `install-agent-hooks.py` kimi 分支日志补：「/reload 或重启生效」；
- README §5 补「生效时机」小节（hook 的 /reload 语义、skill 的新会话语义），
  并同步 kimi hooks 新寄宿模型（`~/.kimi-code/hooks/`，不依赖工程路径）。

## 结果

安装输出与文档都能回答"装完为什么还没生效/怎么让它生效"。
