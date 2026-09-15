#!/usr/bin/env bash
# Kimi Code compat shim — the generic installer handles kimi hooks:
#   scripts/install-agent-hooks.sh kimi --target <project>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/install-agent-hooks.sh" kimi "$@"
