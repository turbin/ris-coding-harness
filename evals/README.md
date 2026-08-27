# evals — RSI 损失函数

这是 RSI 闭环（见 `docs/rsi-design.md` §4.2）的「损失函数」：一组小型、可复现、机械可判的任务。
每个任务是一个故意留有缺陷/陷阱的沙盒小工程（Python 标准库 + unittest，无第三方依赖），
让 PM-Workers agent 在里面按 `task.md` 施工，然后机器判定 pass/fail，产出 pass@1。

## 目录结构

```text
evals/
  tasks/
    NN-slug/
      task.md       # 给 agent 看的需求描述（不含解法提示）
      setup.sh      # 入参 $1=目标目录，在其中创建初始小工程（含缺陷）
      verify.sh     # 在沙盒内运行；exit 0 = 通过；必须机械可判
      rubric.md     # 可选，人读的评分说明
  sandbox/          # gitignore 掉；每个任务的工作副本
  results/          # run-eval.sh 的输出（eval-<timestamp>.json）与 verdict 落账（§4.1）
  baseline.json     # 基线通过率；check 子命令用它做防退化闸门
  run-eval.sh
```

## 用法

```bash
./evals/run-eval.sh list                 # 列出所有任务
./evals/run-eval.sh setup                # 为全部任务（重建）沙盒；也可 setup 01-... 03-...
# --- 这一步由 agent 完成，不在脚本内 ---
# 把 evals/tasks/<slug>/task.md 交给任何 agent，让它在 evals/sandbox/<slug>/ 里施工
./evals/run-eval.sh verify               # 机械判定，打印 pass/fail 表 + pass@1，写 results/eval-<ts>.json
./evals/run-eval.sh check                # verify 后与 baseline.json 比较，低于基线 exit 1
```

`verify` 失败的任务会把完整日志留在 `evals/sandbox/<slug>/.verify-output.log`。

## 评分逻辑

- 每个任务二值判定：`verify.sh` exit 0 = pass，否则 fail。
- 汇总指标：**pass@1** = 通过任务数 / 任务总数（单次施工，不允许看 verify 结果后返工）。
- `check` 是 RSI 防退化闸门：当前 pass@1 低于 `baseline.json` 的 `pass_rate` 时 exit 1。
  基线为 `null`（尚未测量）时跳过比较。workflow 改进落地时按 §4.4 更新 baseline。

## 与 verdict schema 的关系

`run-eval.sh` 的结果与 Reviewer verdict（`docs/rsi-design.md` §4.1）都落在 `evals/results/`：

- `eval-<timestamp>.json`：本脚本产出，`{schema_version, timestamp, passed, total, pass_rate, per_task}`，
  是跨任务的**集成**指标（系统是否变好）。
- `<task-id>.yaml`：Reviewer 对单个真实任务产出物的逐维度 verdict，是**归因**输入（为什么好/坏）。

`baseline.json` 的 schema 与结果文件对齐（`schema_version` / `pass_rate` / `per_task`），演进时同步迁移。

## 新增任务指南

1. `mkdir evals/tasks/NN-slug`（NN 为两位序号，slug 用 kebab-case）。
2. 写 `task.md`：只描述需求与缺陷现象，**不给解法提示**。
3. 写 `setup.sh <target-dir>`：在目标目录构造含缺陷的初始工程；幂等（脚本会先清空沙盒）。
4. 写 `verify.sh`：在沙盒内运行，机械判定，exit 0/1；优先 `python3 -m unittest` 或内嵌 unittest 的 heredoc。
5. 质量自查（必须，缺一不可）：
   - `run-eval.sh setup <slug> && run-eval.sh verify <slug>` → 未改动的沙盒必须 **FAIL**；
   - 临时放入一个参考解 → 必须 **PASS**；然后删掉参考解重置沙盒。
6. 可选 `rubric.md` 给人看。
