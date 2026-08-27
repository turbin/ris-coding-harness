#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: setup.sh <target-dir>}"
mkdir -p "$TARGET"

cat > "$TARGET/cache.py" <<'PY'
"""In-memory key/value cache."""


class Cache:
    """Simple cache backed by a dict."""

    def __init__(self):
        self._data = {}

    def get(self, key, default=None):
        return self._data.get(key, default)

    def set(self, key, value):
        self._data[key] = value

    def __len__(self):
        return len(self._data)
PY
