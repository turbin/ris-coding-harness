# rsi-loop — Round Protocol

One round = one task, executed by a cold-start sub-agent, with results
recorded by the orchestrator. The orchestrator never performs the task
itself (context isolation; identical guarantees to a shell-per-round model).

## Single-round flow

```
1. TAKE      pop next task from the queue (progress/loop/tasks.yaml)
2. SPAWN     cold-start sub-agent with:
             - PM-Workers skill path (role protocol)
             - task description (from queue entry)
             - task context: where the sandbox/worktree lives
             - gate level (from state.yaml) — the sub-agent must know
               whether mutation is allowed this round
3. COLLECT   from the sub-agent's report:
             - structured verdict (evals/results/<task-id>-<milestone>.yaml)
             - issues recorded (issues/ or project tracker)
             - diff stats (changed files, added/removed lines, deps)
             - RED evidence status (verdict field)
4. RECORD    write progress/loop/round-<n>.yaml (see round.yaml.example)
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
8. STOP?     check stop conditions (stop-conditions.md); if tripped, write
             incident report and end the loop immediately.
```

## Queue entry schema (progress/loop/tasks.yaml)

```yaml
- task_id: "2026-08-29-eval-01"
  description: "evals/tasks/01-off-by-one-pagination/task.md (hand to sub-agent)"
  workdir: "evals/sandbox/01-off-by-one-pagination"
  gate_ok: true          # task may be mutated by the sub-agent
```

## Verdict contract with the sub-agent

The sub-agent must return (per `pm-workers-engineering`):

- `MILESTONE ACCEPTED` / `MILESTONE REJECTED` decision;
- structured verdict written to `evals/results/<task-id>-<milestone>.yaml`
  (schema v1, see `skills/pm-workers-engineering/references/verdict-schema.md`);
- every problem discovered but not fixed recorded in `issues/`;
- issue closure verified before acceptance (fixed with evidence or
  explicitly deferred).

The orchestrator validates the verdict file exists and is schema-conformant
before recording the round; missing verdict = round failed.

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
mutations: []            # proposal IDs applied this round (empty in observe-only)
eval_after: "results/eval-<ts>.json (pass@1 x/y)"   # when eval was re-run
timestamp: "2026-08-29T08:00:00+08:00"
```
