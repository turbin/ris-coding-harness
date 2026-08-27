#!/usr/bin/env bash
set -euo pipefail

# Mechanical verification for task 02. Runs inside the sandbox directory.
python3 - <<'PY'
import sys
import unittest

sys.path.insert(0, ".")
from cache import Cache


class TestBoundedLruCache(unittest.TestCase):
    def test_basic_get_set(self):
        c = Cache(2)
        c.set("a", 1)
        self.assertEqual(c.get("a"), 1)
        self.assertEqual(c.get("missing"), None)
        self.assertEqual(c.get("missing", 42), 42)

    def test_capacity_is_bounded(self):
        c = Cache(3)
        for i in range(1000):
            c.set(f"k{i}", i)
        self.assertLessEqual(len(c), 3)
        self.assertEqual(len(c), 3)

    def test_lru_eviction_order(self):
        c = Cache(2)
        c.set("a", 1)
        c.set("b", 2)
        c.set("c", 3)  # evicts "a" (least recently used)
        self.assertIsNone(c.get("a"))
        self.assertEqual(c.get("b"), 2)
        self.assertEqual(c.get("c"), 3)

    def test_get_refreshes_recency(self):
        c = Cache(2)
        c.set("a", 1)
        c.set("b", 2)
        c.get("a")     # "a" is now most recently used
        c.set("c", 3)  # evicts "b", not "a"
        self.assertEqual(c.get("a"), 1)
        self.assertIsNone(c.get("b"))
        self.assertEqual(c.get("c"), 3)

    def test_set_existing_key_no_eviction(self):
        c = Cache(2)
        c.set("a", 1)
        c.set("b", 2)
        c.set("a", 10)  # update, also refreshes recency of "a"
        self.assertEqual(len(c), 2)
        self.assertEqual(c.get("a"), 10)
        c.set("c", 3)   # evicts "b"
        self.assertEqual(c.get("a"), 10)
        self.assertIsNone(c.get("b"))

    def test_invalid_max_size(self):
        for bad in (0, -1, -100):
            with self.assertRaises(ValueError):
                Cache(bad)

    def test_constructor_takes_max_size(self):
        # Old unbounded API must be gone.
        with self.assertRaises(TypeError):
            Cache()

    def test_stress_bounded(self):
        c = Cache(50)
        for i in range(10000):
            c.set(i, i)
            self.assertLessEqual(len(c), 50)


unittest.main(verbosity=1)
PY
