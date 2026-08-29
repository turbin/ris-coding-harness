# Task 13: Simplify the over-engineered formatter

The sandbox contains `pricing.py`. What should be a couple of small
functions is buried under unnecessary abstraction: formatter classes, a
factory, and a registry. Behavior is correct but the design is far more
complex than the problem needs.

## Requirements

- Keep the exact public behavior: the module exposes
  `format_price(price)` -> `"$12.50"` and `format_percent(ratio)` ->
  `"62.5%"` (one decimal place, trailing `.0` kept, e.g. `"0.0%"`).
- Replace the class/factory/registry machinery with the simplest correct
  implementation (plain functions; no `class` keyword may remain in
  `pricing.py`).
- Only the Python standard library may be used.
