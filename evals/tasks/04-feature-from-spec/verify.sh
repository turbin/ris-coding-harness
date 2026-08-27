#!/usr/bin/env bash
set -euo pipefail

# Mechanical verification for task 04. Runs inside the sandbox directory.
python3 - <<'PY'
import os
import re
import sys
import unittest

sys.path.insert(0, ".")
from slugify import slugify


class TestSlugifySpec(unittest.TestCase):
    def test_examples_from_spec(self):
        cases = {
            "Hello World": "hello-world",
            "  Foo -- Bar!! ": "foo-bar",
            "already-a-slug": "already-a-slug",
            "Café Über": "caf-ber",
            "123 go!": "123-go",
            "": "",
            "!!!": "",
        }
        for text, expected in cases.items():
            self.assertEqual(slugify(text), expected, f"slugify({text!r})")
        self.assertEqual(slugify(None), "")

    def test_run_collapse(self):
        self.assertEqual(slugify("a \t\n b"), "a-b")
        self.assertEqual(slugify("a___b"), "a-b")
        self.assertEqual(slugify("--x--"), "x")

    def test_reference_implementation_fuzz(self):
        ref = lambda t: "" if t is None else re.sub(
            r"[^a-z0-9]+", "-", t.lower()).strip("-")
        samples = [
            "The Quick Brown Fox!", "under_score", "MiXeD CaSe 42",
            "ümlaut ß test", "   ", "a-b-c", "9lives", "emoji \U0001F600 test",
            "many     spaces", "trailing---", "---leading",
        ]
        for t in samples:
            self.assertEqual(slugify(t), ref(t), f"slugify({t!r})")

    def test_output_charset(self):
        for t in ("Hello, World!", "Café", "a1 b2 c3"):
            out = slugify(t)
            self.assertTrue(re.fullmatch(r"[a-z0-9-]*", out),
                            f"non-slug characters in {out!r}")
            self.assertNotIn("--", out)


class TestProjectLayout(unittest.TestCase):
    def test_module_at_root(self):
        self.assertTrue(os.path.isfile("slugify.py"))


unittest.main(verbosity=1)
PY
