# rsi-loop — Gate Policy

The gate level controls **how much automation is allowed during the loop**.
It never disables human final acceptance (§4.5.5 of the design): any change
auto-merged during a run is in "trial" state until the human accepts the
batch summary; a rejection rolls back by proposal ID.

## Gate levels (call parameter, written into state.yaml)

| Level | During-loop behavior |
|---|---|
| `observe-only` | Record only, never mutate. Full loop telemetry (rounds, verdicts, retro triggers) with zero changes. Used to debug the loop itself and to measure a baseline. |
| `l1-auto` | L1 (project rules) proposals auto-apply after adversarial Review and eval-subset no-regression. L2 proposals pause and ask the human. L3 never auto. |
| `all-manual` | Every mutation — L1 included — pauses and asks the human before landing. |

Any human can raise the gate (e.g. to `all-manual`) at any time, including
mid-loop; the loop reads the gate from state each round, so raising it
takes effect next round.

## Layer table (docs/rsi-design.md §3)

| Layer | Object | Default gate |
|---|---|---|
| L1 | `docs/engineering/*.md` in the target project | Reviewer review + git commit (auto at `l1-auto`) |
| L2 | `.agents/skills/pm-workers-engineering/**` (SKILL.md + references) | Reviewer diff review + full eval no-regression + version bump (human approval at all levels) |
| L3 | `install.sh` / `install.ps1`, `rsi-loop` skill, eval scoring scripts, `docs/rsi-design.md`, `.rsi/**` | Human approval only. Never auto-mutated. |

## Protected files (hard rule, every level)

From `.rsi/policy.yaml` when present (fallback builtin list):

```yaml
protected_files:
  - ".rsi/**"
  - "evals/tasks/**"
  - "evals/run-eval.*"
  - "docs/rsi-design.md"
  - "install.sh"
  - "install.ps1"
```

The loop never touches protected files — including at `l1-auto`. The
optional pre-commit hook (`scripts/rsi-protect.sh`) enforces this at the
git layer even if an agent misbehaves.

## Change budget (per round)

- `max_files_per_mutation: 2`
- `max_diff_lines_per_mutation: 40`
- Exceeding the budget splits the change into multiple rounds.

## Mutation landing rules (all levels)

1. Proposal ID in the commit message (e.g. `P12`, `retro-2026-08-29-P12`).
2. L1 → eval subset no-regression; L2 → full eval no-regression.
3. `evals/baseline.json` updated only on no-regression.
4. Rules carry `source:` annotations (proposal/issue ID) for future hygiene
   passes (rule merging/deletion).
5. Anti-oscillation: two consecutive retros must not reverse a rule; a
   reversal escalates to the human.

## Installing the optional pre-commit hook

```bash
# in the target repository (the one running the loop)
cat > .git/hooks/pre-commit <<'EOF'
#!/bin/sh
exec "$(git rev-parse --show-toplevel)/scripts/rsi-protect.sh"
EOF
chmod +x .git/hooks/pre-commit
```

The hook exits non-zero when the staged diff touches a protected path, so
the commit is rejected.
