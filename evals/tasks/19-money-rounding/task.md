# Task 19: split_bill drifts on rounding

The sandbox contains `bill.py` with `split_bill(total, parts)` used to
split a bill evenly. It rounds each share to cents with float arithmetic,
so the shares can drift and no longer sum to the original total.

## Requirements

- `split_bill(total, parts)` returns a list of `parts` floats (amounts in
  the same unit as `total`, cents precision).
- The shares must sum **exactly** to `total` (float addition of the
  returned values equals `total`).
- No share may differ from any other by more than `0.01`.
- `split_bill(10.0, 3)` must produce shares summing to `10.0`, e.g.
  `[3.34, 3.33, 3.33]`.
- `parts < 1` raises `ValueError`.
- Only the Python standard library may be used.
