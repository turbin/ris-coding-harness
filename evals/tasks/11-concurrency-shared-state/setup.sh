#!/usr/bin/env bash
# Creates the initial (buggy) project in $1.
set -euo pipefail
cat > "$1/seats.py" <<'PY'
"""Concurrent seat reservation."""

import time

_seats = {}


def reserve(seat_id):
    if seat_id in _seats:
        return False
    time.sleep(0.05)  # simulate work; widens the race window
    _seats[seat_id] = True
    return True


def is_taken(seat_id):
    return seat_id in _seats


def reserved_count():
    return len(_seats)
PY
