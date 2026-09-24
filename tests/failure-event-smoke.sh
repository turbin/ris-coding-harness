#!/usr/bin/env bash
# Golden smoke for scripts/failure-event.py (M0 acceptance).
set -euo pipefail
cd "$(dirname "$0")/.."
py=""
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then py="$c"; break; fi
done
if [ -z "$py" ]; then
  echo "failure-event-smoke: no python interpreter found" >&2
  exit 1
fi
"$py" tests/test-failure-event.py -v
