# Origin

Derived from the user-scope skill `generating-architecture-design-docs`
(retired 2026-09-23; backup: harness repo `tmp/replaced-skills/generating-architecture-design-docs/`).
This is homegrown content, not a vendor copy — there is no upstream LICENSE.

Kept from the original:
- evidence-first recon (build manifests as the dependency backbone);
- bounded per-module sampling and cross-verification (two independent sources per claim);
- `未确认` markers for anything unverified;
- `scripts/mermaid-check.js` (unchanged, 95 lines) and the "render before claiming done" discipline.

Narrowed:
- the doc-set output (index + one file per module with sequence diagrams) is replaced by a single
  topology cache (`docs/architecture/topology.md`) with a machine-checkable freshness basis;
- the cost drivers (one subagent per module, full-repo sweeps) are capped (§Caps and honesty).

Added:
- cache-first routing and the freshness rule (git head + build-file digests + tracked-file count);
- the graphify / scale-gate boundary (this skill is the fallback where the gate disabled graphify).
