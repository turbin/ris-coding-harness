---
name: architecture-topology
description: On-demand architecture-topology synthesis with a disk cache — module map, dependency direction, hub symbols, and key paths — for projects where graphify is disabled by the harness scale gate or has no graph. Use for architecture-level questions ("which modules", "what are the hubs", "dependency direction", "how does X reach Y") in such projects, or when asked to (re)build the topology cache (docs/architecture/topology.md). Do not use for code-level call paths or blast radius (CodeGraph), diagram syntax (mermaid-diagrams / c4-architecture), tiny single-module repos (just answer directly), or when graphify is enabled and its graph is current.
version: 1.0.0
origin: adapted from the retired user-scope skill generating-architecture-design-docs (backup ris-coding-harness tmp/replaced-skills/, retired 2026-09-23) — narrowed to topology synthesis + cache; keeps its render-validation discipline and scripts/mermaid-check.js
---

# Architecture Topology — on-demand synthesis with a disk cache

Above the harness's file-count threshold the scale gate disables graphify, so architecture-level
questions on such projects have no graph to query. This skill synthesizes the missing topology
**on demand** and caches it to disk — it is a fallback workflow, not a live index.

## Cache first

Cache file: `docs/architecture/topology.md`. Its YAML frontmatter carries the basis the cache was
built from:

```yaml
---
generated_at: 2026-09-23T12:00:00+08:00
basis:
  git_head: "<HEAD sha, or none>"
  build_files: "<sha256 of the concatenated build manifests>"
  tracked_files: 0
tool: architecture-topology v1.0.0
---
```

Freshness rule: recompute the three basis values cheaply; **any mismatch ⇒ stale ⇒ rebuild**
(§Workflow). Never answer a topology question from a stale cache without saying so.

## Workflow (bounded — never read the whole repository)

1. **Cache check** — read `docs/architecture/topology.md`; if present and fresh, answer from it and stop.
2. **Backbone (deterministic)** — parse build manifests (`pom.xml` modules/dependencies,
   `package.json` workspaces, `settings.gradle`, `go.mod`, `Cargo.toml`, `pyproject.toml`):
   module list + inter-module edges. This is the only mandatory evidence layer.
3. **Hubs & paths (bounded sampling)** — prefer CodeGraph (`impact`/`callers`) when `.codegraph/`
   exists; otherwise count inbound references per module with grep-style searches (cap: top 10
   modules by inbound references; ≤10 files read per module). Hubs = highest inbound degree.
   Paths follow backbone edges only — do not invent transitive hops.
4. **Cross-verify** — every edge and hub needs two independent sources (build file + code
   reference, or two code references). Anything single-sourced or inferred is marked `未确认`.
5. **Write the cache** — `docs/architecture/topology.md`: module table (≤40 rows; aggregate
   beyond), dependency direction, hubs, ≤5 key paths, 未确认项, then the basis frontmatter.
   `docs/architecture/` holds this generated file only — never mix it into hand-written rules
   (`docs/engineering/*`).

## Validation (before answering from a fresh cache)

- `node scripts/mermaid-check.js docs/architecture` (this skill's `scripts/`) — the structural
  check must pass.
- Render at least the main diagram with `npx -y @mermaid-js/mermaid-cli` when tools/network
  allow; otherwise say rendering was skipped.
- Spot-check ≥5 cited symbols/paths with Grep; every unverified claim stays `未确认`.

## Caps and honesty

- Caps: 40 modules, 10 hubs, 5 paths, 10 files per module. Exceeding a cap ⇒ aggregate and say so.
- A hub or edge without evidence is **not written**. `未确认` beats invention.
- State the cache age in answers ("依据 <date> 生成的拓扑缓存").

## Boundaries

- Project rules outrank this skill (pm-workers-engineering invariant #1).
- Code-level call paths and blast radius belong to CodeGraph; diagram syntax to
  `mermaid-diagrams`; C4 document conventions to `c4-architecture`. This skill only decides
  *what the topology is* and keeps a dated cache of it.
- If graphify is enabled and its graph is current, prefer graphify — this skill is the fallback
  for projects where the scale gate disabled it.
