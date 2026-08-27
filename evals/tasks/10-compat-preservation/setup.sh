#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?usage: setup.sh <target-dir>}"
mkdir -p "$TARGET"

cat > "$TARGET/textutil.py" <<'EOF'
"""文本工具。"""


def find_urls(text):
    urls = []
    for token in text.split():
        if token.startswith("http://") or token.startswith("https://"):
            urls.append(token)
    return urls
EOF

cat > "$TARGET/main.py" <<'EOF'
"""既有调用方：统计与取用文本中的 URL。"""

from textutil import find_urls


def count_urls(text):
    return len(find_urls(text))


def first_url(text):
    urls = find_urls(text)
    return urls[0] if urls else None
EOF

cat > "$TARGET/test_main.py" <<'EOF'
import unittest

from main import count_urls, first_url


class TestMain(unittest.TestCase):
    def test_count(self):
        self.assertEqual(count_urls("see http://a.com and https://b.org/x"), 2)

    def test_first(self):
        self.assertEqual(first_url("go to http://a.com now"), "http://a.com")

    def test_none(self):
        self.assertIsNone(first_url("no links here"))
        self.assertEqual(count_urls("no links here"), 0)


if __name__ == "__main__":
    unittest.main()
EOF
