# progress/loop — rsi-loop 状态目录

rsi-loop skill（`.agents/skills/rsi-loop/`）的**全部状态都在本目录**——
skill 本身无状态，中断后任何 agent 读 `state.yaml` 即可续跑。

| 文件 | 含义 |
|---|---|
| `state.yaml` | 循环状态：轮次、任务队列、门禁级别、累计指标、暂停标志（模板见 `state.yaml.example`） |
| `round-<n>.yaml` | 第 n 轮报告：任务、verdict 引用、指标、本轮变异（模板见 `round.yaml.example`） |
| `tasks.yaml` | 任务队列（可由 `--queue` 指定其他位置） |
| `preflight-<ts>.md` | 预检失败报告（预检不过不进循环） |
| `incident-<ts>.md` | 停机/事故报告（停机条件触发时写） |
| `summary-<ts>.md` | 批处理总结报告，交人工终验（不可省略） |
