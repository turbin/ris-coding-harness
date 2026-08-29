# Task 12: New field breaks reading legacy records

The sandbox contains `records.py` with `serialize(record)` and
`parse(text)`. A new field `region` was added to the serialized format,
but the system must keep reading records written by the old version,
which have no `region` field.

## Requirements

- `parse` must not crash on legacy records that lack `region`; the missing
  field must default to `""`.
- `serialize` must include `region` in the output.
- Round-trip must work: `parse(serialize(r)) == r` for any record with
  `name` and `region` keys (region may be empty).
- Keep the function signatures unchanged.
- Only the Python standard library may be used.
