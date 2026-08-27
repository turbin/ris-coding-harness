# Rubric: 02-unbounded-cache

Pass criteria (all mechanical, enforced by verify.sh):

- `Cache(max_size)` constructor with `ValueError` for non-positive sizes;
  the old zero-argument constructor must no longer work.
- Entry count never exceeds `max_size`, including under 10k inserts.
- True LRU semantics: `get` and `set` both refresh recency; evicting a
  full cache removes the least recently used entry; updating an existing
  key does not evict.
- `get` supports the `default` parameter.

Implementation note: `collections.OrderedDict` (stdlib) is the natural
solution, but any correct implementation passes.
