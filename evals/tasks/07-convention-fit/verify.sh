#!/usr/bin/env bash
# 用法: verify.sh [沙盒目录]  （默认当前目录；在沙盒工程根目录内运行）
set -u
SANDBOX="${1:-.}"
cd "$SANDBOX" || exit 1
fail=0

# 1) 既有测试必须全部通过（不得破坏现有功能）
if ! python3 -m unittest discover -v; then
  echo "FAIL: unittest 未通过"
  fail=1
fi

# 2) 新文件存在
if [ ! -f orders.py ]; then
  echo "FAIL: orders.py 不存在"
  fail=1
else
  # 3) 约定检查：复用既有数据访问 helper
  if ! grep -q "import db" orders.py || ! grep -q "db\.fetch_all" orders.py; then
    echo "FAIL: orders.py 必须复用 db.fetch_all（本工程唯一数据访问入口）"
    fail=1
  fi
  # 4) 约定检查：不得绕过 helper 直接访问 sqlite3
  if grep -q "sqlite3" orders.py; then
    echo "FAIL: orders.py 不得直接引用 sqlite3"
    fail=1
  fi
  # 5) 约定检查：遵循既有错误返回模式，且不抛异常
  if ! grep -qE "['\"]ok['\"]: False" orders.py; then
    echo "FAIL: orders.py 未遵循 {'ok': False, 'error': ...} 错误返回模式"
    fail=1
  fi
  if grep -qE "(^|[[:space:]])raise[[:space:]]" orders.py; then
    echo "FAIL: orders.py 不得抛异常（本工程约定用错误返回值）"
    fail=1
  fi
fi

# 6) 功能测试
if ! python3 - <<'EOF'
import orders

r = orders.get_orders_for_user(1)
assert isinstance(r, dict) and r.get("ok") is True, f"existing user: {r}"
data = r["data"]
assert isinstance(data, list) and len(data) == 2, f"orders count: {r}"
assert data[0]["id"] == 1 and data[0]["item"] == "book" and data[0]["price"] == 12.5, r
assert data[1]["id"] == 2 and data[1]["item"] == "pen", r
assert all(set(o) >= {"id", "item", "price"} for o in data), r

r2 = orders.get_orders_for_user(2)
assert r2["ok"] is True and len(r2["data"]) == 1 and r2["data"][0]["item"] == "mug", r2

r3 = orders.get_orders_for_user(999)
assert r3 == {"ok": False, "error": "user not found"}, f"missing user: {r3}"
print("functional checks OK")
EOF
then
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS"
fi
exit "$fail"
