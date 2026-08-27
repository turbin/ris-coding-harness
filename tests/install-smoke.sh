#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/new" "$TMP/existing"
printf '%s\n' '{"name":"existing-demo"}' > "$TMP/existing/package.json"

"$ROOT/install.sh" --target "$TMP/new" --mode auto --no-git >/dev/null
"$ROOT/install.sh" --target "$TMP/existing" --mode auto --no-git >/dev/null

# Empty project should receive canonical init layout.
test -f "$TMP/new/AGENTS.md"
test -f "$TMP/new/src/index.md"
test -f "$TMP/new/tests/index.md"
test -f "$TMP/new/docs/engineering/index.md"
test -f "$TMP/new/.agents/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/new/.rsi/policy.yaml"
test -d "$TMP/new/evals/results"

# Existing project should be adopted without canonical source/test directories.
test -f "$TMP/existing/AGENTS.md"
test -f "$TMP/existing/docs/engineering/index.md"
test -f "$TMP/existing/.agents/skills/pm-workers-engineering/SKILL.md"
test ! -e "$TMP/existing/src"
test ! -e "$TMP/existing/tests"
test -f "$TMP/existing/package.json"

# Re-running must be non-destructive without --force.
printf '%s\n' '# local customization' > "$TMP/existing/docs/engineering/coding.md"
"$ROOT/install.sh" --target "$TMP/existing" --mode adopt --no-git >/dev/null
grep -q '^# local customization$' "$TMP/existing/docs/engineering/coding.md"

# --agent distributes the skill to each requested agent directory (plus canonical .agents).
mkdir -p "$TMP/multi"
"$ROOT/install.sh" --target "$TMP/multi" --mode auto --no-git --agent claude,opencode,codex >/dev/null
test -f "$TMP/multi/.agents/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/multi/.claude/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/multi/.opencode/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/multi/.codex/skills/pm-workers-engineering/SKILL.md"

# Repeated --agent flags accumulate.
mkdir -p "$TMP/repeat"
"$ROOT/install.sh" --target "$TMP/repeat" --mode auto --no-git --agent claude --agent pi >/dev/null
test -f "$TMP/repeat/.pi/skills/pm-workers-engineering/SKILL.md"
test -f "$TMP/repeat/.claude/skills/pm-workers-engineering/SKILL.md"

# Unknown agent names must fail before anything is written.
if "$ROOT/install.sh" --target "$TMP/bad" --mode auto --no-git --agent foo 2>/dev/null; then
  echo "install smoke test: FAIL (unknown agent accepted)" >&2
  exit 1
fi
test ! -e "$TMP/bad/AGENTS.md"

echo "install smoke test: PASS"
