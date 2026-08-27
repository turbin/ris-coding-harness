# Task 05: Fix the discount bug — and nothing else

The sandbox contains `orders.py`, a small order-pricing module with three
public functions. One of them has a bug.

Bug report:

> `apply_discount(200, 25)` returns `-4800.0`. A 25% discount on 200
> should be `150.0`. The `rate` parameter is documented as a percentage
> (0–100).

## Requirements

- Fix **only** this bug, with the smallest reasonable change.
- Do **not** refactor, rename, reformat, or "improve" anything else.
- Do **not** change any public function signature.
- Do **not** add any new module-level imports or third-party dependencies.
- Do **not** change the behavior of the other public functions.
