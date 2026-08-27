# Project Onboarding: Infrastructure Discovery

This reference defines how the team establishes a project's infrastructure baseline — toolchain, test frameworks, and exact runnable commands — before or during the first engineering task.

The output of onboarding is written to the project's engineering rules (`docs/engineering/tooling.md`, `docs/engineering/testing.md`, and related rule files), never kept only in conversation.

## When onboarding triggers

Trigger onboarding when both conditions hold:

1. the current task requires building, testing, linting, or running the project; and
2. the relevant rule files are missing, or still contain their template placeholders (e.g. `<!-- Add exact build command(s). -->`), or the needed commands cannot be determined from them.

Do not run onboarding for tasks that do not touch the toolchain (pure documentation edits, rule-only changes).

## Two modes

### Existing repository (adopted) — scan, then confirm

Evidence exists; discover it, do not ask the user to restate what the repository already shows.

Scan, in order:

1. package/build manifests (`package.json` scripts, `pyproject.toml`, `go.mod`, `Cargo.toml`, `Makefile`, `justfile`, `Taskfile`, build.gradle, etc.);
2. CI configuration (`.github/workflows/`, `.gitlab-ci.yml`, etc.) — CI commands are the most authoritative statement of how the project is verified;
3. test configuration and existing test directories (framework, naming, placement);
4. `README*` / `CONTRIBUTING*` setup and verification sections.

Then:

- draft the concrete entries for `docs/engineering/tooling.md` and `docs/engineering/testing.md` from that evidence (exact commands only — no invented commands);
- mark anything found in evidence as-is; mark anything not discoverable as `UNKNOWN — needs user input`;
- present the draft to the user for confirmation before writing, listing every `UNKNOWN` item as an explicit question.

### New repository (initialized, empty) — ask, then record

There is no evidence to scan. Do not guess a stack.

1. Recommend a minimal mainstream toolchain and test framework appropriate to the project's stated purpose, with one-line rationale each.
2. Ask the user to confirm or adjust: language/runtime, package manager, build command, test framework and command, lint/format tooling.
3. Write the confirmed choices into `docs/engineering/tooling.md` and `docs/engineering/testing.md`.
4. Record significant toolchain choices and their rationale in `decisions/` (per project rules), so later reflection can distinguish "chosen" from "accidental".

## Hard rule: never guess commands

An agent must never invent a build/test/lint command that is not backed by rule files or repository evidence. If neither source yields the command the current step needs, stop and ask the user (see the stop conditions in `SKILL.md`). A wrong guessed command wastes a full RED-GREEN cycle and pollutes verdict telemetry with infrastructure noise.

## Specs reference, never duplicate

Task specs and plans must reference the rule files for infrastructure ("run the test command from `docs/engineering/tooling.md`"), not restate commands. A spec only carries infrastructure content when the task itself adds or changes tooling — and then the change must be reflected back into the rule files as part of the task's Definition of Done.
