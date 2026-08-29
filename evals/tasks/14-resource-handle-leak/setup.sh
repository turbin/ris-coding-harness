#!/usr/bin/env bash
# Creates the initial (buggy) project in $1.
set -euo pipefail
cat > "$1/readall.py" <<'PY'
"""Concatenate file contents."""

_open_registry = []


def read_all(paths):
    parts = []
    for p in paths:
        f = open(p)
        _open_registry.append(f)
        parts.append(f.read())
    return "".join(parts)


def open_handle_count():
    return len(_open_registry)
PY
