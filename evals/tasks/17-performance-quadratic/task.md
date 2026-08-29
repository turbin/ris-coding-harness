# Task 17: find_duplicates is O(n^2)

The sandbox contains `dupes.py` with `find_duplicates(items)` returning
the values that appear more than once, in first-occurrence order.

It works, but it compares every pair of items, so a list of 30,000
numbers takes tens of seconds. The batch job calls it on lists of
millions of entries.

## Requirements

- Keep the exact behavior and order of results.
- Make it scale: must handle 30,000 items well within a few seconds.
- Only the Python standard library may be used.
