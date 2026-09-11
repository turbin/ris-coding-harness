# Testing Rules

Document the project's test strategy and executable commands.

Include when known:
- test frameworks;
- unit/integration/e2e boundaries;
- TDD expectations;
- regression-test policy;
- test file placement;
- exact commands for targeted and full verification.

## Current testing rules

### RED evidence before behavior changes (source: retro-2026-08-28-P1)

Any behavior change — bug fix, new feature, contract adjustment — must show
RED evidence before implementation:

1. Write a failing test or a minimal reproduction script that demonstrates
   the missing/broken behavior.
2. Record its failure output (red), then implement (green).
3. Refactors that preserve behavior do not need RED, but must start from a
   GREEN baseline (the suite passes before the refactor).

### Boundary input checklist first (source: retro-2026-08-28-P3)

Before implementing or modifying a function that takes input, enumerate the
boundary cases and cover each one: `None`, empty string, whitespace-only
string, zero, negative, out-of-range values, exact multiples/capacity
limits, repeated invocation. Every boundary must either have a test or be
explicitly handled (and justified) in code.
