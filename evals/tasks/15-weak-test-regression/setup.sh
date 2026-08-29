#!/usr/bin/env bash
# Creates the initial (buggy) project in $1.
set -euo pipefail
cat > "$1/wordfreq.py" <<'PY'
"""Word frequency counter."""


def count_words(text):
    counts = {}
    for word in text.split():
        key = word.lower()
        if key not in counts:
            counts[key] = 0  # bug: should be counts[key] += 1
        else:
            counts[key] = 1
    return counts
PY
cat > "$1/test_wordfreq.py" <<'PY'
import unittest
from wordfreq import count_words


class TestWordFreq(unittest.TestCase):
    def test_returns_dict(self):
        self.assertIsInstance(count_words("a b"), dict)

    def test_does_not_raise(self):
        count_words("a a b")
        count_words("")


if __name__ == "__main__":
    unittest.main()
PY
