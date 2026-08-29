---
name: min-loop
description: 最小闭环（Minimal Loop）：以单个 spec 为输入的最小自动闭环——同一 agent 会话内按序扮演 PM / Coder / Reviewer，从 spec 到 MILESTONE ACCEPTED，产出报告。零 RSI 机制（无子代理、无 eval、无 retro、无 skill 进化），token 开销最小，适合预算有限的真实工程日常任务。触发词：「最小闭环」「min-loop」「跑 spec」「按 spec 完成」「spec 任务闭环」。
version: 1.0.0
---

# Min-Loop（最小闭环）

## 这是什么

RSI 全流程（rsi-loop）的**最小化切片**：一次调用、一个 spec、一个闭环。
只保留工程交付闭环本身，去掉编排层（state/round 文件、任务队列、retro、
eval、门禁回写、skill 进化）。

```
spec → PM 拆解 → Coder TDD(RED→GREEN) → Reviewer 对抗审阅 → 修复/举证
     → MILESTONE ACCEPTED → 报告 output/specs/<spec>.md → 汇报
```

与 rsi-loop 的关系：rsi-loop 的**每一轮子代理工作 ≈ 一次 min-loop**。
min-loop 不产出自改进资产（verdict/round/state），因此不进 retro、不触发
harness 变更——它只交付，不进化。

## 启动方法

交互式（首选，任何 agent 都适用）：

```text
# pi：斜杠命令带 spec 路径
/skill:min-loop docs/specs/cache-ttl.md

# 其他 agent（claude/kimi/opencode/codex…）：提示词中显式指定本 SKILL.md 路径
# 「按 <SKILL.md 绝对路径> 的 min-loop 流程完成 spec：<spec 路径>」
```

批处理（可选薄壳）：`./run-specs.sh` 遍历 `docs/specs/*.md`，headless
逐个调用，报告落 `output/specs/`。交互式入口是标准用法，薄壳仅供无人值守。

## 流程（同一 agent 会话内顺序扮演，不启子代理）

1. **读 spec**：参数指定的路径，或 `docs/specs/` 下的文件。spec 是唯一需求源。
2. **工程规则**：`docs/engineering/index.md` 存在则按需加载相关规则；
   不存在则跳过——**不得臆造 build/test 命令**（见停机条件 1）。
3. **PM 拆解**：把 spec 拆成最小里程碑集（一个 spec 通常一个里程碑）。
4. **Coder TDD**：先 RED（一条能复现缺陷/需求的失败测试或最小复现），
   再实现，后 GREEN。纯重构须先有 GREEN 基线。
5. **Reviewer 对抗审阅**：从正确性（含边界）、测试质量、简洁性、资源、
   约定契合、范围六个维度自审；发现问题回第 4 步，直到无 BLOCKER/MAJOR。
6. **验收**：输出 `MILESTONE ACCEPTED`（或 `MILESTONE REJECTED` + 原因）。
7. **报告**：写 `output/specs/<spec-name>.md`（格式见下），并汇报
   `DONE / PARTIAL / BLOCKED`。

## 报告格式（output/specs/<spec-name>.md）

```markdown
# Spec: <spec 名>
- 状态: DONE | PARTIAL | BLOCKED
- 里程碑: <名称> — MILESTONE ACCEPTED
- 变更: <文件清单；loc +N/-M>
- RED 证据: 是/否（一句说明）
- 审阅往返: <次数>
- 遗留问题: <issues 或 "无">
- 时间: <ISO 8601>
```

## 停机条件（最小集，任一触发即停下询问）

1. **build/test 命令未知**：规则文件与仓库证据（manifest/CI/README）都缺时，
   不得臆造命令——停下问用户。
2. **验收不可判定**：spec 的验收标准既无法机械验证也无法人工判定时——停下问。
3. **protected 触碰**：工程存在 `.rsi/policy.yaml`（或等价约定）时，其
   protected files 一律不碰——发现需要触碰才能完成 spec，停下汇报。

## Token 纪律

- 只加载任务相关上下文（渐进披露），不预读全仓库。
- 不创建 state/round/retro/verdict 文件（那是 rsi-loop 的资产）。
- 一次会话内完成，不跨会话续跑。
