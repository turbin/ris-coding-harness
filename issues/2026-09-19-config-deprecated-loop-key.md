# 2026-09-19 — 用户全局 config.toml 使用废弃键 max_retries_per_step

- 状态：fixed
- 严重级别：P2（配置失效 + 启动告警）
- 来源：其他工程安装时顺带发现「config.toml 第 9 行 max_retries_per_step 是
  已废弃键（0.32.0 起改名为 max_attempts_per_step，旧键被忽略并告警）」

## 现象

`~/.kimi-code/config.toml` 第 9 行：

```toml
[loop_control]
max_retries_per_step = 3
```

kimi-code 0.32.0 起该键改名 `max_attempts_per_step`，旧键被忽略并告警——用户
自以为生效的重试上限实际未生效。

## 排查

全仓 grep `max_retries_per_step` 无匹配 → 该键**不是安装器写出的**，是用户
既有配置；修复动作 = 仅改键名、保留值。

## 复现步骤

1. 打开 `~/.kimi-code/config.toml` 第 9 行；
2. 观察 kimi-code 启动告警（deprecated key）。

## 修复

键名原地改名：`max_retries_per_step = 3` → `max_attempts_per_step = 3`。
验证：tomllib 解析成功且 `loop_control` 段仅含新键名。

## 结果

改后 TOML 解析通过，新键名生效。
