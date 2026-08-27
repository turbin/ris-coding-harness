# Structured Review Verdict Schema

## Purpose

Every milestone review decision must be recorded as a machine-readable YAML verdict in addition to the natural-language review. These verdicts are the protocol's telemetry: they let evaluation and reflection steps compute acceptance rates, recurring failure patterns, TDD compliance, and change-budget signals across tasks.

## Location and lifecycle

- Write one file per milestone decision to:

  `evals/results/<task-id>-<milestone>.yaml`

- One milestone decision = one file. When a milestone is re-reviewed after fixes, overwrite the same file; `rounds` records how many adversarial round-trips it took.
- Create `evals/results/` if it does not exist. This is the protocol-required telemetry location.
- If project rules (`docs/engineering/` or equivalent) specify a different telemetry location, follow the project rules.

## Schema version

`schema_version` is currently `1`. When the schema evolves, bump the version and migrate or reinterpret older verdicts according to their recorded version.

## Field reference

Authoritative example:

```yaml
schema_version: 1
task_id: "2026-08-27-add-cache-layer"
milestone: "m1"
decision: rejected            # accepted | rejected
scores:                       # 1-5, per review rubric
  correctness: 2
  test_quality: 3
  simplicity: 4
  resource_safety: 5
  convention_fit: 4
issues:
  - severity: BLOCKER         # BLOCKER | MAJOR | MINOR | NIT
    category: correctness     # finite enum, see below
    summary: "cache grows without bound on repeated execution"
    file: "src/cache.py"
rounds: 2                     # adversarial review round-trips for this milestone
coder_red_green_evidence: true
loc_delta: {added: 120, removed: 15}
new_dependencies: 0
timestamp: "2026-08-27T10:41:00+08:00"
```

### Top-level fields

- `schema_version` (int, required) — schema version; currently `1`.
- `task_id` (string, required) — the PM-assigned task ID; used to join verdicts belonging to the same task.
- `milestone` (string, required) — milestone identifier within the task; together with `task_id` it determines the file name.
- `decision` (enum, required) — `accepted` or `rejected`. Mirrors the natural-language `MILESTONE ACCEPTED` / `MILESTONE REJECTED` decision.
- `scores` (map, required) — five fixed dimensions, each an integer from 1 (worst) to 5 (best), scored per the review rubric:
  - `correctness` — requirement satisfied, edge cases and failure paths handled.
  - `test_quality` — tests verify behavior, catch regressions, and include meaningful negative/edge cases.
  - `simplicity` — smallest correct change; no speculative abstraction or duplicate state.
  - `resource_safety` — memory/resource growth is bounded, owned, and cleaned up.
  - `convention_fit` — discovered project conventions, architecture boundaries, and patterns respected.
- `issues` (list, required; may be empty) — one entry per distinct finding:
  - `severity` (enum, required) — `BLOCKER` | `MAJOR` | `MINOR` | `NIT`, same meaning as the review output.
  - `category` (enum, required) — finite enum so failure modes aggregate across tasks:
    - `correctness` — wrong behavior, broken edge/failure paths
    - `testing` — missing, weak, or misleading tests
    - `simplicity` — unnecessary code, abstraction, or unrelated cleanup
    - `resource` — memory, lifecycle, cleanup, or growth-bound problems
    - `concurrency` — races, shared-state, or amplification problems
    - `compatibility` — API/schema/data migration or platform concerns
    - `convention` — divergence from discovered project rules/patterns
    - `scope` — out-of-scope changes or scope creep
  - `summary` (string, required) — one-line description of the finding.
  - `file` (string, optional) — primary file the issue refers to.
- `rounds` (int, required) — number of adversarial review round-trips this milestone went through, counting the decision recorded in this file.
- `coder_red_green_evidence` (bool, required) — `true` when the Coder supplied credible TDD RED evidence for this milestone; `false` when RED was skipped or the evidence is not credible.
- `loc_delta` (map, required) — `{added: <int>, removed: <int>}` net line counts for the milestone's change set.
- `new_dependencies` (int, required) — number of new third-party dependencies introduced by this milestone.
- `timestamp` (string, required) — ISO 8601 timestamp with timezone offset, recording when this decision was made.

## Downstream use

- `decision` and `rounds` → acceptance-rate and review-efficiency statistics per task and per milestone.
- `category` + `severity` → aggregation of recurring failure patterns across tasks; feeds reflection on where the team systematically fails.
- `coder_red_green_evidence` → makes "skipped TDD RED" directly countable.
- `loc_delta` and `new_dependencies` → change-budget signals; correlate size/dependency growth with review outcomes.
