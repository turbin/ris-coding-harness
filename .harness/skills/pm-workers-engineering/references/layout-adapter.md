# Repository Layout Adapter

## Canonical initialized layout

When present, interpret:

- `AGENTS.md` — lightweight routing/entry document
- `src/` — source implementation
- `tests/` — tests
- `docs/` — product/technical documentation
- `.harness/docs/engineering/` — project-specific engineering rules
- `.harness/decisions/` — design/architecture decision history
- `.harness/issues/` — bug/problem history and reproduction information
- `.harness/conversations/` — user-explicit archival only
- `output/` — delivery/build/release artifacts
- `.harness/progress/` — active task/milestone state
- `scripts/` — helper automation
- `tmp/` — disposable intermediate data

Layout v2 (2026-09-30) keeps every installer-managed record directory under
`.harness/`; pre-v2 projects have the same four directories (`decisions/`,
`issues/`, `progress/`, `conversations/`) at the repository root instead.

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
