#!/usr/bin/env bash
# Optional git pre-commit hook: hard-block staged changes to protected files.
# Install (from the repo root that runs the RSI loop):
#   ln -s "$(pwd)/scripts/rsi-protect.sh" .git/hooks/pre-commit   (or copy)
# Policy source: .rsi/policy.yaml protected_files (fallback: builtin list).
# Exits 1 when a staged path matches a protected glob — the commit is rejected
# even if an agent misbehaves (docs/rsi-design.md §4.5.8).
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
POLICY="$ROOT/.harness/.rsi/policy.yaml"
[ -f "$POLICY" ] || POLICY="$ROOT/.rsi/policy.yaml"  # legacy layout

if [ -f "$POLICY" ] && command -v python3 >/dev/null 2>&1; then
  # Windows python builds emit CRLF; strip \r so glob entries match filenames.
  LISTS="$(python3 - "$POLICY" <<'PY' | tr -d '\r'
import sys
try:
    import yaml
except ImportError:
    print("P:evals/tasks/** P:evals/run-eval.* P:docs/rsi-design.md P:install.sh P:install.ps1 P:.harness/.rsi/** P:.rsi/**")
    print("H:docs/engineering/platform/**")
    sys.exit(0)
with open(sys.argv[1], encoding="utf-8") as f:
    doc = yaml.safe_load(f) or {}
for g in (doc.get("protected_files") or []):
    print("P:" + g)
for g in (doc.get("hard_blocked_files") or []):
    print("H:" + g)
PY
)"
else
  LISTS='P:evals/tasks/** P:evals/run-eval.* P:docs/rsi-design.md P:install.sh P:install.ps1 P:.harness/.rsi/** P:.rsi/**
H:docs/engineering/platform/**'
fi

blocked=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  for entry in $LISTS; do
    kind="${entry%%:*}"
    glob="${entry#*:}"
    case "$file" in
      $glob)
        if [ "$kind" = "H" ]; then
          echo "rsi-protect: blocked L1P platform card in an automated commit: $file" >&2
          echo "rsi-protect: a reviewed card may be committed by a human with: git commit --no-verify" >&2
        else
          echo "rsi-protect: blocked change to protected file: $file" >&2
        fi
        blocked=1 ;;
    esac
  done
done < <(git diff --cached --name-only)

[ "$blocked" -eq 0 ] || {
  echo "rsi-protect: commit rejected (protected files must not be auto-modified)" >&2
  exit 1
}
exit 0
