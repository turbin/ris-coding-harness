# Rubric: 04-feature-from-spec

Pass criteria (all mechanical, enforced by verify.sh):

- `slugify.py` exists at the project root with `slugify(text)`.
- Every example from `docs/spec.md` produces the exact specified output.
- Behavior matches a reference implementation (`lower` -> replace runs of
  non-`[a-z0-9]` with `-` -> strip hyphens) on a fuzz sample, including
  non-ASCII input.
- Output charset is `[a-z0-9-]*` with no consecutive hyphens.
- No `NotImplementedError` left behind.

This task exercises the spec-intake path: task.md contains no solution
detail, only a pointer to `docs/spec.md`.
