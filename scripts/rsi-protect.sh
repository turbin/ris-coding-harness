#!/usr/bin/env bash
# Optional git pre-commit hook: hard-block staged changes to protected files.
# Install (from the repo root that runs the RSI loop):
#   ln -s "$(pwd)/scripts/rsi-protect.sh" .git/hooks/pre-commit   (or copy)
# Policy source: .rsi/policy.yaml protected_files (fallback: builtin list).
# Exits 1 when a staged path matches a protected glob — the commit is rejected
# even if an agent misbehaves (docs/rsi-design.md §4.5.8).
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
POLICY="$ROOT/.rsi/policy.yaml"

if [ -f "$POLICY" ] && command -v python3 >/dev/null 2>&1; then
  PROTECTED="$(python3 - "$POLICY" <<'PY'
import fnmatch, sys
try:
    import yaml
except ImportError:
    print("evals/tasks/** evals/run-eval.* docs/rsi-design.md install.sh install.ps1 .rsi/**")
    sys.exit(0)
with open(sys.argv[1], encoding="utf-8") as f:
    doc = yaml.safe_load(f) or {}
for g in (doc.get("protected_files") or []):
    print(g)
PY
)"
else
  PROTECTED='evals/tasks/** evals/run-eval.* docs/rsi-design.md install.sh install.ps1 .rsi/**'
fi

blocked=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  for glob in $PROTECTED; do
    case "$file" in
      $glob) echo "rsi-protect: blocked change to protected file: $file" >&2; blocked=1 ;;
    esac
  done
done < <(git diff --cached --name-only)

[ "$blocked" -eq 0 ] || {
  echo "rsi-protect: commit rejected (protected files must not be auto-modified)" >&2
  exit 1
}
exit 0
