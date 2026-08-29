#!/usr/bin/env bash
# Creates the initial (buggy) project in $1.
set -euo pipefail
cat > "$1/bill.py" <<'PY'
"""Split a bill evenly."""


def split_bill(total, parts):
    if parts < 1:
        raise ValueError("parts must be >= 1")
    return [round(total / parts, 2)] * parts
PY
