# Rubric: 03-missing-input-validation

Pass criteria (all mechanical, enforced by verify.sh):

- All three functions accept `None`, `""`, and whitespace-only strings
  without raising, returning the contract values from task.md
  (`0` / `0.0` / `""`).
- `average_word_length` returns a `float` even for empty input.
- Normal behavior unchanged (split on whitespace runs, first longest word
  wins ties).
- Signatures unchanged: `(text)`.

Typical failure mode being tested: no input validation — `None.split()`
raises `TypeError`, empty input raises `ZeroDivisionError` /
`ValueError`.
