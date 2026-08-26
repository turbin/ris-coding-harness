# Progressive Context Disclosure

This reference defines how the team controls repository-context growth.

## Principle

Context should expand because a decision requires it, not because a file exists.

## Initial pass

Inspect only shallow repository structure and the root instruction/routing file. Avoid recursive reads of `docs/`, `src/`, `tests/`, generated files, dependencies, vendor trees, and build outputs.

## Routing pass

Use `AGENTS.md`, `index.md`, manifests, and module maps to identify the smallest relevant context set.

## Role-aware loading

### PM normally needs
- root rule router;
- engineering rule index;
- task/progress state;
- high-level module/index information;
- relevant decisions/issues only when they constrain scope.

### Coder normally needs
- task definition;
- relevant engineering rules;
- affected source module;
- matching tests;
- one or two similar patterns when needed.

### Reviewer normally needs
- acceptance criteria;
- relevant engineering rules;
- diff/change set;
- changed tests and directly affected behavior;
- supporting architecture/decision docs only when the change touches them.

## Expansion triggers

Expand context only when:
- repository patterns conflict;
- task boundaries are unclear;
- a build/test failure cannot be explained locally;
- an API/data boundary is crossed;
- a historical decision materially constrains the change;
- memory/lifecycle ownership is unclear;
- reviewer requests evidence.

## Contraction

After a milestone, carry forward summaries, decisions, task state, and exact file pointers rather than reloading all raw context.
