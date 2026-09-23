# Upstream provenance

This skill is vendored from [softaworks/agent-toolkit](https://github.com/softaworks/agent-toolkit)
under the MIT License (see `LICENSE`).

- **Upstream commit**: `3027f20f3181758385a1bb8c022d4041dfb4de84` (shallow clone, 2026-09-23)
- **Source files**: upstream `skills/c4-architecture/{SKILL.md,references/*.md}`
- **Adaptations for ris-coding-harness**:
  - Dropped upstream `README.md` (user-facing duplicate of `SKILL.md`; the harness ships
    agent-facing skills only).
  - Added `version` / `upstream` fields to the `SKILL.md` frontmatter (provenance only).
  - Content otherwise byte-identical to upstream: no output-path or validation changes yet.
- **Replaces**: the previously used user-scope skill `generating-architecture-design-docs`
  (retired 2026-09-23). The installer never shipped a diagram/architecture skill before,
  so this is an addition on the harness side and a replacement on the user side.
- **Known pending adaptations** (deliberately not applied — upstream fidelity first):
  - Upstream hardcodes output to `docs/architecture/c4-*.md`. Projects on the harness layout
    keep architecture rules in `docs/engineering/architecture.md` and have no
    `docs/architecture/` convention, so the skill's output location needs mapping to the
    project's existing architecture-doc location.
  - Validation is manual upstream ("check in Mermaid Live"); there is no structural or
    real-render check step, while the retired skill shipped a `mermaid-check.js`.
- **C4 ownership**: this skill is the single owner of C4 diagrams. `mermaid-diagrams` dropped its
  `references/c4-diagrams.md` and its C4 triggers on 2026-09-23, so the two no longer compete
  (see `decisions/2026-09-23-diagram-skills-vendoring.md`).
- **Sync**: upstream updates must be merged manually. After syncing, update the commit hash
  in this file and in the `SKILL.md` frontmatter, and note the sync in `decisions/`.
