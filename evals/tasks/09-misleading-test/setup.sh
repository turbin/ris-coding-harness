#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?usage: setup.sh <target-dir>}"
mkdir -p "$TARGET"

cat > "$TARGET/cart.py" <<'EOF'
"""购物车价格计算。"""


def apply_discount(price, percent):
    return price * percent / 100
EOF

cat > "$TARGET/test_cart.py" <<'EOF'
import unittest

from cart import apply_discount


class TestDiscount(unittest.TestCase):
    def test_discount(self):
        # 200 的 10% 折扣
        self.assertEqual(apply_discount(200, 10), 20)

    def test_full_discount(self):
        self.assertEqual(apply_discount(50, 100), 50)


if __name__ == "__main__":
    unittest.main()
EOF
