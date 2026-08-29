#!/usr/bin/env bash
# Creates the initial project in $1.
set -euo pipefail
cat > "$1/db.py" <<'PY'
"""数据访问层：本工程所有数据访问必须经过本模块的 helper。"""

import sqlite3

_conn = sqlite3.connect(":memory:")
_conn.row_factory = sqlite3.Row

_conn.execute("CREATE TABLE todos (id INTEGER PRIMARY KEY, title TEXT, done INTEGER)")
_conn.executemany(
    "INSERT INTO todos (id, title, done) VALUES (?, ?, ?)",
    [(1, "write docs", 0), (2, "ship release", 1), (3, "retro", 0)],
)


def fetch_all(query, params=()):
    """执行查询并以 dict 列表返回全部行。这是本工程唯一允许的数据访问入口。"""
    cur = _conn.execute(query, params)
    return [dict(r) for r in cur.fetchall()]
PY
cat > "$1/todo.py" <<'PY'
"""待办查询。本工程约定：

- 所有数据访问必须经过 db.fetch_all。
- 函数不抛异常；成功返回 {"ok": True, "data": ...}，失败返回 {"ok": False, "error": "..."}。
"""

import db


def get_todo(todo_id):
    rows = db.fetch_all("SELECT id, title, done FROM todos WHERE id = ?", (todo_id,))
    if not rows:
        return {"ok": False, "error": "todo not found"}
    return {"ok": True, "data": rows[0]}
PY
cat > "$1/test_todo.py" <<'PY'
import unittest
import todo


class TestGetTodo(unittest.TestCase):
    def test_existing(self):
        self.assertEqual(
            todo.get_todo(1),
            {"ok": True, "data": {"id": 1, "title": "write docs", "done": 0}},
        )

    def test_missing(self):
        self.assertEqual(todo.get_todo(999), {"ok": False, "error": "todo not found"})


if __name__ == "__main__":
    unittest.main()
PY
