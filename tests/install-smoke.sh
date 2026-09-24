#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Isolate the user home for the whole run: the installer installs the skills
# marked scope=user in .harness/skill-scope.txt into agent user directories, so
# no test may ever write into the real home. USERPROFILE/KIMI_CODE_HOME are set
# too because the python hook adapters resolve ~ via those on Windows.
export HOME="$TMP/home"
export USERPROFILE="$TMP/home"
export KIMI_CODE_HOME="$TMP/home/.kimi-code"
mkdir -p "$HOME"

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
# Manifest records the two scopes: project skills, user skills, and where the
# user-level ones landed (absolute paths outside the target).
if grep -q '"skills": \[[^]]*c4-architecture' "$TMP/new/.harness/manifest.json"; then
  echo "install smoke test: FAIL (user-level skill listed as a project skill)" >&2
  exit 1
fi
grep -q '"user_skills": \[[^]]*"architecture-topology"' "$TMP/new/.harness/manifest.json"
grep -q '"user_skills": \[[^]]*"c4-architecture"' "$TMP/new/.harness/manifest.json"
grep -q '"user_skills": \[[^]]*"mermaid-diagrams"' "$TMP/new/.harness/manifest.json"
grep -q '"skill_scope": {[^}]*"architecture-topology": "user"' "$TMP/new/.harness/manifest.json"
grep -q '"skill_scope": {[^}]*"c4-architecture": "user"' "$TMP/new/.harness/manifest.json"
grep -q '"skill_scope": {[^}]*"mermaid-diagrams": "user"' "$TMP/new/.harness/manifest.json"
grep -qF "\"user_agent_destinations\": [\"$HOME/.claude/skills\"" "$TMP/new/.harness/manifest.json"
grep -qF "$HOME/.kimi-code/skills" "$TMP/new/.harness/manifest.json"
test -d "$TMP/new/evals/results"

# Both vendored diagram skills are user-level (.harness/skill-scope.txt): they
# land in the agent user directories and never inside the project.
test ! -e "$TMP/new/.harness/skills/c4-architecture"
test ! -e "$TMP/new/.harness/skills/mermaid-diagrams"
for d in .claude/skills .pi/agent/skills .kimi-code/skills .config/opencode/skills .codex/skills .agents/skills; do
  test -f "$HOME/$d/c4-architecture/SKILL.md"
  test -f "$HOME/$d/mermaid-diagrams/SKILL.md"
done
# The old kimi home is no longer used.
test ! -e "$HOME/.kimi"
# The managed section registers them as user-level and names their real homes.
grep -q 'User-level skills' "$TMP/new/AGENTS.md"
grep -q -- '~/.kimi-code/skills/c4-architecture/' "$TMP/new/AGENTS.md"
grep -q -- '~/.claude/skills/mermaid-diagrams/' "$TMP/new/AGENTS.md"

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

# --agent distributes the project skills to each requested agent directory
# (plus canonical .harness); user-level skills stay in the user directories.
mkdir -p "$TMP/multi"
"$ROOT/install.sh" --target "$TMP/multi" --mode auto --no-git --agent claude,opencode,codex >/dev/null
test -f "$TMP/multi/.harness/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/multi/.harness/skills/rsi-loop/SKILL.md"
test -f "$TMP/multi/.claude/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/multi/.claude/skills/rsi-loop/SKILL.md"
test -f "$TMP/multi/.opencode/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/multi/.codex/skills/pm-workers-engineering/SKILL.md"
test ! -e "$TMP/multi/.claude/skills/c4-architecture"
test ! -e "$TMP/multi/.opencode/skills/mermaid-diagrams"
test ! -e "$TMP/multi/.codex/skills/c4-architecture"

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
# ... and reports the user-level copies in the agent user directories.
printf '%s\n' "$out" | grep -q "ok         $HOME/.kimi-code/skills/c4-architecture"
printf '%s\n' "$out" | grep -q "ok         $HOME/.claude/skills/mermaid-diagrams"
printf '%s\n' "$out" | grep -q "ok         $HOME/.pi/agent/skills/c4-architecture"

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

# A missing user-level copy (deleted SKILL.md) is detected, then healed by a
# re-run; the project side stays untouched.
rm "$HOME/.codex/skills/c4-architecture/SKILL.md"
if out="$("$ROOT/install.sh" --target "$TMP/new" --check 2>&1)"; then
  echo "install smoke test: FAIL (--check missed incomplete user-level skill)" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "incomplete $HOME/.codex/skills/c4-architecture"
"$ROOT/install.sh" --target "$TMP/new" --mode adopt --no-git >/dev/null
test -f "$HOME/.codex/skills/c4-architecture/SKILL.md"
test ! -e "$TMP/new/.harness/skills/c4-architecture"

# A user-level copy that is entirely absent is reported missing (exit 1).
mv "$HOME/.agents/skills/mermaid-diagrams" "$HOME/mermaid-diagrams-away"
if out="$("$ROOT/install.sh" --target "$TMP/new" --check 2>&1)"; then
  echo "install smoke test: FAIL (--check missed missing user-level skill)" >&2
  exit 1
fi
printf '%s\n' "$out" | grep -q "missing    $HOME/.agents/skills/mermaid-diagrams"
"$ROOT/install.sh" --target "$TMP/new" --mode adopt --no-git >/dev/null
test -f "$HOME/.agents/skills/mermaid-diagrams/SKILL.md"
test ! -e "$TMP/new/.harness/skills/mermaid-diagrams"

# --agent narrows the user-level install: only the requested agent's user
# directory is written for those skills.
NARROW_HOME="$TMP/narrowhome"; mkdir -p "$NARROW_HOME" "$TMP/narrowproj"
HOME="$NARROW_HOME" USERPROFILE="$NARROW_HOME" KIMI_CODE_HOME="$NARROW_HOME/.kimi-code" \
  "$ROOT/install.sh" --target "$TMP/narrowproj" --mode adopt --no-git --agent claude --skip-env >/dev/null
test -f "$NARROW_HOME/.claude/skills/c4-architecture/SKILL.md"
test ! -e "$NARROW_HOME/.codex"
test ! -e "$NARROW_HOME/.kimi-code"
HOME="$NARROW_HOME" USERPROFILE="$NARROW_HOME" KIMI_CODE_HOME="$NARROW_HOME/.kimi-code" \
  "$ROOT/install.sh" --target "$TMP/narrowproj" --check --agent claude >/dev/null

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
HOME="$FAKEHOME" USERPROFILE="$FAKEHOME" KIMI_CODE_HOME="$FAKEHOME/.kimi-code" \
  "$ROOT/install.sh" --target "$TMP/userproj" --mode adopt --no-git --scope user \
  --agent claude,kimi-code --skip-env >/dev/null
test -f "$FAKEHOME/.claude/skills/pm-workers-engineering/SKILL.md"
test ! -e "$TMP/userproj/.claude"
# kimi/kimi-code resolve to the Kimi Code home, not the retired ~/.kimi.
test -f "$FAKEHOME/.kimi-code/skills/pm-workers-engineering/SKILL.md"
test -f "$FAKEHOME/.kimi-code/skills/c4-architecture/SKILL.md"
test ! -e "$FAKEHOME/.kimi/skills"

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

# --search off skips the routing block, graphify included, but the manifest still
# records the graphify decision. The word "graphify" itself may still appear in the
# user-level skills blurbs, so assert on the injected routing lines instead.
grep -q '"graphify": {"decision":' "$TMP/searchoff/.harness/manifest.json"
if grep -qE 'graphify is (enabled|\*\*DISABLED\*\*)' "$TMP/searchoff/AGENTS.md"; then
  echo "install smoke test: FAIL (--search off still injects the graphify routing)" >&2
  exit 1
fi

# graphify scale gate: the threshold lives in the repository-level
# .harness/graphify-threshold.txt, and the decision reaches the managed routing
# section and the manifest.
mkdir -p "$TMP/gfy-small"
"$ROOT/install.sh" --target "$TMP/gfy-small" --mode adopt --no-git --skip-env >/dev/null
grep -q -- '- graphify is enabled for this project (0 files <= threshold 483)' "$TMP/gfy-small/AGENTS.md"
grep -q '"graphify": {"decision": "on", "metric": "files", "value": 0, "threshold": 483, "source": "auto"}' \
  "$TMP/gfy-small/.harness/manifest.json"

# A project above the threshold gets the explicit disable instead of the graphify
# routing line.
mkdir -p "$TMP/gfy-big/data"
i=0; while [ "$i" -lt 500 ]; do : > "$TMP/gfy-big/data/f$i.txt"; i=$((i + 1)); done
"$ROOT/install.sh" --target "$TMP/gfy-big" --mode adopt --no-git --skip-env >/dev/null
grep -q -- '  (500 files > threshold 483)' "$TMP/gfy-big/AGENTS.md"
grep -q 'graphify is \*\*DISABLED\*\* for this project' "$TMP/gfy-big/AGENTS.md"
if grep -q 'graphify` when `graphify-out/`' "$TMP/gfy-big/AGENTS.md"; then
  echo "install smoke test: FAIL (off decision kept the graphify routing line)" >&2
  exit 1
fi
grep -q '"graphify": {"decision": "off", "metric": "files", "value": 500, "threshold": 483, "source": "auto"}' \
  "$TMP/gfy-big/.harness/manifest.json"

# A `git init`ed project with an empty index must not recount as 0 files — that
# flipped the decision back to "on" on every re-run.
if command -v git >/dev/null 2>&1; then
  mkdir -p "$TMP/gfy-git"
  i=0; while [ "$i" -lt 500 ]; do : > "$TMP/gfy-git/f$i.txt"; i=$((i + 1)); done
  git -C "$TMP/gfy-git" init -q
  "$ROOT/install.sh" --target "$TMP/gfy-git" --mode adopt --no-git --skip-env >/dev/null
  out="$("$ROOT/install.sh" --target "$TMP/gfy-git" --mode adopt --no-git --skip-env)"
  printf '%s\n' "$out" | grep -qE '^graphify off \([0-9]+ files > 483\)' || {
    echo "install smoke test: FAIL (git project with empty index recounted as 0 files)" >&2; exit 1; }
fi

# --graphify on|off forces the decision over the measured file count.
"$ROOT/install.sh" --target "$TMP/gfy-big" --mode adopt --no-git --skip-env --graphify on >/dev/null
grep -q -- '- graphify is enabled for this project ([0-9]* files > threshold 483; forced by --graphify on)' \
  "$TMP/gfy-big/AGENTS.md"
grep -q '"decision": "on", "metric": "files"' "$TMP/gfy-big/.harness/manifest.json"
grep -q '"threshold": 483, "source": "flag"' "$TMP/gfy-big/.harness/manifest.json"
"$ROOT/install.sh" --target "$TMP/gfy-small" --mode adopt --no-git --skip-env --graphify off >/dev/null
grep -q 'graphify is \*\*DISABLED\*\* for this project' "$TMP/gfy-small/AGENTS.md"
grep -q '"decision": "off", "metric": "files"' "$TMP/gfy-small/.harness/manifest.json"
grep -q '"threshold": 483, "source": "flag"' "$TMP/gfy-small/.harness/manifest.json"

# Invalid or missing --graphify values exit 2 before anything is written.
rc=0; "$ROOT/install.sh" --target "$TMP/gfy-bad" --mode adopt --no-git --graphify maybe >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "install smoke test: FAIL (--graphify maybe exits $rc, want 2)" >&2; exit 1; }
rc=0; "$ROOT/install.sh" --target "$TMP/gfy-bad" --mode adopt --no-git --graphify >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "install smoke test: FAIL (--graphify missing value exits $rc, want 2)" >&2; exit 1; }
test ! -e "$TMP/gfy-bad/AGENTS.md"

# The threshold file drives the gate: a source tree carrying a tiny threshold
# flips a small project off, and a missing file falls back to the built-in
# default with a warning.
SRCCOPY="$TMP/srccopy"; mkdir -p "$SRCCOPY" "$TMP/gfy-thr"
cp "$ROOT/install.sh" "$SRCCOPY/"
cp -r "$ROOT/.harness" "$SRCCOPY/.harness"
printf 'metric: files\nthreshold: 2\n' > "$SRCCOPY/.harness/graphify-threshold.txt"
for f in a b c; do printf 'x\n' > "$TMP/gfy-thr/$f.txt"; done
out="$("$SRCCOPY/install.sh" --target "$TMP/gfy-thr" --mode adopt --no-git --skip-env 2>&1)"
printf '%s\n' "$out" | grep -q '^graphify off (3 files > 2)'
grep -q '"threshold": 2' "$TMP/gfy-thr/.harness/manifest.json"
rm "$SRCCOPY/.harness/graphify-threshold.txt"
out="$("$SRCCOPY/install.sh" --target "$TMP/gfy-thr" --mode adopt --no-git --skip-env 2>&1)"
printf '%s\n' "$out" | grep -q 'warn   .*graphify-threshold.txt missing or invalid'
grep -q '"threshold": 483' "$TMP/gfy-thr/.harness/manifest.json"

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
