# rsi-loop — Preflight Checklist

Run before the loop starts. **Any failure stops the loop**: write
`progress/loop/preflight-<timestamp>.md` listing the failed items and hand
to the human. Do not start a loop with a dirty or unverifiable base state —
the loop's mutations are only auditable when the starting point is known.

## Checklist

| # | Check | Pass condition |
|---|---|---|
| 1 | Git working tree clean | `git status --porcelain` empty (or every entry is a known, recorded artifact and the human approved starting anyway) |
| 2 | Baseline exists | `evals/baseline.json` present with a non-null `pass_rate` (`run-eval.sh check` can compare) |
| 3 | Protected-files policy present | `.rsi/policy.yaml` (or the canonical equivalent) exists with `protected_files`; when missing, fall back to the builtin list in `references/gate-policy.md` and record the fallback |
| 4 | Eval harness runnable | `./evals/run-eval.sh list` exits 0 and lists ≥1 task |
| 5 | Task queue present | `progress/loop/tasks.yaml` (or `--queue`) exists and is parseable; each entry has `task_id`, `description`, `gate_ok` |
| 6 | Tools available | `bash`, `git`, `python3` (+ `yaml` module for aggregation), and an agent CLI capable of running the PM-Workers protocol. Candidates come from `RSI_AGENT_CANDIDATES` env var or `progress/loop/agent.env` (default builtin list: pi, opencode, claude, codex, kimi); at least one candidate must be installed **and usable** (verify with a one-shot invocation, e.g. `pi -p 'reply ok'`) |
| 7 | Loop directory writable | `progress/loop/` exists (or can be created) and `state.yaml` is readable/writable |
| 8 | Gate level valid | gate is one of `observe-only` / `l1-auto` / `all-manual` (see `gate-policy.md`) |
| 9 | Results dir present | `evals/results/` exists and is writable |
| 10 | Verdicts parse & schema-valid (P4) | `python3 scripts/retro-aggregate.py --dry` style check: every `evals/results/<task>-<milestone>.yaml` parses as YAML and conforms to verdict schema v1 — run `python3 scripts/retro-aggregate.py` and require exit 0 (it aborts listing ALL invalid files) |

## Failure handling

- One file per failed preflight: `progress/loop/preflight-<ts>.md`.
- Content: timestamp, failed checks (numbers + evidence), suggested fixes.
- The loop must not start; return control to the human.
