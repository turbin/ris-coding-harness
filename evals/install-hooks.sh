#!/usr/bin/env bash
set -euo pipefail

# Install git hooks that maintain the eval "pending" marker (debounced).
# Idempotent: existing hooks are overwritten only when they carry the managed
# marker comment; foreign hooks are left alone. Run once per target project:
#
#   evals/install-hooks.sh            # hooks for the current repository
#   evals/install-hooks.sh --target PATH

usage() {
  cat <<'USAGE'
Install eval trigger hooks (post-merge, post-commit) into a git repository.

Usage:
  install-hooks.sh [--target PATH]   Target repository (default: .)
  install-hooks.sh -h|--help         Show this help
USAGE
}

TARGET="."
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$TARGET" && pwd)"
if [ ! -d "$ROOT/.git" ]; then
  echo "error: $ROOT is not a git repository" >&2
  exit 1
fi

HOOKS_DIR="$ROOT/.git/hooks"
custom="$(git -C "$ROOT" config core.hooksPath 2>/dev/null || true)"
if [ -n "$custom" ]; then
  case "$custom" in
    /*) HOOKS_DIR="$custom" ;;
    *)  HOOKS_DIR="$ROOT/$custom" ;;
  esac
fi
mkdir -p "$HOOKS_DIR"

write_hook() {
  name="$1"
  event="$2"
  file="$HOOKS_DIR/$name"
  if [ -f "$file" ] && ! grep -q 'managed by ris-coding-harness' "$file"; then
    echo "keep   $name (exists, not managed)"
    return
  fi
  cat > "$file" <<EOF
#!/usr/bin/env bash
# managed by ris-coding-harness: eval trigger ($event)
# Resolve the repo root at runtime: hooks may live under a custom
# core.hooksPath, so the relative ../.. walk is only a fallback.
ROOT="\$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "\$ROOT" ] || ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/../.." && pwd)"
"\$ROOT/evals/trigger.sh" $event || true
EOF
  chmod +x "$file"
  echo "write  $name"
}

write_hook post-commit "commit"
write_hook post-merge "merge"
echo "hooks installed in ${HOOKS_DIR#"$ROOT"/} — marker: evals/.eval-pending (gitignored)"
