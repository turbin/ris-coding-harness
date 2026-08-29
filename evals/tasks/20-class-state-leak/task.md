# Task 20: Tracker instances share hidden state

The sandbox contains `stats.py` with a `Tracker` class that records
measurements and reports count/sum/mean.

Bug report: creating two `Tracker` instances mixes their data — values
added to one instance appear in the other.

## Requirements

- Fix `Tracker` so each instance has its own state: values added to one
  instance never appear in another.
- Keep the public API: `Tracker()`, `add(value)`, `count()`, `sum()`,
  `mean()` (mean of empty tracker returns `0.0`).
- `python3 -m unittest discover` must pass (tests are provided).
- Only the Python standard library may be used.
