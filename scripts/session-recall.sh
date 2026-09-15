#!/usr/bin/env bash
# Kimi Code UserPromptSubmit hook wrapper: locate a Python interpreter and run
# session-recall.py. Fail-open: exits 0 when no interpreter is found.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for py in python3 python py; do
  if command -v "$py" >/dev/null 2>&1; then
    exec "$py" "$SCRIPT_DIR/session-recall.py" "$@"
  fi
done
echo "[session-recall] no python interpreter found; skipping" >&2
exit 0
