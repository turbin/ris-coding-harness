# Task 11: Concurrent reservation is not thread-safe

The sandbox contains `seats.py` with `reserve(seat_id)` used by a booking
service. Under concurrent load the same seat is reserved by multiple
requests.

## Requirements

- Fix `reserve` so that each seat can be reserved by exactly one caller,
  even when many threads call `reserve` concurrently with the same seat.
- `reserve(seat_id)` returns `True` when the seat was not taken before and
  `False` when it is already taken.
- The public API must stay: `reserve(seat_id)`, `is_taken(seat_id)`,
  `reserved_count()`.
- Only the Python standard library may be used.
