# Task 16: days_between is off by one on timestamps

The sandbox contains `dates.py` with `days_between(a, b)` returning the
number of whole days from `a` to `b` (inclusive of `a`, exclusive of
`b`).

The inputs may be plain dates (`"2026-08-29"`) or full ISO timestamps
(`"2026-08-29T23:59:59"`). The current implementation parses the whole
string, so timestamps are misaligned and the count is off by one:
`days_between("2026-08-29T23:59:59", "2026-08-30T00:00:00")` returns
`0` but must return `1` (the two instants are on different calendar days).

## Requirements

- `days_between(a, b)` must count **calendar-day** differences: both
  inputs are truncated to their date part before comparing.
- `days_between("2026-01-01", "2026-01-01")` -> `0`
- `days_between("2026-01-01", "2026-01-03")` -> `2`
- `days_between("2026-08-29T23:59:59", "2026-08-30T00:00:00")` -> `1`
- `days_between("2026-12-31T23:59:59", "2027-01-01T00:00:00")` -> `1`
- Raise `ValueError` for malformed input.
- Only the Python standard library may be used.
