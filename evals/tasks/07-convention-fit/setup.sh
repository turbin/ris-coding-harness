#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?usage: setup.sh <target-dir>}"
mkdir -p "$TARGET"

cat > "$TARGET/db.py" <<'EOF'
"""数据访问层：本工程所有数据访问必须经过本模块的 helper。"""

import sqlite3

_conn = sqlite3.connect(":memory:")
_conn.row_factory = sqlite3.Row

_conn.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
_conn.execute("CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, item TEXT, price REAL)")
_conn.executemany(
    "INSERT INTO users (id, name) VALUES (?, ?)",
    [(1, "alice"), (2, "bob")],
)
_conn.executemany(
    "INSERT INTO orders (id, user_id, item, price) VALUES (?, ?, ?, ?)",
    [(1, 1, "book", 12.5), (2, 1, "pen", 1.5), (3, 2, "mug", 8.0)],
)


def fetch_all(query, params=()):
    """执行查询并以 dict 列表返回全部行。这是本工程唯一允许的数据访问入口。"""
    cur = _conn.execute(query, params)
    return [dict(r) for r in cur.fetchall()]
EOF

cat > "$TARGET/users.py" <<'EOF'
"""用户查询。本工程约定：

- 所有数据访问必须经过 db.fetch_all，不允许直接 import sqlite3。
- 函数不抛异常；成功返回 {"ok": True, "data": ...}，失败返回 {"ok": False, "error": "..."}。
"""

import db


def get_user(user_id):
    rows = db.fetch_all("SELECT id, name FROM users WHERE id = ?", (user_id,))
    if not rows:
        return {"ok": False, "error": "user not found"}
    return {"ok": True, "data": rows[0]}
EOF

cat > "$TARGET/test_users.py" <<'EOF'
import unittest

import users


class TestUsers(unittest.TestCase):
    def test_get_existing_user(self):
        self.assertEqual(users.get_user(1), {"ok": True, "data": {"id": 1, "name": "alice"}})

    def test_get_missing_user(self):
        self.assertEqual(users.get_user(999), {"ok": False, "error": "user not found"})


if __name__ == "__main__":
    unittest.main()
EOF
