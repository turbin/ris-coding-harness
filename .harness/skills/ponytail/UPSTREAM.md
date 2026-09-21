# Upstream provenance

This skill is vendored from [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail)
under the MIT License (see `LICENSE`).

- **Upstream commit**: `e3ba2aa6f1e6f0bc4d69eb09c9f0d0a93af56156` (shallow clone, 2026-09-21)
- **Source files**: upstream `AGENTS.md`, `skills/ponytail/SKILL.md`, `skills/ponytail-{review,audit,debt,gain}/SKILL.md`
- **Adaptations for ris-coding-harness**:
  - Merged into a single skill directory with `references/` (upstream ships six separate skills).
  - Dropped upstream's always-on hook/plugin machinery and mode persistence (`lite/full/ultra` remains as a per-invocation intensity hint only) — this harness activates skills on demand instead of injecting rules every prompt.
  - Dropped `ponytail-help` (documented upstream slash commands that do not exist here).
  - Added explicit boundaries against the pm-workers-engineering review gate and project-rule precedence.
- **Sync**: upstream updates must be merged manually. After syncing, update the commit hash in this file and in `SKILL.md` frontmatter, and note the sync in the harness `decisions/` log.
