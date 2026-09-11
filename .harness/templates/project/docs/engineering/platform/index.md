# Platform Knowledge Cards (L1P)

Platform-specific lessons (OS quirks, toolchain/driver version traps, dependency
constraints that hold only on one platform) live here as one card per file:

`<platform>/<slug>.md` — e.g. `windows/crlf-breaks-bash-scripts.md`

Cards are drafted by the RSI reflection loop but **never auto-committed**: a human
reviews and commits them, and may later export them to an external knowledge base
(see `.harness/.rsi/policy.yaml` → `platform_knowledge.export.targets`).

## Loading rule

Load a card only when the current runtime matches its `platform` frontmatter and
the task touches its `scope`. Do not read all cards.

## Cards

| Platform | Cards |
|---|---|
| (none yet) | — |

Format, commit policy, and export metadata: see the pm-workers-engineering skill
reference `platform-knowledge.md`.
