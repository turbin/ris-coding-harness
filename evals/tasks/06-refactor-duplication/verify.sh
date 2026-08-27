#!/usr/bin/env bash
# 用法: verify.sh [沙盒目录]  （默认当前目录；在沙盒工程根目录内运行）
set -u
SANDBOX="${1:-.}"
cd "$SANDBOX" || exit 1
fail=0

# 1) 既有测试必须全部通过（行为不变）
if ! python3 -m unittest discover -v; then
  echo "FAIL: unittest 未通过"
  fail=1
fi

# 2) 公开接口仍在
if ! grep -q "def summarize_sales" report.py || ! grep -q "def summarize_costs" report.py; then
  echo "FAIL: summarize_sales / summarize_costs 必须仍然存在"
  fail=1
fi

# 3) 机械检查：重复代码块已消除（每行核心逻辑最多出现一次）
check_once() {
  local pattern="$1" desc="$2" count
  count=$(grep -c "$pattern" report.py || true)
  if [ "$count" -gt 1 ]; then
    echo "FAIL: 重复逻辑未消除 —— '$desc' 出现 $count 次（应 <= 1）"
    fail=1
  fi
}
check_once 'total += row\["amount"\] \* row\["qty"\]' '累加表达式'
check_once 'for row in rows:' '累加循环'
check_once 'avg = total / count if count else 0' '平均值计算'

if [ "$fail" -eq 0 ]; then
  echo "PASS"
fi
exit "$fail"
