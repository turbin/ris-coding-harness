# Task 15: The test passes for the wrong reasons

The sandbox contains `wordfreq.py` (`count_words(text)` -> dict of word ->
count, case-insensitive) and `test_wordfreq.py`. The existing test only
checks that the function returns a dict and doesn't raise — it would pass
even if the counting were completely wrong.

The module has a real bug: `count_words("a a b")` returns
`{"a": 1, "b": 1}` instead of `{"a": 2, "b": 1}`.

## Requirements

- Fix the bug in `wordfreq.py`.
- Strengthen `test_wordfreq.py` so the suite would **fail on the original
  buggy code**: add at least one assertion on an exact frequency (e.g.
  `{"a": 2, "b": 1}` for `"a a b"`).
- `python3 -m unittest discover` must pass.
- Only the Python standard library may be used.
