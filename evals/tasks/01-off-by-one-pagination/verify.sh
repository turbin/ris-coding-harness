#!/usr/bin/env bash
set -euo pipefail

# Mechanical verification for task 01. Runs inside the sandbox directory.
python3 - <<'PY'
import inspect
import math
import sys
import unittest

sys.path.insert(0, ".")
from paginate import paginate


class TestPaginate(unittest.TestCase):
    def test_exact_multiple(self):
        self.assertEqual(paginate([1, 2, 3, 4, 5, 6], 3), [[1, 2, 3], [4, 5, 6]])

    def test_partial_last_page(self):
        self.assertEqual(paginate([1, 2, 3, 4, 5, 6, 7], 3),
                         [[1, 2, 3], [4, 5, 6], [7]])

    def test_no_items_lost_fuzz(self):
        items = list(range(1, 101))
        for size in (1, 2, 3, 7, 9, 10, 33, 100, 101):
            pages = paginate(items, size)
            self.assertEqual([x for p in pages for x in p], items,
                             f"elements lost for page_size={size}")
            self.assertTrue(all(1 <= len(p) <= size for p in pages),
                            f"bad page sizes for page_size={size}")
            self.assertEqual(len(pages), math.ceil(len(items) / size))

    def test_empty_input(self):
        self.assertEqual(paginate([], 5), [])

    def test_single_page(self):
        self.assertEqual(paginate([1, 2], 10), [[1, 2]])

    def test_invalid_page_size(self):
        with self.assertRaises(ValueError):
            paginate([1, 2, 3], 0)

    def test_signature_unchanged(self):
        self.assertEqual(str(inspect.signature(paginate)), "(items, page_size)")


unittest.main(verbosity=1)
PY
