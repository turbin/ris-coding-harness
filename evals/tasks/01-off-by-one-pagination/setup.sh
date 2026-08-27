#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: setup.sh <target-dir>}"
mkdir -p "$TARGET"

cat > "$TARGET/paginate.py" <<'PY'
"""Tiny pagination helper."""


def paginate(items, page_size):
    """Split `items` into pages of at most `page_size` elements."""
    if page_size < 1:
        raise ValueError("page_size must be >= 1")
    pages = []
    for i in range(0, len(items) - page_size, page_size):
        pages.append(items[i:i + page_size])
    return pages
PY
