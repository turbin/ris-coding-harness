# Rule Conflict Check — Synchronous Consistency Gate for Writeback

## Purpose

Every mutation proposal (from retro or elsewhere) must be checked against
existing engineering rules **before** it is applied — the rsi-loop
round-protocol runs this gate at the MUTATE step, after retro produces
proposals and before any file change. Generating a constraint and checking it
for conflicts are one synchronous step. Outcomes split into auto-resolvable
(still gated) and human-arbitration.

## When it runs

1. **Synchronous (mandatory)** — for every proposal, before approval and
   before any file change. Scope: the full target file plus every other rule
   file governing the same concern (same topic across `docs/engineering/`).
2. **Periodic** — during every retro, sweep all of `docs/engineering/` for
   contradictions between existing rules, not only the new proposals.

## Conflict classes and disposition

| Class | Example | Disposition |
|---|---|---|
| Duplicate / redundant | new rule restates an existing rule | **Auto-optimizable**: merge or delete-old-keep-new, preserve `source:` chains; then normal gates. |
| Wording conflict | same direction, different thresholds/scopes ("cache ≤ 100 entries" vs "cache ≤ 1000") | **Auto-optimizable**: unify wording/threshold with justification; then normal gates. |
| Directional conflict | opposite instructions ("always X" vs "never X") | **Not auto-resolvable**: pause the proposal, present both rule texts plus evidence to the user, wait for arbitration. Record the ruling in `decisions/`. |
| Cross-layer conflict | proposal contradicts an L2 protocol rule, or would require touching L3 | **Not auto-resolvable**: escalate like directional; L3 changes are human-initiated only. |
| Oscillation | the same file received opposite-direction changes in two consecutive retros | **Not auto-resolvable**: mandatory user arbitration; the newer change is held (or reverted) until ruled. |

## Auto-resolution is still gated

"Auto-optimizable" never bypasses gates:

- L1 changes still follow the gate level (`gate-policy.md`) — review, eval
  subset no-regression under `l1-auto`, human approval under `all-manual`.
- L1P platform cards have **no auto-commit at all**; even auto-mergeable
  conflict resolutions stay uncommitted until a human commits (see
  `platform-knowledge.md`).

## Required output in the proposal

Every proposal document must contain a conflict-check section:

```yaml
conflict_check:
  status: no-conflict | auto-mergeable | needs-user-arbitration
  scanned: [docs/engineering/coding.md, docs/engineering/performance.md]
  findings:
    - rule: "coding.md#bounded-caches"
      relation: duplicate | wording | directional | cross-layer | oscillation
      disposition: merged into new text | unified threshold to <X> | escalated to user
```

A proposal without this section is invalid and must not be applied.

## Escalation record

When the user arbitrates, record in `decisions/`: both conflicting texts, the
evidence, the ruling, and the resulting rule text. The losing text is deleted
or amended in the same change that records the decision (L1), or flagged in
the pending platform card (L1P).
