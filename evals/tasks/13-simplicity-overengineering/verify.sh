#!/usr/bin/env bash
set -euo pipefail
fail=0
if ! python3 - <<'PY'
import sys, unittest
sys.path.insert(0, ".")
from pricing import format_percent, format_price


class TestPricing(unittest.TestCase):
    def test_price(self):
        self.assertEqual(format_price(12.5), "$12.50")
        self.assertEqual(format_price(0), "$0.00")

    def test_percent(self):
        self.assertEqual(format_percent(0.625), "62.5%")
        self.assertEqual(format_percent(0), "0.0%")
        self.assertEqual(format_percent(1), "100.0%")


unittest.main(verbosity=1)
PY
then
  echo "FAIL: unit tests" >&2
  fail=1
fi
if grep -q "^class " pricing.py; then
  echo "FAIL: class keyword must not remain in pricing.py" >&2
  fail=1
fi
exit "$fail"
