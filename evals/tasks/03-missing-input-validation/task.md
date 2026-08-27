# Task 03: Crashes on empty / None input

The sandbox contains `textstats.py`, a small text statistics helper used
by a batch job. The job crashes at 3 a.m. whenever it hits a record with
missing or empty text.

Current behavior (bad):

- `word_count(None)` raises `TypeError`.
- `word_count("")` works, but `average_word_length("")` and
  `average_word_length("   ")` raise `ZeroDivisionError`.
- `longest_word(None)` / `longest_word("")` raise.

## Requirements

Make all three functions handle `None`, empty, and whitespace-only input
gracefully, with this exact contract:

| call                        | result |
|-----------------------------|--------|
| `word_count(None)`          | `0`    |
| `word_count("")`            | `0`    |
| `average_word_length(None)` | `0.0`  |
| `average_word_length("")`   | `0.0`  |
| `longest_word(None)`        | `""`   |
| `longest_word("")`          | `""`   |

Whitespace-only strings behave the same as empty strings. None of the
three functions may raise for any `str` or `None` input.

Behavior for normal non-empty text must stay as today:

- words are separated by runs of whitespace (`str.split()` semantics);
- `word_count` returns the number of words;
- `average_word_length` returns a `float`, the mean character length of
  the words;
- `longest_word` returns the first longest word.

Keep function names and signatures unchanged. Standard library only.
