#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: setup.sh <target-dir>}"
mkdir -p "$TARGET"

cat > "$TARGET/textstats.py" <<'PY'
"""Small text statistics helpers."""


def word_count(text):
    """Return the number of whitespace-separated words in `text`."""
    return len(text.split())


def average_word_length(text):
    """Return the mean character length of the words in `text`."""
    words = text.split()
    return sum(len(w) for w in words) / len(words)


def longest_word(text):
    """Return the (first) longest word in `text`."""
    return max(text.split(), key=len)
PY
