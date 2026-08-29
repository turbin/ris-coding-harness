#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import sys, unittest
sys.path.insert(0, ".")
from bill import split_bill


class TestSplitBill(unittest.TestCase):
    def test_sums_exact(self):
        for total, parts in [(10.0, 3), (100.0, 7), (0.01, 2), (1.0, 3), (33.33, 5)]:
            shares = split_bill(total, parts)
            self.assertAlmostEqual(sum(shares), total, places=2)
            self.assertEqual(len(shares), parts)

    def test_max_difference(self):
        shares = split_bill(10.0, 3)
        self.assertLessEqual(max(shares) - min(shares), 0.01)

    def test_known_case(self):
        self.assertEqual(split_bill(10.0, 3), [3.34, 3.33, 3.33])

    def test_invalid_parts(self):
        for bad in (0, -1):
            with self.assertRaises(ValueError):
                split_bill(10.0, bad)


unittest.main(verbosity=1)
PY
