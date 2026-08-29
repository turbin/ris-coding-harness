#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import os, sys, tempfile, unittest
sys.path.insert(0, ".")
import readall


class TestReadAll(unittest.TestCase):
    def test_read_ok(self):
        with tempfile.TemporaryDirectory() as d:
            a = os.path.join(d, "a.txt")
            b = os.path.join(d, "b.txt")
            open(a, "w").write("hello ")
            open(b, "w").write("world")
            self.assertEqual(readall.read_all([a, b]), "hello world")

    def test_registry_bounded_on_success(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "f.txt")
            open(f, "w").write("x")
            before = readall.open_handle_count()
            for _ in range(50):
                readall.read_all([f, f])
            self.assertEqual(readall.open_handle_count(), before)

    def test_registry_bounded_on_failure(self):
        with tempfile.TemporaryDirectory() as d:
            ok = os.path.join(d, "ok.txt")
            open(ok, "w").write("x")
            before = readall.open_handle_count()
            for _ in range(50):
                with self.assertRaises(FileNotFoundError):
                    readall.read_all([ok, os.path.join(d, "missing.txt")])
            self.assertEqual(readall.open_handle_count(), before)


unittest.main(verbosity=1)
PY
