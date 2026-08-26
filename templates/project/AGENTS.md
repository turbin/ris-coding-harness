# Project Agent Entry

This file is the lightweight routing entry for agents working in this repository.
Do not load the entire repository or all documentation up front.

## Engineering workflow skill

For software-engineering tasks, use:

`.agents/skills/pm-workers-engineering/SKILL.md`

Load role-specific references only when the corresponding role is active.

## Project-specific engineering rules

Start with:

`docs/engineering/index.md`

That index tells you which project-specific rules to load for the current task. Read only the relevant rule files.

## Repository routing

When present, use each directory's `index.md` before reading many child files.

- `src/` — source implementation
- `tests/` — tests
- `docs/` — design and technical documentation
- `docs/engineering/` — project-specific engineering rules
- `decisions/` — architecture and technical decisions
- `issues/` — defects, problems, and reproduction records
- `conversations/` — conversations saved only when explicitly requested by the user
- `output/` — build, release, and delivery artifacts
- `progress/` — active task and milestone state
- `scripts/` — helper automation
- `tmp/` — disposable intermediate artifacts

If the repository uses a different native layout, follow that layout instead of forcing these directories.

## Context loading order

1. Read this file.
2. Read `docs/engineering/index.md` when present.
3. Load only task-relevant engineering rules.
4. Read affected module/index files.
5. Read only the source, tests, decisions, issues, or progress records needed for the current decision.
6. Expand context only when local evidence is insufficient.

## Safety and change discipline

- Preserve existing project conventions.
- Prefer the smallest correct change.
- Do not invent framework, build, test, Git, or style rules that the repository does not define.
- Do not overwrite existing project files unless explicitly instructed.
