#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import subprocess, sys, unittest
sys.path.insert(0, ".")
from dupes import find_duplicates


class TestDuplicates(unittest.TestCase):
    def test_order_and_dupes(self):
        self.assertEqual(find_duplicates([1, 2, 1, 3, 2, 1]), [1, 2])
        self.assertEqual(find_duplicates([1, 2, 3]), [])
        self.assertEqual(find_duplicates(["a", "b", "a", "c", "a"]), ["a"])
        self.assertEqual(find_duplicates([]), [])

    def test_scales(self):
        # Data is generated inside the subprocess (argv is size-limited).
        # 100k items: O(n^2) takes ~30s+, an O(n) implementation < 1s.
        code = (
            "import sys; sys.path.insert(0, '.'); "
            "from dupes import find_duplicates; "
            "items = list(range(100000)) + [0]; "
            "print(find_duplicates(items)[:1])"
        )
        r = subprocess.run([sys.executable, "-c", code], capture_output=True,
                           text=True, timeout=6)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("0", r.stdout)


unittest.main(verbosity=1)
PY
