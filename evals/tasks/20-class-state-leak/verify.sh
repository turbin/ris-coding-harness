#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import sys, unittest
sys.path.insert(0, ".")
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

    def test_many_instances(self):
        trackers = [Tracker() for _ in range(10)]
        for i, t in enumerate(trackers):
            t.add(i)
        for i, t in enumerate(trackers):
            self.assertEqual(t.sum(), i)


unittest.main(verbosity=1)
PY
