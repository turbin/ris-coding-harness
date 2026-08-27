#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?usage: setup.sh <target-dir>}"
mkdir -p "$TARGET"

cat > "$TARGET/report.py" <<'EOF'
"""Sales/cost reporting helpers."""


def summarize_sales(rows):
    total = 0
    for row in rows:
        total += row["amount"] * row["qty"]
    count = len(rows)
    avg = total / count if count else 0
    return {"label": "sales", "total": total, "count": count, "avg": avg}


def summarize_costs(rows):
    total = 0
    for row in rows:
        total += row["amount"] * row["qty"]
    count = len(rows)
    avg = total / count if count else 0
    return {"label": "costs", "total": total, "count": count, "avg": avg}
EOF

cat > "$TARGET/test_report.py" <<'EOF'
import unittest

from report import summarize_sales, summarize_costs

ROWS = [
    {"amount": 10, "qty": 2},
    {"amount": 5, "qty": 4},
]


class TestSummarize(unittest.TestCase):
    def test_sales(self):
        self.assertEqual(
            summarize_sales(ROWS),
            {"label": "sales", "total": 40, "count": 2, "avg": 20},
        )

    def test_costs(self):
        self.assertEqual(
            summarize_costs(ROWS),
            {"label": "costs", "total": 40, "count": 2, "avg": 20},
        )

    def test_empty(self):
        self.assertEqual(
            summarize_sales([]),
            {"label": "sales", "total": 0, "count": 0, "avg": 0},
        )
        self.assertEqual(
            summarize_costs([]),
            {"label": "costs", "total": 0, "count": 0, "avg": 0},
        )


if __name__ == "__main__":
    unittest.main()
EOF
