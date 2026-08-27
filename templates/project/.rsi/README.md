# .rsi/ — RSI Harness Mechanism (L3)

`.rsi/` is the mechanism-layer configuration of the recursive self-improvement
(RSI) harness. It is an L3 asset: autonomous agent mutation must never modify
anything under this directory.

`policy.yaml` defines the safety boundary:

- `protected_files` — files/globs that autonomous mutation must never touch.
- `change_budget` — per-round limits on how many files and diff lines a
  mutation may change; larger proposals must be split into multiple rounds.
- `gate` — the gate level (`observe-only | l1-auto | all-manual`) controlling
  which self-modification layers may auto-apply.
- `layers` — the L1 (project rules) / L2 (collaboration protocol) / L3
  (harness mechanism) risk tiers.

Every self-improvement change must land as its own git commit whose message
carries the proposal ID, so each round can be rolled back individually.

See `docs/rsi-design.md` in the harness repository for the full design.
