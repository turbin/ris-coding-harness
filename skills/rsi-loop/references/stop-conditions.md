# rsi-loop — Stop Conditions

Hardcoded conditions, checked **after every round** (and before the loop
starts via preflight). If any condition trips, the loop stops immediately:
write `progress/loop/incident-<timestamp>.md` with the condition, evidence,
and current state, then return control to the human. No further mutation
happens after a stop.

## Hard stops

| # | Condition | Evidence to record |
|---|---|---|
| 1 | Eval regression: `pass@1` after a mutation is below `evals/baseline.json` `pass_rate` | `run-eval.sh check` output; results file path |
| 2 | Consecutive task failures: 3 rounds in a row with `decision: rejected` or missing verdict | round files 3..n-1, verdict status |
| 3 | Git state pollution: uncommitted changes to protected files, or a mutation commit that cannot be reverted cleanly | `git status --porcelain`, `git log` |
| 4 | Preflight failure at start (see `preflight.md`) | preflight report path |
| 5 | Human interruption: user sets `pause: true` in `state.yaml`, or the loop is asked to stop | state file, user request |
| 6 | Queue exhausted with rounds remaining — this is a **normal stop** (not an incident): report and go to human acceptance | queue file |
| 7 | Any L3 file changed by the loop (defense in depth; should be impossible if pre-commit hook is installed) | `git diff` on the protected path |

## After a stop

1. Write `progress/loop/incident-<ts>.md` (or, for normal stops, proceed to
   the batch summary) with:
   - timestamp and round number;
   - the condition that fired and the evidence;
   - cumulative loop metrics from `state.yaml`;
   - recommendations (fix, gate raise, revert list).
2. Produce the batch summary report (task results, eval score change,
   mutation list with diff summaries) and stop for **human final
   acceptance** — this is never skippable, even on incident stops.
3. On human rejection: roll back by proposal ID — one `git revert` per
   mutation commit, in reverse order.
