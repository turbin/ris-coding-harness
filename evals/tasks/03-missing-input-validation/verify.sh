#!/usr/bin/env bash
set -euo pipefail

# Mechanical verification for task 03. Runs inside the sandbox directory.
python3 - <<'PY'
import inspect
import sys
import unittest

sys.path.insert(0, ".")
import textstats
from textstats import average_word_length, longest_word, word_count

EMPTYISH = [None, "", "   ", "\t\n  \r\n"]


class TestWordCount(unittest.TestCase):
    def test_normal(self):
        self.assertEqual(word_count("hello world"), 2)
        self.assertEqual(word_count("one"), 1)
        self.assertEqual(word_count("  a  b\tc\n"), 3)

    def test_emptyish(self):
        for t in EMPTYISH:
            self.assertEqual(word_count(t), 0, f"word_count({t!r})")


class TestAverageWordLength(unittest.TestCase):
    def test_normal(self):
        self.assertAlmostEqual(average_word_length("hi there"), 3.5)
        self.assertAlmostEqual(average_word_length("a bb ccc"), 2.0)
        self.assertIsInstance(average_word_length("hello"), float)

    def test_emptyish(self):
        for t in EMPTYISH:
            self.assertEqual(average_word_length(t), 0.0,
                             f"average_word_length({t!r})")
            self.assertIsInstance(average_word_length(t), float)


class TestLongestWord(unittest.TestCase):
    def test_normal(self):
        self.assertEqual(longest_word("a bb ccc dd"), "ccc")
        self.assertEqual(longest_word("same size"), "same")  # first longest

    def test_emptyish(self):
        for t in EMPTYISH:
            self.assertEqual(longest_word(t), "", f"longest_word({t!r})")


class TestNoRaises(unittest.TestCase):
    def test_never_raises_for_str_or_none(self):
        samples = EMPTYISH + ["x", "hello world", "\u00e9\u00e9 \u00e9"]
        for t in samples:
            for fn in (word_count, average_word_length, longest_word):
                fn(t)  # must not raise


class TestSignatures(unittest.TestCase):
    def test_signatures_unchanged(self):
        for name in ("word_count", "average_word_length", "longest_word"):
            self.assertEqual(str(inspect.signature(getattr(textstats, name))),
                             "(text)")


unittest.main(verbosity=1)
PY
