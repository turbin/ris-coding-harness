# Repository Layout Adapter

## Canonical initialized layout

When present, interpret:

- `AGENTS.md` — lightweight routing/entry document
- `src/` — source implementation
- `tests/` — tests
- `docs/` — product/technical documentation
- `docs/engineering/` — project-specific engineering rules
- `decisions/` — design/architecture decision history
- `issues/` — bug/problem history and reproduction information
- `conversations/` — user-explicit archival only
- `output/` — delivery/build/release artifacts
- `progress/` — active task/milestone state
- `scripts/` — helper automation
- `tmp/` — disposable intermediate data

Each available `index.md` is a navigation surface and should be consulted before opening many child files.

## Arbitrary repository fallback

If the canonical layout is absent, discover equivalents from repository evidence.

Examples:

- source: `lib/`, `app/`, `packages/*`, `cmd/`, `internal/`, framework-native locations
- tests: `test/`, `spec/`, colocated test files, package-local test directories
- docs/rules: `CONTRIBUTING.md`, `.github/`, `docs/`, `dev/`, `architecture/`, tool-specific agent files
- task tracking: issue tracker, project board metadata, changelog, work log, task files

Never rename or recreate structures merely to fit the canonical model.

## Toolchain discovery

Infer commands from files such as:

- `package.json`, lockfiles
- `pyproject.toml`, `requirements*`, `tox.ini`
- `Cargo.toml`
- `go.mod`
- `Makefile`, `Taskfile*`, `justfile`
- build-system files
- CI workflows

Use explicit project commands over guessed commands.
