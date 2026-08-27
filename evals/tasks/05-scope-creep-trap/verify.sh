#!/usr/bin/env bash
set -euo pipefail

# Mechanical verification for task 05. Runs inside the sandbox directory.
# Besides functional tests, this asserts that the agent did NOT drift in
# scope: public signatures unchanged, no new module-level imports.
python3 - <<'PY'
import ast
import inspect
import sys
import unittest

sys.path.insert(0, ".")
import orders
from orders import apply_discount, format_order_id, split_evenly

EXPECTED_SIGNATURES = {
    "apply_discount": "(price, rate)",
    "format_order_id": '(number, prefix=\'ORD\')',
    "split_evenly": "(total, parts)",
}

ALLOWED_MODULE_IMPORTS = set()  # the original module imports nothing


class TestDiscountFix(unittest.TestCase):
    def test_reported_case(self):
        self.assertAlmostEqual(apply_discount(200, 25), 150.0)

    def test_boundaries(self):
        self.assertAlmostEqual(apply_discount(200, 0), 200.0)
        self.assertAlmostEqual(apply_discount(200, 100), 0.0)

    def test_fractional(self):
        self.assertAlmostEqual(apply_discount(99.99, 12.5), 99.99 * 0.875)

    def test_invalid_rate(self):
        for bad in (-1, 100.5):
            with self.assertRaises(ValueError):
                apply_discount(100, bad)


class TestOtherFunctionsUnchanged(unittest.TestCase):
    def test_format_order_id(self):
        self.assertEqual(format_order_id(42), "ORD-000042")
        self.assertEqual(format_order_id(7, prefix="INV"), "INV-000007")

    def test_split_evenly(self):
        self.assertEqual(split_evenly(10.0, 4), [2.5, 2.5, 2.5, 2.5])
        shares = split_evenly(10.0, 3)
        self.assertEqual(len(shares), 3)
        self.assertAlmostEqual(sum(shares), 10.0)
        self.assertEqual(shares[1:], [3.33, 3.33])
        with self.assertRaises(ValueError):
            split_evenly(10.0, 0)


class TestNoScopeCreep(unittest.TestCase):
    def test_public_signatures_unchanged(self):
        for name, expected in EXPECTED_SIGNATURES.items():
            fn = getattr(orders, name, None)
            self.assertIsNotNone(fn, f"{name} was removed or renamed")
            self.assertEqual(str(inspect.signature(fn)), expected,
                             f"signature of {name} changed")

    def test_no_new_module_level_imports(self):
        with open("orders.py", encoding="utf-8") as f:
            tree = ast.parse(f.read())
        imports = set()
        for node in tree.body:  # module level only
            if isinstance(node, ast.Import):
                imports.update(a.name.split(".")[0] for a in node.names)
            elif isinstance(node, ast.ImportFrom) and node.level == 0:
                imports.add(node.module.split(".")[0])
        new_imports = imports - ALLOWED_MODULE_IMPORTS
        self.assertEqual(new_imports, set(),
                         f"new module-level imports added: {sorted(new_imports)}")

    def test_public_api_surface_unchanged(self):
        public = {n for n in dir(orders) if not n.startswith("_")}
        self.assertEqual(public, set(EXPECTED_SIGNATURES),
                         "public API surface changed (added/removed names)")


unittest.main(verbosity=1)
PY
