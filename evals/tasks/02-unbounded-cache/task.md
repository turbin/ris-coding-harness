# Task 02: Unbounded cache grows forever

The sandbox contains `cache.py` with a `Cache` class used as an in-memory
key/value store. In production its memory footprint grows without bound —
profiling shows millions of entries piling up over a long-running process.

## Requirements

Change the class so that:

- The constructor takes a maximum capacity: `Cache(max_size)`.
  `max_size` must be a positive integer; raise `ValueError` otherwise.
- The number of stored entries never exceeds `max_size`.
- Eviction policy is **LRU**: when `set` is called on a full cache, the
  least recently used entry is evicted. Both `get` and `set` count as
  "use" (they refresh the entry's recency).
- `set` on an existing key updates its value and refreshes its recency
  without evicting anything.
- Keep the public API: `Cache(max_size)`, `get(key, default=None)`,
  `set(key, value)`, `len(cache)` returns the current entry count.
- Only the Python standard library may be used.
