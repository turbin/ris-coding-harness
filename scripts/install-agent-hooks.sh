#!/usr/bin/env bash
# Wrapper: locate a Python interpreter and run install-agent-hooks.py.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for py in python3 python py; do
  if command -v "$py" >/dev/null 2>&1; then
    exec "$py" "$SCRIPT_DIR/install-agent-hooks.py" "$@"
  fi
done
echo "[install-agent-hooks] no python interpreter found" >&2
exit 1
