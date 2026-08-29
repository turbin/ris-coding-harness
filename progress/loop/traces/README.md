# progress/loop/traces — 子代理执行轨迹（P6, 2026-08-29）

每个 rsi-loop 轮次的子代理**完整执行轨迹**落库于此，作为 verdict 之外的
审计证据：真实工程任务没有 `verify.sh` 机器判定，人工验收依赖
「Reviewer verdict + 执行轨迹」双证据链。

## 命名约定

```text
round-<n>-<task-id>.<agent>            # pi: 完整会话 jsonl（所有工具调用+输出）
round-<n>-<task-id>.<agent>/           # kimi: 会话目录（context.jsonl + wire.jsonl + state.json）
```

- **pi**：派单时用 `pi -p --session-dir progress/loop/traces/ ...`，会话直接落库；
  或跑完后从 `~/.pi/agent/sessions/<cwd-dir>/` 拷贝。
- **kimi**：跑完后从 `~/.kimi/sessions/<id>/` 拷贝会话目录。
- 其他 agent：等价地保存其会话存储，或把完整输出流 tee 到
  `round-<n>-<task-id>.log`。

## 协议要求（round-protocol.md）

- SPAWN 环节必须捕获轨迹；无轨迹 = 轮次无效（与无 verdict 同级）。
- round 报告必须带 `trace_file:` 字段引用本目录内的轨迹文件。

## 回溯说明

`round-{1..5}` 为 loop-real-01（2026-08-29）的轨迹**回填**：当时派单未落库，
会话仍保存在本机 agent session store，现已拷贝入库并引用。自 P6 起新轮次
直接落库，不再依赖回填。
