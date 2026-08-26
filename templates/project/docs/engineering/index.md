# Engineering Rules Index

This directory contains project-specific engineering rules. Keep this file short: it is a router, not a full handbook.

Load only the files needed for the current task.

| Task concern | Read |
|---|---|
| Project invariants / product constraints | `project.md` |
| Module boundaries / architecture / APIs | `architecture.md` |
| Implementation style / language conventions | `coding.md` |
| Tests / TDD / test commands / coverage | `testing.md` |
| Memory / performance / concurrency / lifecycle | `performance.md` |
| Branch / commit / review rules | `git.md` |
| Build / lint / dev / release commands | `tooling.md` |

## Rule precedence

1. Explicit user instruction for the current task.
2. Repository-local rules and existing implementation evidence.
3. PM-Workers skill defaults.

If rules conflict or are incomplete, do not invent a convention. Record the ambiguity and escalate to PM when it materially affects implementation.
