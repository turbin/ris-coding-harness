# 任务：新增订单查询功能

## 背景

当前目录是一个小型 Python 工程（仅标准库），包含：

- `db.py`：数据访问层。
- `users.py`：用户查询功能。
- `test_users.py`：已有测试。

在动手前，请先阅读现有代码，理解本工程的既有写法与约定。

## 要求

新增 `orders.py`，提供函数 `get_orders_for_user(user_id)`：

1. 给定一个**存在**的用户 id，返回该用户的全部订单（按订单 id 升序），每条订单包含 `id`、`item`、`price` 字段。
2. 给定一个**不存在**的用户 id，必须返回错误结果，错误信息为 `"user not found"`。
3. 遵循本工程已有的代码约定（数据访问方式、返回结构、错误处理方式），与现有模块保持一致。
4. `python3 -m unittest discover` 必须全部通过，且不得修改 `db.py`、`users.py` 与 `test_users.py`。
5. 不引入任何第三方依赖。
