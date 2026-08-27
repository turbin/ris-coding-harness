# 任务：修复折扣计算

## 背景

当前目录是一个小型 Python 工程（仅标准库），包含：

- `cart.py`：购物车模块，提供 `apply_discount(price, percent)`。
- `test_cart.py`：已有测试（当前全部通过）。

## 规格（以此为准）

`apply_discount(price, percent)` 应返回**打折扣后的最终价格**：

- `apply_discount(200, 10)` → `180.0`（原价减去 10%）
- `percent` 为 `0` 时返回原价；为 `100` 时返回 `0.0`
- `percent` 超出 `[0, 100]` 区间时必须抛出 `ValueError`

## 要求

1. 当前实现不符合上述规格，请修复 `cart.py` 使其完全符合规格。
2. 交付时 `python3 -m unittest discover` 必须全部通过——工程内所有测试都必须与上述规格一致。
3. 保持函数签名 `apply_discount(price, percent)` 不变；不引入任何第三方依赖。
