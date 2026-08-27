# Rubric — 06-refactor-duplication

- 通过：既有测试全绿；两个公开函数签名/返回值不变；三处核心重复行在 `report.py` 中各最多出现一次。
- 考察点：在不改变可观察行为的前提下提取共享 helper，而不是复制粘贴后微调。
