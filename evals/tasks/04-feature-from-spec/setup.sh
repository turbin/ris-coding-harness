#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:?usage: setup.sh <target-dir>}"
mkdir -p "$TARGET/docs"

cat > "$TARGET/docs/spec.md" <<'MD'
# Spec: URL slug generation

## Module

Create a module `slugify.py` at the project root exposing one public
function:

```python
slugify(text: str) -> str
```

## Behavior

`slugify` converts arbitrary text into a URL-safe slug. The rules, applied
in this exact order:

1. If `text` is `None`, return `""`.
2. Convert to lowercase (ASCII case folding via `str.lower()`).
3. Replace every maximal run of characters that are **not** ASCII letters
   (`a-z`) or digits (`0-9`) with a single hyphen `-`.
4. Strip leading and trailing hyphens.

## Examples

| input                 | output          |
|-----------------------|-----------------|
| `"Hello World"`       | `"hello-world"` |
| `"  Foo -- Bar!! "`   | `"foo-bar"`     |
| `"already-a-slug"`    | `"already-a-slug"` |
| `"Café Über"`         | `"caf-ber"`     |
| `"123 go!"`           | `"123-go"`      |
| `""`                  | `""`            |
| `"!!!"`               | `""`            |
| `None`                | `""`            |

## Constraints

- Python standard library only (the `re` module is sufficient).
- `slugify` must not raise for any `str` or `None` input.
MD

cat > "$TARGET/slugify.py" <<'PY'
"""URL slug generation. See docs/spec.md."""


def slugify(text):
    """Convert `text` into a URL-safe slug per docs/spec.md."""
    raise NotImplementedError("not implemented yet; see docs/spec.md")
PY
