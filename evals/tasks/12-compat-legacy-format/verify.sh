#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import sys, unittest
sys.path.insert(0, ".")
from records import parse, serialize

LEGACY = '{"name": "alice"}'


class TestCompat(unittest.TestCase):
    def test_legacy_parse(self):
        self.assertEqual(parse(LEGACY), {"name": "alice", "region": ""})

    def test_round_trip(self):
        for r in ({"name": "bob", "region": "cn"},
                  {"name": "carol", "region": ""}):
            self.assertEqual(parse(serialize(r)), r)

    def test_new_format_has_region(self):
        self.assertIn('"region"', serialize({"name": "dave", "region": "us"}))


unittest.main(verbosity=1)
PY
