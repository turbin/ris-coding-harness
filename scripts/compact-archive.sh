#!/usr/bin/env bash
# Kimi Code PostCompact hook wrapper: locate a Python interpreter and run
# compact-archive.py. Fail-open: exits 0 when no interpreter is found so the
# hook never blocks compaction.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for py in python3 python py; do
  if command -v "$py" >/dev/null 2>&1; then
    exec "$py" "$SCRIPT_DIR/compact-archive.py" "$@"
  fi
done
echo "[compact-archive] no python interpreter found; skipping" >&2
exit 0
