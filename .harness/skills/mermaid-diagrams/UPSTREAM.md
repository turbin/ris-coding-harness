# Upstream provenance

This skill is vendored from [softaworks/agent-toolkit](https://github.com/softaworks/agent-toolkit)
under the MIT License (see `LICENSE`).

- **Upstream commit**: `3027f20f3181758385a1bb8c022d4041dfb4de84` (shallow clone, 2026-09-23)
- **Source files**: upstream `skills/mermaid-diagrams/{SKILL.md,references/*.md}`
- **Adaptations for ris-coding-harness**:
  - Dropped upstream `README.md` (user-facing duplicate of `SKILL.md`; the harness ships
    agent-facing skills only).
  - Added `version` / `upstream` fields to the `SKILL.md` frontmatter (provenance only).
  - De-duplicated C4 content (2026-09-23): dropped `references/c4-diagrams.md` (410 lines
    duplicating `c4-architecture/references/c4-syntax.md`), removed C4 from the description and
    from the diagram-type guide, and left a pointer to `c4-architecture`. Content otherwise
    byte-identical to upstream.
- **Replaces**: the previously used user-scope skill `generating-architecture-design-docs`
  (retired 2026-09-23).
- **C4 ownership**: `c4-architecture` owns C4 diagrams (context / container / component /
  deployment). This skill deliberately excludes them so only one skill answers those triggers.
- **Sync**: upstream updates must be merged manually. After syncing, update the commit hash
  in this file and in the `SKILL.md` frontmatter, and note the sync in `decisions/`.
