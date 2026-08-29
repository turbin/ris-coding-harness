#!/usr/bin/env bash
# Creates the initial (buggy/slow) project in $1.
set -euo pipefail
cat > "$1/dupes.py" <<'PY'
"""Duplicate finder."""


def find_duplicates(items):
    result = []
    for i, item in enumerate(items):
        if item in items[i + 1:] and item not in result:
            result.append(item)
    return result
PY
