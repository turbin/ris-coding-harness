#!/usr/bin/env bash
set -euo pipefail
fail=0
if ! python3 - <<'PY'
import sys, unittest
sys.path.insert(0, ".")
import todo


class TestListTodos(unittest.TestCase):
    def test_all(self):
        r = todo.list_todos()
        self.assertTrue(r["ok"])
        self.assertEqual([t["id"] for t in r["data"]], [1, 2, 3])
        self.assertEqual(set(r["data"][0]), {"id", "title", "done"})

    def test_done_only(self):
        self.assertEqual([t["id"] for t in todo.list_todos(done_only=True)["data"]], [2])

    def test_open_only(self):
        self.assertEqual([t["id"] for t in todo.list_todos(done_only=False)["data"]], [1, 3])

    def test_empty_db_shape(self):
        # 无匹配项返回空列表而非错误
        self.assertEqual(todo.list_todos(done_only=True)["ok"], True)
        self.assertIsInstance(todo.list_todos(done_only=True)["data"], list)


unittest.main(verbosity=1)
PY
then
  echo "FAIL: unit tests" >&2
  fail=1
fi
if grep -q "sqlite3" todo.py; then
  echo "FAIL: todo.py 不得直接引用 sqlite3（含注释/docstring）" >&2
  fail=1
fi
exit "$fail"
