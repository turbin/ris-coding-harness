# Task 14: File handles accumulate on failure paths

The sandbox contains `readall.py` with `read_all(paths)`. It opens every
file and keeps a reference to each handle in a module-level registry "for
tracing". In production the registry grows without bound: every call
(including calls that hit a missing path and raise) adds handles that are
never closed.

## Requirements

- `read_all(paths)` returns the concatenated file contents in order.
- When a path does not exist, it raises `FileNotFoundError` — and the
  handles opened before the failure must be closed (no leak).
- The module-level registry must stay bounded: its size must not grow with
  repeated calls, whether they succeed or fail.
- Keep the public API: `read_all(paths)`.
- Only the Python standard library may be used.
