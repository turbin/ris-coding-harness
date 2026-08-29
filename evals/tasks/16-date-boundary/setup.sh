#!/usr/bin/env bash
# Creates the initial (buggy) project in $1.
set -euo pipefail
cat > "$1/dates.py" <<'PY'
"""Calendar-day difference helper."""

from datetime import datetime


def days_between(a, b):
    da = datetime.fromisoformat(a)
    db = datetime.fromisoformat(b)
    return (db - da).days
PY
