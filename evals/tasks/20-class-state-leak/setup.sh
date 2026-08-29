#!/usr/bin/env bash
# Creates the initial (buggy) project in $1.
set -euo pipefail
cat > "$1/stats.py" <<'PY'
"""Measurement tracker."""


class Tracker:
    _values = []  # bug: class attribute, shared across instances

    def add(self, value):
        self._values.append(value)

    def count(self):
        return len(self._values)

    def sum(self):
        return sum(self._values)

    def mean(self):
        if not self._values:
            return 0.0
        return sum(self._values) / len(self._values)
PY
cat > "$1/test_stats.py" <<'PY'
import unittest
from stats import Tracker


class TestTracker(unittest.TestCase):
    def test_basic(self):
        t = Tracker()
        t.add(1)
        t.add(2)
        self.assertEqual(t.count(), 2)
        self.assertEqual(t.sum(), 3)
        self.assertEqual(t.mean(), 1.5)

    def test_empty(self):
        self.assertEqual(Tracker().mean(), 0.0)

    def test_instances_isolated(self):
        a = Tracker()
        b = Tracker()
        a.add(10)
        self.assertEqual(a.count(), 1)
        self.assertEqual(b.count(), 0)


if __name__ == "__main__":
    unittest.main()
PY
