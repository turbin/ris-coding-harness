# Platform Knowledge Cards (L1P)

## Purpose

Some lessons are true only on one platform: Windows path/line-ending/encoding
quirks, PowerShell vs bash differences, driver/toolchain version traps, and
platform-specific dependency constraints. These are recorded as **platform
knowledge cards** — a dedicated sub-layer of the rules (L1P) — instead of
generic project rules, so they never pollute other platforms' rule context.

Key property: **cards are never auto-committed.** The reflection loop may
draft them, but a human reviews and commits them. Cards carry export metadata
so they can later be synced to an external knowledge base (e.g. Open Viking).

## When to write a card

- a retro pattern attributes to a platform-specific mechanism (the
  `platform-specific` cause in the retro protocol — see
  `progress/retro/README.md` and the rsi-loop round step 6);
- a task hits a platform-specific problem whose fix generalizes beyond this
  repository;
- a discovered dependency constraint holds only on one platform.

Do not write a card for platform-independent lessons — those belong in the
regular L1 rules.

## Location and format

One card per file:

```text
docs/engineering/platform/<platform>/<slug>.md
e.g. docs/engineering/platform/windows/crlf-breaks-bash-scripts.md
```

Card body:

```markdown
---
platform: windows            # lowercase: windows | linux | macos | wsl | ...
scope: shell | filesystem | encoding | dependency | toolchain | driver | display | other
source: "<proposal/issue/task id>"
date: 2026-09-10
export_ready: true           # future knowledge-base sync picks up export_ready cards
---

## <symptom-first title>

- Symptom: <what is observed, with the exact error/output>
- Root cause: <why, in one or two lines>
- Fix: <exact commands/paths/settings>
- Applies when: <versions/editions/constraints; when NOT to apply>
```

`docs/engineering/platform/index.md` lists the cards and routes loading.

## Loading rule

Load a card only when the current runtime matches its `platform` frontmatter
and the task touches its `scope`. Never inject all cards into context.

## Commit and export policy

- The loop may create or edit cards in the working tree, but MUST NOT
  `git add` or `git commit` them. Pending cards are listed in the round/task
  report as "awaiting human commit".
- Uncommitted changes under `docs/engineering/platform/` are expected state,
  not workspace pollution (loop preflight and reviewers treat them
  accordingly).
- Conflict resolution inside L1P follows `rule-conflict-check.md`, but even
  "auto-mergeable" outcomes stay uncommitted until a human commits.
- Cards are excluded from eval gating (the eval set does not span platform
  matrices); quality gates are Reviewer review + human commit.
- Export (reserved, not scheduled): a sync step reads `export_ready: true`
  cards and pushes them to the configured knowledge base
  (`.rsi/policy.yaml` → `platform_knowledge.export.targets`, e.g.
  Open Viking). Until a target is configured, export is a no-op.
