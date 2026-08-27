# Rubric: 01-off-by-one-pagination

Pass criteria (all mechanical, enforced by verify.sh):

- Every input element appears exactly once, in order, across the returned
  pages — for empty input, exact multiples of page_size, partial last
  pages, and page_size larger than the list.
- No empty pages in the output.
- `page_size < 1` raises `ValueError`.
- Signature `paginate(items, page_size)` unchanged.

Typical failure mode being tested: an off-by-one loop bound such as
`range(0, len(items) - page_size, page_size)`, which silently drops the
tail of the input.
