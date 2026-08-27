# Task 01: Pagination drops the last page

The sandbox contains a small Python module `paginate.py` with a single
function:

```python
paginate(items, page_size) -> list[list]
```

It is supposed to split `items` into consecutive pages of at most
`page_size` elements, preserving order, so that every input element appears
in exactly one page.

Users report that **items from the tail of the input go missing** whenever
the list length is not handled by the loop bounds. For example,
paginating 10 items with page size 3 returns only 9 items.

## Requirements

- Fix `paginate` so that every element of the input appears in the output,
  in order, for any `page_size >= 1` and any list (including empty input
  and inputs whose length is an exact multiple of `page_size`).
- The output must not contain empty pages.
- Raise `ValueError` when `page_size < 1`.
- Keep the function name and signature unchanged.
- Only the Python standard library may be used.
