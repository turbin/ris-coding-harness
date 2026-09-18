# rsi-loop — Round Protocol

One round = one task, executed by a cold-start sub-agent, with results
recorded by the orchestrator. The orchestrator never performs the task
itself (context isolation; identical guarantees to a shell-per-round model).

## Single-round flow

```
1. TAKE      pop next task from the queue (progress/loop/tasks.yaml).
             Validate the entry carries a `budget` (schema below): a queue
             entry without `budget.tokens` is NOT dispatched — list every
             offending entry and stop with an error (same severity as a
             missing verdict/trace; fix the queue, never guess budgets).
2. SPAWN     cold-start sub-agent with:
             - PM-Workers skill path (role protocol)
             - task description (from queue entry)
             - task context: where the sandbox/worktree lives
             - gate level (from state.yaml) — the sub-agent must know
               whether mutation is allowed this round
             - trace capture (P6): save the sub-agent's full execution trace
               to `progress/loop/traces/round-<n>-<task-id>.<agent>`
               (pi: `--session-dir progress/loop/traces/` or copy the session
               file after the run; kimi: copy `~/.kimi/sessions/<id>/`;
               others: save the equivalent session store, or tee the output
               stream to `round-<n>-<task-id>.log`). A round without a trace
               is INVALID — same severity as a missing verdict.
             - SPAWN infra failure (CLI crash, timeout, no session produced)
               is NOT a task failure: retry the spawn ONCE. A retried spawn
               that also fails is recorded as a normal failed round with
               `infra_failure: true` in round-<n>.yaml; it counts toward
               stop-condition #2 like any missing-verdict round. Never retry
               more than once — infra retries must not become an unbounded loop.
3. COLLECT   from the sub-agent's report:
             - structured verdict (evals/results/<task-id>-<milestone>.yaml)
             - issues recorded (issues/ or project tracker)
             - diff stats (changed files, added/removed lines, deps)
             - RED evidence status (verdict field)
             - session usage: run `python3 scripts/trace-usage.py` on the
               captured trace (budget telemetry is orchestrator-measured,
               never sub-agent self-reported; see Budget enforcement)
4. RECORD    write progress/loop/round-<n>.yaml (see round.yaml.example),
             including `trace_file` referencing the captured trace and the
             budget fields (`budget`, `token_usage`, `total_tokens`,
             `cost_usd`, `cost_source`, `budget_exceeded`)
5. UPDATE    state.yaml: rounds_done++, counters (accepted/rejected,
             issues by category, eval results), queue position
6. RETRO?    judge triggers (docs/rsi-design.md §4.3):
             - N tasks completed since last retro (suggested N=5), or
             - same category BLOCKER+MAJOR count >= 3, or
             - eval score dropped vs baseline
             When triggered: run retro (progress/retro/README.md). Retro
             produces proposals only — no direct file edits.
7. MUTATE?   per gate level (gate-policy.md):
             - observe-only: never
             - l1-auto: L1 proposals auto-apply after Review + eval subset
               no-regression; L2 stops for human approval
             - all-manual: every proposal stops for human approval
             Every mutation = one git commit, message references proposal ID
             (e.g. "feat: apply P12 (retro-2026-08-29)"). Update
             evals/baseline.json only when eval shows no regression.
             Conflict check (rule-conflict-check.md) runs BEFORE any apply:
             every proposal carries a conflict_check section; duplicate /
             wording conflicts may be auto-merged but still pass the gates
             above; directional / cross-layer / oscillation conflicts pause
             the proposal for user arbitration, ruling recorded in
             decisions/. L1P platform cards are drafted only — never
             committed.
8. STOP?     check stop conditions (stop-conditions.md); if tripped, write
             incident report and end the loop immediately.
```

## Queue entry schema (progress/loop/tasks.yaml)

```yaml
- task_id: "2026-08-29-eval-01"
  description: "evals/tasks/01-off-by-one-pagination/task.md (hand to sub-agent)"
  workdir: "evals/sandbox/01-off-by-one-pagination"
  gate_ok: true          # task may be mutated by the sub-agent
  budget:                # REQUIRED; a task without a budget is not dispatched
    tokens: 200000       # total session tokens (input incl. cache + output + reasoning)
    cost_usd: 0.50       # optional; checked only when both actual cost and budget are known
```

## Verdict contract with the sub-agent

The sub-agent must return (per `pm-workers-engineering`):

- `MILESTONE ACCEPTED` / `MILESTONE REJECTED` decision;
- structured verdict written to `evals/results/<task-id>-<milestone>.yaml`
  (schema v1, see `skills/pm-workers-engineering/references/verdict-schema.md`)
  with `origin: protocol` (P5, retro-2026-08-29) — required for every
  sub-agent round so protocol telemetry never mixes with manual bookkeeping;
- every problem discovered but not fixed recorded in `issues/`;
- issue closure verified before acceptance (fixed with evidence or
  explicitly deferred).

The orchestrator validates the verdict file exists and is schema-conformant
before recording the round; missing verdict = round failed. The round's
execution trace must exist under `progress/loop/traces/` and be referenced
by `trace_file` in the round report; missing trace = round failed (P6,
retro-2026-08-29) — verdicts without traces cannot be audited, and real
project tasks have no machine judge to substitute for the trace.

## Budget enforcement (docs/rsi-design.md §4.8)

Every dispatched task carries a `budget` (queue entry). After each round
the orchestrator — never the sub-agent — extracts actual session usage
from the captured trace with `scripts/trace-usage.py` and records it in
the round report:

- `budget_exceeded: true` when `total_tokens` > `budget.tokens` (or, when
  both actual and budgeted cost are known, `cost_usd` > `budget.cost_usd`);
- traces without usable usage data record `total_tokens: unknown` and
  `budget_exceeded: null` — the round stays valid and the gap stays visible;
- enforcement follows `budget.enforce` in `.harness/.rsi/policy.yaml`:
  `strict` feeds the stop conditions (see `stop-conditions.md` #8/#9);
  `record` keeps telemetry only;
- cumulative usage accumulates in `state.yaml` counters (`tokens_total`,
  `cost_usd_total`, `budget_exceeded_rounds`) and feeds retro aggregation
  (`scripts/retro-aggregate.py --rounds-dir`).

## Round report (progress/loop/round-<n>.yaml)

```yaml
round: 3
task_id: "2026-08-29-eval-01"
gate: l1-auto
decision: accepted
verdict_file: "evals/results/2026-08-29-eval-01-m1.yaml"
scores: {correctness: 5, test_quality: 4, simplicity: 5, resource_safety: 5, convention_fit: 4}
issues: []
rounds: 1
coder_red_green_evidence: true
loc_delta: {added: 12, removed: 3}
budget: {tokens: 200000, cost_usd: 0.50}   # from the queue entry
token_usage: {input: 16399, output: 18229, cache_read: 400640, cache_write: 0, reasoning: 11546}
total_tokens: 435268                        # "unknown" when the trace has no usage data
cost_usd: 0.008522                          # null when not computable
cost_source: native                         # native | pricing | none
budget_exceeded: false                      # null when total_tokens is unknown
trace_file: "traces/round-1-example-task-01.pi.jsonl"   # required (P6)
mutations: []            # proposal IDs applied this round (empty in observe-only)
eval_after: "results/eval-<ts>.json (pass@1 x/y)"   # when eval was re-run
timestamp: "2026-08-29T08:00:00+08:00"
```
