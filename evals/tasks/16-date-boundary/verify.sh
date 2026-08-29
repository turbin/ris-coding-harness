#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import sys, unittest
sys.path.insert(0, ".")
from dates import days_between


class TestDaysBetween(unittest.TestCase):
    def test_same_day(self):
        self.assertEqual(days_between("2026-01-01", "2026-01-01"), 0)

    def test_plain_dates(self):
        self.assertEqual(days_between("2026-01-01", "2026-01-03"), 2)

    def test_timestamp_alignment(self):
        self.assertEqual(days_between("2026-08-29T23:59:59", "2026-08-30T00:00:00"), 1)

    def test_year_boundary(self):
        self.assertEqual(days_between("2026-12-31T23:59:59", "2027-01-01T00:00:00"), 1)

    def test_malformed(self):
        for bad in ("nope", "", "2026-13-01"):
            with self.assertRaises(ValueError):
                days_between(bad, "2026-01-01")


unittest.main(verbosity=1)
PY
