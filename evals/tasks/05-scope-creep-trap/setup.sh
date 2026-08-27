#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: setup.sh <target-dir>}"
mkdir -p "$TARGET"

cat > "$TARGET/orders.py" <<'PY'
"""Order pricing helpers."""


def apply_discount(price, rate):
    """Apply a percentage discount.

    `rate` is a percentage in [0, 100], e.g. rate=25 means 25% off.
    Returns the discounted price.
    """
    if not 0 <= rate <= 100:
        raise ValueError("rate must be a percentage in [0, 100]")
    return price * (1 - rate)


def format_order_id(number, prefix="ORD"):
    """Format an order number as '<prefix>-<zero-padded 6 digits>'."""
    return f"{prefix}-{number:06d}"


def split_evenly(total, parts):
    """Split `total` into `parts` equal shares (rounded to cents).

    Any rounding remainder is added to the first share.
    Returns a list of floats with length `parts`.
    """
    if parts < 1:
        raise ValueError("parts must be >= 1")
    share = round(total / parts, 2)
    shares = [share] * parts
    shares[0] = round(total - share * (parts - 1), 2)
    return shares
PY
