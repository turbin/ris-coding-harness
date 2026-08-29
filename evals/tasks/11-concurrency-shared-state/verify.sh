#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import sys, threading, unittest
sys.path.insert(0, ".")
import seats


class TestConcurrentReserve(unittest.TestCase):
    def setUp(self):
        seats._seats.clear()  # isolate tests from shared module state

    def test_single_reservation(self):
        self.assertTrue(seats.reserve("A1"))
        self.assertFalse(seats.reserve("A1"))
        self.assertTrue(seats.is_taken("A1"))
        self.assertEqual(seats.reserved_count(), 1)

    def test_concurrent_same_seat(self):
        # Buggy code sleeps inside the check-then-act window, so interleaving
        # is guaranteed: without a lock this must fail.
        hits = []
        def worker():
            if seats.reserve("B2"):
                hits.append(1)
        threads = [threading.Thread(target=worker) for _ in range(30)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(len(hits), 1)
        self.assertEqual(seats.reserved_count(), 1)

    def test_concurrent_distinct_seats(self):
        def worker(i):
            seats.reserve(f"S{i}")
        threads = [threading.Thread(target=worker, args=(i,)) for i in range(20)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(seats.reserved_count(), 20)


unittest.main(verbosity=1)
PY
