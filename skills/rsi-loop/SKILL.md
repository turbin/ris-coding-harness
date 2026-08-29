---
name: rsi-loop
description: Orchestrates the recursive self-improvement loop (docs/rsi-design.md §4.5): preflight -> run task rounds -> collect verdicts -> retro -> gated mutation -> eval regression -> stop -> human final acceptance. Use when the user asks to run the RSI loop, "跑 N 轮", "observe-only 试跑", or to resume an interrupted loop from progress/loop/state.yaml.
version: 1.1.0
---

# RSI Loop Skill

## Purpose

Run the recursive self-improvement loop defined in `docs/rsi-design.md`:

```
EXECUTE -> SENSE -> EVALUATE -> REFLECT -> MUTATE -> GATE -> (loop)
```

The orchestrator (this skill's host agent) is **deliberately thin**: it
preflights, takes tasks from the queue, spawns a cold-start sub-agent per
round, collects verdicts, judges retro triggers, and writes state files.
It never executes task details in its own context — that is what sub-agents
are for, and it is what keeps the loop from exhausting its own context.

The skill is **stateless**: all loop state lives in files under
`progress/loop/`. Any agent (or the user) can resume an interrupted loop by
reading `progress/loop/state.yaml`.

## Core invariants

1. Orchestrator is thin; every round spawns a cold-start sub-agent.
2. All state lives in files: `progress/loop/state.yaml` + `progress/loop/round-<n>.yaml`.
3. Preflight must pass before the loop starts (see `references/preflight.md`).
4. Stop conditions are hardcoded and checked every round (see `references/stop-conditions.md`).
5. Human final acceptance is mandatory and cannot be configured off.
   Anything auto-merged during the loop is in "trial" state until the human
   accepts the batch report; a rejection reverts by proposal ID.
6. The gate level is a call parameter written into state; it only controls
   automation during the loop, never the final human acceptance.
7. Protected files are never touched, even at `l1-auto` (see `references/gate-policy.md`).

## Invocation

```
invoke rsi-loop --gate <observe-only|l1-auto|all-manual> --rounds <N>
                [--queue <tasks.yaml>] [--resume]
```

- `--gate` (required) — gate level for this loop run, written to state.
- `--rounds` (default 5) — number of task rounds to run.
- `--queue` (default `progress/loop/tasks.yaml`) — task queue file.
- `--resume` — continue from `progress/loop/state.yaml` instead of starting fresh.

## Loop procedure

1. **Preflight** — run the checklist in `references/preflight.md`. Any
   failure: write `progress/loop/preflight-<ts>.md`, stop, hand to human.
2. **State** — create or read `progress/loop/state.yaml` (see
   `progress/loop/state.yaml.example`).
3. **Round loop** (repeat up to `--rounds`):
   a. Take the next task from the queue (or stop when the queue is empty).
   b. Spawn a cold-start sub-agent for the task: hand it the PM-Workers
      protocol (`.agents/skills/pm-workers-engineering/SKILL.md`), the task
      description, and the gate level. The orchestrator does not work the
      task itself. Capture the sub-agent's execution trace into
      `progress/loop/traces/round-<n>-<task-id>.<agent>` (P6; see
      `references/round-protocol.md` SPAWN step) — a round without a trace
      is invalid.
   c. Collect the sub-agent's results: structured verdict
      (`evals/results/<task-id>-<milestone>.yaml`), issues, diff stats,
      trace file.
   d. Write `progress/loop/round-<n>.yaml` (see `round.yaml.example`),
      including `trace_file`.
   e. Update `state.yaml` counters and cumulative metrics.
   f. Judge retro triggers (per `docs/rsi-design.md` §4.3: N tasks done /
      ≥3 BLOCKER+MAJOR in one category / eval drop). If triggered, run a
      retro per `progress/retro/README.md` (orchestrator writes the report;
      proposals are **proposals only** — no direct file edits).
   g. If the gate allows mutation and the human approves where required,
      land proposals via `decisions/` flow: each mutation is one git commit
      whose message references the proposal ID, then eval regression per
      gate level, update `evals/baseline.json` only on no-regression.
   h. Check stop conditions (see `references/stop-conditions.md`); if any
      trip, stop immediately and write an incident report.
4. **Human final acceptance** — after the requested rounds (or an abnormal
   stop), write the batch summary report: task results, eval score change,
   full mutation list with diff summaries, and stop for human acceptance.
   Nothing is considered final until the human accepts; rejection rolls back
   by proposal ID (`git revert` per commit).

## Reference documents

- `references/preflight.md` — preflight checklist
- `references/round-protocol.md` — single-round flow in detail
- `references/gate-policy.md` — gate levels, layer table, protected files
- `references/stop-conditions.md` — hardcoded stop conditions

## Optional shells (for cron/CI)

- `run-loop.sh` — thin wrapper: builds the invocation prompt and hands it to
  an agent CLI (`RSI_AGENT_CMD`). Interactive users just ask the agent
  directly; the script is for unattended scheduling.
- `scripts/rsi-protect.sh` — optional git pre-commit hook that hard-blocks
  staged changes to protected files, even if an agent misbehaves.

## Definition of "done" for a loop run

- requested rounds completed or queue exhausted;
- state files written for every round;
- retro reports (when triggered) produced with proposals, no direct edits;
- mutations landed only under the active gate and human confirmation rules;
- eval regression checked with results on file;
- batch summary report written and handed to the human;
- final status in the summary: `ACCEPTED` (human approved) or
  `REJECTED-ROLLED-BACK` (human rejected, reverted by proposal ID).
