# 任务：消除重复逻辑（行为不变）

## 背景

当前目录是一个小型 Python 工程（仅标准库），包含：

- `report.py`：报表汇总模块，导出 `summarize_sales(rows)` 与 `summarize_costs(rows)` 两个函数。
- `test_report.py`：已有的 unittest 测试，覆盖了这两个函数的现有行为（含空输入边界）。

## 要求

`report.py` 中两个函数的函数体存在大段重复逻辑。请消除重复，同时满足：

1. **行为完全不变**：两个公开函数的函数名、签名、返回值结构与数值都必须与现在一致；`python3 -m unittest discover` 必须全部通过。
2. 重复出现的核心计算逻辑（累加循环、平均值计算等）在 `report.py` 中只保留一份。
3. 不引入任何第三方依赖。
