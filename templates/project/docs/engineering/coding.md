# Coding Rules

Document implementation conventions discovered from the project.

Possible topics:
- languages and supported versions;
- formatter/linter rules;
- naming and error-handling conventions;
- async/concurrency patterns;
- preferred existing helpers or patterns;
- forbidden or discouraged abstractions.

## Current coding rules

### Verify API assumptions before calling (source: retro-2026-08-28-P2)

Before calling a standard-library or third-party API, verify its existence
and signature with a minimal probe (`help()`, `dir()`, official docs, or a
one-line REPL expression). Do not call from memory. In particular, check
method ownership (e.g. `dict.move_to_end` does not exist; it belongs to
`OrderedDict`) and guard semantics before relying on them.
