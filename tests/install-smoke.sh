#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/new" "$TMP/existing"
printf '%s\n' '{"name":"existing-demo"}' > "$TMP/existing/package.json"

"$ROOT/install.sh" --target "$TMP/new" --mode auto --no-git >/dev/null
"$ROOT/install.sh" --target "$TMP/existing" --mode auto --no-git >/dev/null

# Empty project should receive canonical init layout under .harness/.
test -f "$TMP/new/AGENTS.md"
test -f "$TMP/new/CLAUDE.md"
grep -qF '<!-- ris-coding-harness:begin -->' "$TMP/new/AGENTS.md"
grep -qF '<!-- ris-coding-harness:begin -->' "$TMP/new/CLAUDE.md"
test -f "$TMP/new/src/index.md"
test -f "$TMP/new/tests/index.md"
test -f "$TMP/new/docs/engineering/index.md"
test -f "$TMP/new/docs/engineering/platform/index.md"
test -f "$TMP/new/.harness/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/new/.harness/skills/rsi-loop/SKILL.md"
test -f "$TMP/new/.harness/skills/rsi-loop/references/preflight.md"
test -f "$TMP/new/.harness/.rsi/policy.yaml"
test -f "$TMP/new/.harness/manifest.json"
grep -q '"schema_version"' "$TMP/new/.harness/manifest.json"
grep -q '"sha256"' "$TMP/new/.harness/manifest.json"
test -d "$TMP/new/evals/results"

# Search routing (default --search zvec): managed AGENTS section carries the
# zvec-first fuzzy-search routing block.
grep -q 'zvec is the default fuzzy-search layer' "$TMP/new/AGENTS.md"

# Existing project should be adopted without canonical source/test directories.
test -f "$TMP/existing/AGENTS.md"
test -f "$TMP/existing/docs/engineering/index.md"
test -f "$TMP/existing/.harness/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/existing/.harness/skills/rsi-loop/SKILL.md"
test ! -e "$TMP/existing/src"
test ! -e "$TMP/existing/tests"
test -f "$TMP/existing/package.json"

# An existing AGENTS.md is merged: user content kept, managed section appended,
# and a re-run refreshes the section without duplicating it.
printf '# our own rules\ndo not touch\n' > "$TMP/existing/AGENTS.md"
"$ROOT/install.sh" --target "$TMP/existing" --mode adopt --no-git >/dev/null
grep -q 'do not touch' "$TMP/existing/AGENTS.md"
grep -qF '<!-- ris-coding-harness:begin -->' "$TMP/existing/AGENTS.md"
"$ROOT/install.sh" --target "$TMP/existing" --mode adopt --no-git >/dev/null
[ "$(grep -c 'ris-coding-harness:begin' "$TMP/existing/AGENTS.md")" -eq 1 ]
grep -q 'do not touch' "$TMP/existing/AGENTS.md"

# Re-running must be non-destructive without --force.
printf '%s\n' '# local customization' > "$TMP/existing/docs/engineering/coding.md"
"$ROOT/install.sh" --target "$TMP/existing" --mode adopt --no-git >/dev/null
grep -q '^# local customization$' "$TMP/existing/docs/engineering/coding.md"

# --agent distributes the skill to each requested agent directory (plus canonical .harness).
mkdir -p "$TMP/multi"
"$ROOT/install.sh" --target "$TMP/multi" --mode auto --no-git --agent claude,opencode,codex >/dev/null
test -f "$TMP/multi/.harness/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/multi/.harness/skills/rsi-loop/SKILL.md"
test -f "$TMP/multi/.claude/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/multi/.claude/skills/rsi-loop/SKILL.md"
test -f "$TMP/multi/.opencode/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/multi/.codex/skills/pm-workers-engineering/SKILL.md"

# Repeated --agent flags accumulate; uppercase and empty segments tolerated.
mkdir -p "$TMP/repeat"
"$ROOT/install.sh" --target "$TMP/repeat" --mode auto --no-git --agent claude --agent PI >/dev/null
test -f "$TMP/repeat/.pi/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/repeat/.claude/skills/pm-workers-engineering/SKILL.md"

# Unknown agent names must fail before anything is written.
if "$ROOT/install.sh" --target "$TMP/bad" --mode auto --no-git --agent foo 2>/dev/null; then
  echo "install smoke test: FAIL (unknown agent accepted)" >&2
  exit 1
fi
test ! -e "$TMP/bad/AGENTS.md"

# --check on an absent target must report missing skills, exit 1, and write nothing.
CHECK_ABSENT="$TMP/check-absent"
if out="$("$ROOT/install.sh" --target "$CHECK_ABSENT" --check 2>&1)"; then
  echo "install smoke test: FAIL (--check passed on absent target)" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q 'missing'
test ! -e "$CHECK_ABSENT"

# --check passes once the skills are installed, and covers policy + managed section.
out="$("$ROOT/install.sh" --target "$TMP/new" --check 2>&1)"
printf '%s\n' "$out" | grep -q 'ok         .harness/.rsi/policy.yaml'
printf '%s\n' "$out" | grep -q 'AGENTS.md managed section'

# --check --agent flags a destination that was never installed.
if out="$("$ROOT/install.sh" --target "$TMP/new" --check --agent claude 2>&1)"; then
  echo "install smoke test: FAIL (--check missed absent claude dest)" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q '.claude/skills'

# An incomplete skill (SKILL.md deleted) is detected, then healed by re-running
# the installer without destroying local customizations.
rm "$TMP/existing/.harness/skills/rsi-loop/SKILL.md"
if out="$("$ROOT/install.sh" --target "$TMP/existing" --check 2>&1)"; then
  echo "install smoke test: FAIL (--check missed incomplete skill)" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q 'incomplete'
"$ROOT/install.sh" --target "$TMP/existing" --mode adopt --no-git >/dev/null
"$ROOT/install.sh" --target "$TMP/existing" --check >/dev/null
grep -q '^# local customization$' "$TMP/existing/docs/engineering/coding.md"

# --check and --no-skill are mutually exclusive.
if "$ROOT/install.sh" --target "$TMP/new" --check --no-skill >/dev/null 2>&1; then
  echo "install smoke test: FAIL (--check accepted with --no-skill)" >&2
  exit 1
fi

# Exit code contract: missing option values must exit 2.
rc=0; "$ROOT/install.sh" --target >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "install smoke test: FAIL (--target missing value exits $rc, want 2)" >&2; exit 1; }
rc=0; "$ROOT/install.sh" --agent >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "install smoke test: FAIL (--agent missing value exits $rc, want 2)" >&2; exit 1; }

# --scope user installs agent skills under $HOME (project stays untouched except canonical).
FAKEHOME="$TMP/fakehome"; mkdir -p "$FAKEHOME" "$TMP/userproj"
HOME="$FAKEHOME" "$ROOT/install.sh" --target "$TMP/userproj" --mode adopt --no-git --scope user --agent claude >/dev/null
test -f "$FAKEHOME/.claude/skills/pm-workers-engineering/SKILL.md"
test ! -e "$TMP/userproj/.claude"

# Env bootstrap: dry-run records the setup-env command but must not execute it.
mkdir -p "$TMP/envtest/scripts"
printf '#!/usr/bin/env bash\ntouch .setup-marker\n' > "$TMP/envtest/scripts/setup-env.sh"
"$ROOT/install.sh" --target "$TMP/envtest" --mode adopt --no-git --dry-run-env >/dev/null
test -f "$TMP/envtest/.harness/reports/env-report.md"
grep -q '\[dry-run\] setup-env' "$TMP/envtest/.harness/reports/env-report.md"
test ! -e "$TMP/envtest/.setup-marker"

# Env bootstrap: a failing setup-env warns by default (exit 0, report says failed).
printf '#!/usr/bin/env bash\nexit 7\n' > "$TMP/envtest/scripts/setup-env.sh"
"$ROOT/install.sh" --target "$TMP/envtest" --mode adopt --no-git >/dev/null
grep -q 'result: failed' "$TMP/envtest/.harness/reports/env-report.md"

# Env bootstrap: --strict-env upgrades failure to exit code 3.
rc=0; "$ROOT/install.sh" --target "$TMP/envtest" --mode adopt --no-git --strict-env >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ] || { echo "install smoke test: FAIL (--strict-env exits $rc, want 3)" >&2; exit 1; }

# Env bootstrap: --skip-env writes no env report (.harness/ itself is owned by
# the mechanism layer: skills, policy, manifest).
mkdir -p "$TMP/envskip"
"$ROOT/install.sh" --target "$TMP/envskip" --mode adopt --no-git --skip-env >/dev/null
test ! -e "$TMP/envskip/.harness/reports"

# Env bootstrap: successful run reports ok.
mkdir -p "$TMP/envok/scripts"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/envok/scripts/setup-env.sh"
"$ROOT/install.sh" --target "$TMP/envok" --mode adopt --no-git >/dev/null
grep -q 'result: ok' "$TMP/envok/.harness/reports/env-report.md"

# Env bootstrap: fresh install without manifests records an ok report.
grep -q 'result: ok' "$TMP/new/.harness/reports/env-report.md" || {
  echo "install smoke test: FAIL (env report missing after fresh install)" >&2
  exit 1
}
# .gitignore template parity: Thumbs.db present.
grep -q 'Thumbs.db' "$TMP/new/.gitignore"
# .gitignore template ignores the local zvec index store.
grep -q '.zvec-grep/' "$TMP/new/.gitignore"

# Env bootstrap mentions zvec, and no eager index is built at install time
# (indexing is deferred to the first fuzzy search per the routing section).
grep -q 'zvec' "$TMP/new/.harness/reports/env-report.md"
test ! -e "$TMP/new/.zvec-grep"

# --search off: managed section and env report stay zvec-free.
mkdir -p "$TMP/searchoff"
if ! "$ROOT/install.sh" --target "$TMP/searchoff" --mode adopt --no-git --search off >/dev/null; then
  echo "install smoke test: FAIL (--search off rejected)" >&2
  exit 1
fi
grep -qF '<!-- ris-coding-harness:begin -->' "$TMP/searchoff/AGENTS.md"
if grep -q 'zvec is the default fuzzy-search layer' "$TMP/searchoff/AGENTS.md"; then
  echo "install smoke test: FAIL (--search off still injects routing)" >&2
  exit 1
fi
if grep -q 'zvec' "$TMP/searchoff/.harness/reports/env-report.md"; then
  echo "install smoke test: FAIL (--search off still touches env report)" >&2
  exit 1
fi

# Invalid --search value exits 2.
rc=0; "$ROOT/install.sh" --target "$TMP/sbad" --mode adopt --no-git --search bogus >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "install smoke test: FAIL (--search bogus exits $rc, want 2)" >&2; exit 1; }

# Legacy layout is reported but does not fail a complete installation.
mkdir -p "$TMP/new/.agents/skills" "$TMP/new/.rsi"
if out="$("$ROOT/install.sh" --target "$TMP/new" --check 2>&1)"; then
  printf '%s\n' "$out" | grep -q 'legacy'
else
  echo "install smoke test: FAIL (legacy leftovers failed a complete install)" >&2
  exit 1
fi

# Legacy-only project: everything missing -> exit 1 with legacy report.
mkdir -p "$TMP/legacyonly/.agents/skills" "$TMP/legacyonly/.rsi"
if out="$("$ROOT/install.sh" --target "$TMP/legacyonly" --check 2>&1)"; then
  echo "install smoke test: FAIL (legacy-only project passed check)" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q 'legacy'

# Legacy migration: files identical to the managed source move into .harness/;
# customized files stay in place and are reported.
mkdir -p "$TMP/migproj/.agents/skills/rsi-loop/references" "$TMP/migproj/.rsi"
printf 'customized by hand\n' > "$TMP/migproj/.agents/skills/rsi-loop/references/stop-conditions.md"
printf 'customized policy\n' > "$TMP/migproj/.rsi/policy.yaml"
cp "$ROOT/.harness/skills/rsi-loop/references/gate-policy.md" "$TMP/migproj/.agents/skills/rsi-loop/references/gate-policy.md"
out="$("$ROOT/install.sh" --target "$TMP/migproj" --mode adopt --no-git 2>&1)"
test ! -e "$TMP/migproj/.agents/skills/rsi-loop/references/gate-policy.md"
test -f "$TMP/migproj/.agents/skills/rsi-loop/references/stop-conditions.md"
test -f "$TMP/migproj/.harness/skills/rsi-loop/references/stop-conditions.md"
test -f "$TMP/migproj/.harness/.rsi/policy.yaml"
test -f "$TMP/migproj/.rsi/policy.yaml"
printf '%s\n' "$out" | grep -q 'left in place'

# Regression (issues/2026-09-19-remote-install-sed-pipe): build_agents_section
# must survive a repair hint containing '|' (the remote curl|bash form).
# Exercises the real function bodies extracted from install.sh, with a stubbed
# print_repair_hint; before the fix the sed substitution aborted the install.
SECT_SRC="$(awk '/^print_repair_hint\(\)/,/^}/' "$ROOT/install.sh"; awk '/^build_agents_section\(\)/,/^}/' "$ROOT/install.sh")"
if ! out="$(
  BEGIN_MARK='<!-- ris-coding-harness:begin -->'
  END_MARK='<!-- ris-coding-harness:end -->'
  eval "$SECT_SRC"
  print_repair_hint() { printf '%s\n' 'Repair: curl -fsSL https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.sh | bash -s -- --target "/tmp/demo" --mode adopt --agent kimi'; }
  build_agents_section
)"; then
  echo "install smoke test: FAIL (build_agents_section broke on a '|' repair hint)" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q 'bash -s -- --target'
printf '%s\n' "$out" | grep -qF '<!-- ris-coding-harness:begin -->'
if printf '%s\n' "$out" | grep -qE '@(REPAIR|BEGIN|END)@'; then
  echo "install smoke test: FAIL (placeholders left in agents section)" >&2
  exit 1
fi

# The local-form repair hint must land in the installed AGENTS.md.
grep -q -- '--mode adopt' "$TMP/new/AGENTS.md"

# Anti-nesting guard: a bare relative --target that does not exist, run from
# an empty (or already harness-managed) directory, is refused with guidance —
# the README examples read exactly that way when copied from inside the new
# project directory.
NEST="$TMP/nestcwd"
mkdir -p "$NEST"
rc=0; nest_out="$( cd "$NEST" && "$ROOT/install.sh" --target my-project --mode auto --no-git 2>&1 )" || rc=$?
[ "$rc" -eq 2 ] || { echo "install smoke test: FAIL (anti-nesting guard rc=$rc, want 2)" >&2; exit 1; }
printf '%s\n' "$nest_out" | grep -q -- '--target \.'
[ ! -e "$NEST/my-project" ]

# Escape hatch: an explicit ./name (or an absolute path) still nests on purpose.
( cd "$NEST" && "$ROOT/install.sh" --target ./my-project --mode auto --no-git >/dev/null )
[ -f "$NEST/my-project/AGENTS.md" ]

# Documented new-project flow: a non-empty cwd + bare name still works.
DOCU="$TMP/docucwd"
mkdir -p "$DOCU"
printf 'seed\n' > "$DOCU/seed.txt"
( cd "$DOCU" && "$ROOT/install.sh" --target my-project --mode auto --no-git >/dev/null )
[ -f "$DOCU/my-project/AGENTS.md" ]

# git init: a fresh target gets a repository; a re-run keeps it (idempotent).
GITP="$TMP/gitproj"
mkdir -p "$GITP"
"$ROOT/install.sh" --target "$GITP" --mode auto >/dev/null
[ -d "$GITP/.git" ]
GITP_OUT="$("$ROOT/install.sh" --target "$GITP" --mode auto 2>&1)"
printf '%s\n' "$GITP_OUT" | grep -q 'keep   .git'

# git init: a .git FILE (worktree-style) counts as already-initialized and is
# left untouched.
GITF="$TMP/gitfile"
mkdir -p "$GITF"
printf 'gitdir: /elsewhere\n' > "$GITF/.git"
GITF_OUT="$("$ROOT/install.sh" --target "$GITF" --mode auto 2>&1)"
printf '%s\n' "$GITF_OUT" | grep -q 'keep   .git'
[ -f "$GITF/.git" ]

echo "install smoke test: PASS"
