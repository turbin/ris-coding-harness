#!/usr/bin/env bash
# 用法: verify.sh [沙盒目录]  （默认当前目录；在沙盒工程根目录内运行）
set -u
SANDBOX="${1:-.}"
cd "$SANDBOX" || exit 1
fail=0

# 1) 既有测试必须通过
if ! python3 -m unittest discover -v; then
  echo "FAIL: unittest 未通过"
  fail=1
fi

# 2) 幂等性检查：连续执行 N 次，结果恒定且注册表有界
if ! python3 - <<'EOF'
import events

expected = ["logged:a", "audited:a", "logged:b", "audited:b"]
N = 25
for i in range(N):
    r = events.process(["a", "b"])
    assert r == expected, f"第 {i + 1} 次执行结果错误: {r}"

size = len(events._HANDLERS)
assert size <= 2, f"注册表无限增长: {size} 个处理器（执行 {N} 次后）"

# 再执行一次，确认注册表仍不增长
before = len(events._HANDLERS)
events.process(["x"])
assert len(events._HANDLERS) == before, "注册表仍在随调用增长"
print("idempotency checks OK")
EOF
then
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS"
fi
exit "$fail"
