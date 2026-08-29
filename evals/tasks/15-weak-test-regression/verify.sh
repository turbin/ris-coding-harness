#!/usr/bin/env bash
set -euo pipefail
fail=0
if ! python3 -m unittest discover >/dev/null 2>&1; then
  echo "FAIL: unittest" >&2
  fail=1
fi
if ! grep -q '{"a": 2, "b": 1}' test_wordfreq.py && ! grep -q '"a": 2' test_wordfreq.py; then
  echo "FAIL: test file must assert an exact frequency that catches the bug" >&2
  fail=1
fi
exit "$fail"
