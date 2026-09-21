# Ponytail Gain — measured impact scoreboard

Vendored from DietrichGebert/ponytail `skills/ponytail-gain` (MIT, upstream commit
`e3ba2aa`). One-shot display of the published benchmark medians. Do NOT change any
mode, write flag files, or persist anything.

The figures below are the published benchmark medians, measured on a headless
agent editing a real FastAPI + React repo (12 feature tasks, n=4, Haiku 4.5),
against the same agent with no skill:

| vs no-skill baseline | LOC | tokens | cost | time | safe |
|---|---|---|---|---|---|
| ponytail | -54% mean (up to -94%) | -22% | -20% | -27% | 100% |

The single-shot (isolated generation) benchmark reported 80–94% less LOC across
five everyday tasks and three models; the agentic numbers above are the corrected,
defensible version. Source: upstream `benchmarks/` and README.

## Honesty boundary

These are benchmark medians, not this repo. NEVER print a per-repo savings number
("you saved X lines/tokens here"): the unbuilt version was never written, so there
is no real baseline to subtract from in a live repo. The only real per-repo figures
come from `debt.md` (a counted ledger).

## Boundaries

One-shot display. Edits nothing, changes no mode.
