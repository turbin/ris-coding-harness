#!/usr/bin/env bash
set -euo pipefail

# min-loop thin shell: iterate docs/specs/*.md and hand each spec to an agent
# via the min-loop skill (skills/min-loop/SKILL.md). One headless call per
# spec; reports land in output/specs/<spec-name>.md (written by the agent).
#
# Interactive use is the standard entry (ask your agent directly). This
# script exists for batch/unattended scenarios. Agent CLI resolution:
#   1. --agent-cmd flag
#   2. RSI_AGENT_CMD environment variable
#   3. RSI_AGENT_CANDIDATES (env var, or progress/loop/agent.env)
#   4. builtin candidates: pi, kimi
#
# For custom agent flags, set RSI_AGENT_CMD to a full command including its
# headless flag, e.g. RSI_AGENT_CMD="pi --provider deepseek --model deepseek-v4-flash -p"
# (the prompt is appended as the last argument).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ENV="$SCRIPT_DIR/progress/loop/agent.env"
[ -f "$AGENT_ENV" ] && . "$AGENT_ENV"

AGENT_CMD="${RSI_AGENT_CMD:-}"
CANDIDATES="${RSI_AGENT_CANDIDATES:-pi kimi}"
SPECS_DIR="${SPECS_DIR:-$SCRIPT_DIR/docs/specs}"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/output/specs}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
min-loop thin shell

Usage:
  run-specs.sh [--specs DIR] [--out DIR] [--agent-cmd CMD] [--dry-run]

  --specs DIR    spec directory (default: docs/specs)
  --out DIR      report directory (default: output/specs)
  --agent-cmd    agent CLI command (default: $RSI_AGENT_CMD or first candidate)
  --dry-run      print the invocation prompts without running
  -h, --help     show this help
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --specs) SPECS_DIR="${2:?}"; shift 2 ;;
    --out) OUT_DIR="${2:?}"; shift 2 ;;
    --agent-cmd) AGENT_CMD="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$AGENT_CMD" ]; then
  for c in $(echo "$CANDIDATES" | tr ',' ' '); do
    if command -v "$c" >/dev/null 2>&1; then AGENT_CMD="$c"; break; fi
  done
fi
if [ -z "$AGENT_CMD" ]; then
  echo "No agent CLI found. Set RSI_AGENT_CMD (e.g. RSI_AGENT_CMD='pi --provider deepseek -p' run-specs.sh ...) or RSI_AGENT_CANDIDATES." >&2
  exit 2
fi

if [ ! -d "$SPECS_DIR" ]; then
  echo "No spec directory: $SPECS_DIR (create it and drop .md specs, or pass --specs)" >&2
  exit 2
fi
mkdir -p "$OUT_DIR"

mapfile -t specs < <(find "$SPECS_DIR" -maxdepth 1 -name '*.md' | sort)
if [ "${#specs[@]}" -eq 0 ]; then
  echo "No specs found in $SPECS_DIR" >&2
  exit 1
fi

echo "specs: ${#specs[@]}   agent: $AGENT_CMD   out: $OUT_DIR"
for spec in "${specs[@]}"; do
  name="$(basename "$spec" .md)"
  prompt="Invoke the min-loop skill (skills/min-loop/SKILL.md, or .agents/skills/min-loop/SKILL.md in the target project) with spec: $spec. Follow its procedure and write the report to $OUT_DIR/$name.md."
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "==> $name"
    echo "    prompt: $prompt"
    continue
  fi
  echo "==> $name ($AGENT_CMD)"
  case "$AGENT_CMD" in
    pi)   pi -p "$prompt" ;;
    kimi) kimi -p "$prompt" --print ;;
    *)    "$AGENT_CMD" "$prompt" ;;
  esac
done
echo "done. reports: $OUT_DIR"
