# 任务：新增待办查询（遵循工程约定）

## 背景

当前目录是一个小型 Python 工程（仅标准库），包含：

- `db.py`：数据访问层（唯一的 SQLite 访问入口）。
- `todo.py`：已有函数 `get_todo(todo_id)`，展示了本工程的约定。
- `test_todo.py`：已有测试。

## 工程约定（务必遵循）

1. 所有数据访问必须经过 `db.fetch_all`，**不得**直接 import 或使用 sqlite3。
2. 函数不抛异常：成功返回 `{"ok": True, "data": ...}`，失败返回 `{"ok": False, "error": "..."}`。
3. 函数名使用 snake_case，模块只导出公开函数。

## 要求

在 `todo.py` 新增 `list_todos(done_only=None)`：

- 返回全部待办，按 id 升序，每条包含 `id`、`title`、`done` 字段。
- `done_only=True` 只返回已完成（done=1）的；`done_only=False` 只返回未完成的；
  `done_only=None` 返回全部。
- 工程内无待办时返回 `{"ok": True, "data": []}`（不是错误）。
- 不得修改 `db.py` 与 `test_todo.py`；`python3 -m unittest discover` 必须通过。
- 不引入任何第三方依赖。
