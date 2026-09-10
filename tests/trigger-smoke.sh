#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO/evals" "$REPO/src"
cp "$ROOT/evals/trigger.sh" "$ROOT/evals/install-hooks.sh" "$REPO/evals/"

cd "$REPO"
git init -q -b main
git config user.email test@example.com
git config user.name test

T="$REPO/evals/trigger.sh"

# 1. no pending eval initially
if "$T" status >/dev/null 2>&1; then
  echo "trigger smoke: FAIL (status should report no pending eval)" >&2
  exit 1
fi

# 2. plain commits debounce: threshold 2, second commit sets the marker
echo a > src/a.txt
git add -A && git commit -qm c1
"$T" commit 2
if "$T" status >/dev/null 2>&1; then
  echo "trigger smoke: FAIL (marker set before debounce threshold)" >&2
  exit 1
fi
echo b > src/b.txt
git add -A && git commit -qm c2
"$T" commit 2
"$T" status | grep -q 'commits'

# 3. consume prints the reason and clears the marker
"$T" consume | grep -q 'commits'
if "$T" status >/dev/null 2>&1; then
  echo "trigger smoke: FAIL (consume did not clear the marker)" >&2
  exit 1
fi

# 4. a commit touching rule paths sets the marker immediately
mkdir -p docs/engineering
echo r > docs/engineering/coding.md
git add -A && git commit -qm c3
"$T" commit 5
"$T" status | grep -q 'rules'

# 4b. L1P platform cards do NOT set the marker (no eval gate for L1P)
"$T" reset
mkdir -p docs/engineering/platform/windows
echo w > docs/engineering/platform/windows/x.md
git add -A && git commit -qm c3b
"$T" commit 2
if "$T" status >/dev/null 2>&1; then
  echo "trigger smoke: FAIL (platform card commit must not set the marker)" >&2
  exit 1
fi

# 5. merge event sets the marker
"$T" merge
"$T" status | grep -q 'merge'

# 6. reset clears marker and counter
"$T" reset
if "$T" status >/dev/null 2>&1; then
  echo "trigger smoke: FAIL (reset did not clear)" >&2
  exit 1
fi

# 7. install-hooks wires real git hooks end-to-end
bash "$REPO/evals/install-hooks.sh" --target "$REPO" >/dev/null
test -x "$REPO/.git/hooks/post-commit"
test -x "$REPO/.git/hooks/post-merge"
echo y > docs/engineering/testing.md
git add -A && git commit -qm c4
"$T" status | grep -q 'rules'

# 8. refuses a non-git directory
if bash "$REPO/evals/install-hooks.sh" --target "$TMP/nogit" >/dev/null 2>&1; then
  echo "trigger smoke: FAIL (install-hooks accepted a non-git directory)" >&2
  exit 1
fi

echo "trigger smoke test: PASS"
