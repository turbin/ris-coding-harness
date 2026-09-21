# Ponytail Debt — shortcut ledger

Vendored from DietrichGebert/ponytail `skills/ponytail-debt` (MIT, upstream commit
`e3ba2aa`). Every deliberate ponytail shortcut is marked with a `ponytail:` comment
naming its ceiling and upgrade path. This collects them into one ledger so a
deferral can't quietly become permanent. One-shot report, changes nothing.

## Scan

Grep the repo for comment markers, skipping `node_modules`, `.git`, and build
output:

`grep -rnE '(#|//) ?ponytail:' .`  (add other comment prefixes if your stack uses them)

Each hit is one ledger row. The comment prefix keeps prose that merely mentions the
convention out of the ledger.

## Output

One row per marker, grouped by file:

`<file>:<line>, <what was simplified>. ceiling: <the limit named>. upgrade: <the trigger to revisit>.`

The convention is `ponytail: <ceiling>, <upgrade path>` — pull the ceiling and the
trigger straight from the comment. Want an owner per row too? add
`git blame -L<line>,<line>`.

Flag the rot risk: any `ponytail:` comment that names no upgrade path or trigger
gets a `no-trigger` tag — those are the ones that silently rot.

End with `<N> markers, <M> with no trigger.` Nothing found: `No ponytail: debt. Clean ledger.`

## Boundaries

Reads and reports only. To persist it, ask the user and write the ledger to a file
(e.g. `PONYTAIL-DEBT.md`, or the project's `issues/`/`decisions/` per its own
conventions). One-shot.
