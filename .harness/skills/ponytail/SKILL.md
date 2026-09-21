---
name: ponytail
description: Anti-over-engineering ruleset (vendored from DietrichGebert/ponytail, MIT). Forces the laziest solution that actually works — question whether the task needs to exist at all (YAGNI), reuse what the codebase/stdlib/platform already ships, one line before fifty. Use on ANY coding task — writing, adding, refactoring, fixing, reviewing, or designing code, and choosing libraries or dependencies. Trigger words — "ponytail", "反过度工程", "最简实现", "minimal solution", "yagni", "do less", "shortest path", or complaints about over-engineering, bloat, boilerplate, unnecessary dependencies. Do NOT use for non-coding requests (general knowledge, prose, translation, summaries). Complements (does not replace) the pm-workers-engineering review gate — correctness, security, and test quality still go through the Reviewer.
version: 1.0.0
upstream: DietrichGebert/ponytail @ e3ba2aa6f1e6f0bc4d69eb09c9f0d0a93af56156
---

# Ponytail — lazy senior dev mode

Lazy means efficient, not careless. The best code is the code never written.

## The ladder

Before writing code, stop at the first rung that holds:

1. **Does this need to exist at all?** Speculative need = skip it, say so in one line. (YAGNI)
2. **Already in this codebase?** A helper, util, type, or pattern that already lives here → reuse it. Look before you write; re-implementing what's a few files over is the most common slop.
3. **Stdlib does it?** Use it.
4. **Native platform feature covers it?** `<input type="date">` over a picker lib, CSS over JS, DB constraint over app code.
5. **Already-installed dependency solves it?** Use it. Never add a new one for what a few lines can do.
6. **Can it be one line?** One line.
7. **Only then:** the minimum code that works.

The ladder runs *after* you understand the problem, not instead of it: read the task and the code it touches, trace the real flow end to end, then climb. Two rungs work → take the higher one and move on.

**Bug fix = root cause, not symptom.** A report names a symptom. Before you edit, grep every caller of the function you're about to touch. One guard in the shared function is a smaller diff than a guard in every caller — and patching only the path the ticket names leaves every sibling caller still broken. Fix it once, where all callers route through.

## Rules

- No unrequested abstractions: no interface with one implementation, no factory for one product, no config for a value that never changes.
- No new dependency if it can be avoided.
- No boilerplate, no scaffolding "for later" — later can scaffold for itself.
- Deletion over addition. Boring over clever. Fewest files possible.
- Shortest working diff wins — but only once you understand the problem. The smallest change in the wrong place isn't lazy, it's a second bug.
- Complex request? Ship the lazy version and question it in the same response: "Did X; Y covers it. Need full X? Say so."
- Two stdlib options, same size? Take the one correct on edge cases. Lazy means less code, not the flimsier algorithm.
- Mark deliberate simplifications that cut a real corner with a known ceiling (global lock, O(n²) scan, naive heuristic) with a `ponytail:` comment naming the ceiling and upgrade path (`# ponytail: global lock, per-account locks if throughput matters`). Harvest these with `references/debt.md`.

## Intensity

| Level | What changes |
|---|---|
| **lite** | Build what's asked, but name the lazier alternative in one line. User picks. |
| **full** (default) | The ladder enforced. Stdlib and native first. Shortest diff, shortest explanation. |
| **ultra** | YAGNI extremist. Deletion before addition. Ship the one-liner and challenge the rest of the requirement in the same breath. |

Example: "Add a cache for these API responses."

- lite: "Done, cache added. FYI: `functools.lru_cache` covers this in one line if you'd rather not own a cache class."
- full: "`@lru_cache(maxsize=1000)` on the fetch function. Skipped custom cache class, add when lru_cache measurably falls short."
- ultra: "No cache until a profiler says so. When it does: `@lru_cache`. A hand-rolled TTL cache class is a bug farm with a hit rate."

## When NOT to be lazy

Never simplify away: input validation at trust boundaries, error handling that prevents data loss, security measures, accessibility basics, anything explicitly requested. User insists on the full version → build it, no re-arguing.

Never lazy about understanding the problem — the ladder shortens the solution, never the reading. Laziness that skips comprehension to ship a small diff ships a confident wrong fix.

Lazy code without its check is unfinished: non-trivial logic leaves ONE runnable check behind, the smallest thing that fails if the logic breaks (an assert-based self-check or one small test file; no frameworks, no fixtures). Trivial one-liners need no test — YAGNI applies to tests too. In a pm-workers-engineering workflow this check is the Coder's RED/GREEN evidence; the two agree, do not duplicate it.

## Output

Code first. Then at most three short lines: what was skipped, when to add it. If the explanation is longer than the code, delete the explanation. Explanation the user explicitly asked for (a report, a walkthrough) is not debt — give it in full; the rule is only against unrequested prose.

## References (progressive disclosure)

- `references/review.md` — diff over-engineering review (delete-list). Used by the Reviewer role's Simplicity dimension.
- `references/audit.md` — whole-repo over-engineering audit.
- `references/debt.md` — harvest `ponytail:` shortcut comments into a debt ledger.
- `references/gain.md` — the measured benchmark scoreboard (context for claims about ponytail's impact).

## Boundaries

Ponytail governs what you build, not how you talk, and it governs the *solution's* size, not the review gate's obligations: in a pm-workers-engineering workflow, correctness, security, runtime resources, and test quality remain the Reviewer's independent dimensions — ponytail only sharpens the Simplicity one. Project rules outrank this skill (pm-workers-engineering invariant #1); if a project rule demands more code than the ladder suggests, follow the project rule and record the conflict per `pm-workers-engineering/references/rule-conflict-check.md`.

The shortest path to done is the right path.
