#!/usr/bin/env bash
# 用法: verify.sh [沙盒目录]  （默认当前目录；在沙盒工程根目录内运行）
set -u
SANDBOX="${1:-.}"
cd "$SANDBOX" || exit 1
fail=0

# 1) 工程内测试必须全部通过（且必须与规格一致，否则功能检查会拦下）
if ! python3 -m unittest discover -v; then
  echo "FAIL: unittest 未通过"
  fail=1
fi

# 2) 独立功能检查（按规格断言真实行为，不参考工程内测试）
if ! python3 - <<'EOF'
from cart import apply_discount

assert apply_discount(200, 10) == 180.0, apply_discount(200, 10)
assert apply_discount(100, 0) == 100.0, "0% 应返回原价"
assert apply_discount(100, 100) == 0.0, "100% 应返回 0.0"
assert abs(apply_discount(99.99, 33.3) - 66.6933) < 1e-3, apply_discount(99.99, 33.3)

for bad in (-1, 101, 200):
    try:
        apply_discount(100, bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f"percent={bad} 必须抛出 ValueError")
print("spec checks OK")
EOF
then
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS"
fi
exit "$fail"
