#!/usr/bin/env bash
# 用法: verify.sh [沙盒目录]  （默认当前目录；在沙盒工程根目录内运行）
set -u
SANDBOX="${1:-.}"
cd "$SANDBOX" || exit 1
fail=0

# 1) 既有测试必须全部通过（兼容性回归检查）
if ! python3 -m unittest discover -v; then
  echo "FAIL: unittest 未通过（既有行为回归）"
  fail=1
fi

# 2) main.py 不得被修改（兼容性的机械保证）
if ! grep -q "from textutil import find_urls" main.py; then
  echo "FAIL: main.py 被改动"
  fail=1
fi

# 3) 新行为 + 兼容性用例
if ! python3 - <<'EOF'
from textutil import find_urls
from main import count_urls, first_url

# 新行为：尾部标点剥除 + www. 支持
urls = find_urls("Visit http://a.com. Also www.b.org/x, and https://c.net!")
assert urls == ["http://a.com", "www.b.org/x", "https://c.net"], urls

# 各种尾部标点
assert find_urls("see http://a.com/x?") == ["http://a.com/x"]
assert find_urls("see http://a.com/y;") == ["http://a.com/y"]
assert find_urls("see www.c.net:") == ["www.c.net"]

# 契约保持：list[str]、有序、保留重复
dups = find_urls("http://a.com http://a.com www.a.com")
assert isinstance(dups, list), type(dups)
assert dups == ["http://a.com", "http://a.com", "www.a.com"], dups
assert all(isinstance(u, str) for u in dups)

# 兼容性：既有调用方式仍工作
assert count_urls("see http://a.com and https://b.org/x") == 2
assert first_url("go to http://a.com now") == "http://a.com"
assert first_url("no links") is None
assert count_urls("no links") == 0
print("new-behavior + compat checks OK")
EOF
then
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS"
fi
exit "$fail"
