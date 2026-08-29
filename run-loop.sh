#!/usr/bin/env bash
set -euo pipefail

# rsi-loop thin shell: build the invocation prompt and hand it to an agent CLI.
# For interactive use, talk to your agent directly — this script exists for
# cron/CI (unattended) scenarios. The agent CLI is taken from:
#   1. --agent-cmd flag
#   2. RSI_AGENT_CMD environment variable
#   3. RSI_AGENT_CANDIDATES (env var, or progress/loop/agent.env) — first
#      available candidate
#   4. builtin default list: pi, opencode, claude, codex, kimi
# The script only invokes the agent; the actual loop runs inside the agent
# via the rsi-loop skill. Use --dry-run to print the prompt without running.
# Use --headless for non-interactive print mode (pi -p / kimi -p --print),
# suitable for cron/CI and sub-agent rounds.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_ENV="$SCRIPT_DIR/progress/loop/agent.env"
[ -f "$AGENT_ENV" ] && . "$AGENT_ENV"

GATE="${RSI_GATE:-observe-only}"
ROUNDS="${RSI_ROUNDS:-5}"
QUEUE=""
RESUME=0
AGENT_CMD="${RSI_AGENT_CMD:-}"
CANDIDATES="${RSI_AGENT_CANDIDATES:-pi opencode claude codex kimi}"
HEADLESS="${RSI_HEADLESS:-0}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
rsi-loop thin shell

Usage:
  run-loop.sh [--gate LEVEL] [--rounds N] [--queue FILE] [--resume]
              [--agent-cmd CMD] [--dry-run]

  --gate LEVEL   observe-only | l1-auto | all-manual (default: observe-only)
  --rounds N     rounds to run (default: 5)
  --queue FILE   task queue (default: progress/loop/tasks.yaml)
  --resume       resume from progress/loop/state.yaml
  --agent-cmd    agent CLI command (default: $RSI_AGENT_CMD or first available)
  --headless     non-interactive print mode (pi -p / kimi -p --print; default: RSI_HEADLESS)
  --dry-run      print the invocation prompt without running
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --gate) GATE="${2:?}"; shift 2 ;;
    --rounds) ROUNDS="${2:?}"; shift 2 ;;
    --queue) QUEUE="--queue ${2:?}"; shift 2 ;;
    --resume) RESUME=1; shift ;;
    --agent-cmd) AGENT_CMD="$2"; shift 2 ;;
    --headless) HEADLESS=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$GATE" in observe-only|l1-auto|all-manual) ;; *)
  echo "Invalid gate: $GATE" >&2; exit 2 ;;
esac
case "$ROUNDS" in *[!0-9]*|"") echo "Invalid rounds: $ROUNDS" >&2; exit 2 ;; esac

if [ "$DRY_RUN" -eq 1 ]; then
  AGENT_CMD="(dry-run)"
elif [ -z "$AGENT_CMD" ]; then
  # Candidates may be space- or comma-separated.
  for c in $(echo "$CANDIDATES" | tr ',' ' '); do
    if command -v "$c" >/dev/null 2>&1; then AGENT_CMD="$c"; break; fi
  done
fi
if [ -z "$AGENT_CMD" ]; then
  echo "No agent CLI found. Set RSI_AGENT_CMD (e.g. RSI_AGENT_CMD='pi' run-loop.sh ...) or RSI_AGENT_CANDIDATES." >&2
  exit 2
fi

RESUME_FLAG=""
[ "$RESUME" -eq 1 ] && RESUME_FLAG="--resume"
PROMPT="Invoke the rsi-loop skill (skills/rsi-loop/SKILL.md, or .agents/skills/rsi-loop/ in the target project) with: --gate $GATE --rounds $ROUNDS $QUEUE $RESUME_FLAG. Read the skill and follow its procedure."

echo "gate: $GATE   rounds: $ROUNDS   agent: $AGENT_CMD   headless: $([ "$HEADLESS" -eq 1 ] && echo yes || echo no)   resume: $([ "$RESUME" -eq 1 ] && echo yes || echo no)"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "prompt: $PROMPT"
  exit 0
fi
if [ "$HEADLESS" -eq 1 ]; then
  case "$AGENT_CMD" in
    pi)   exec pi -p "$PROMPT" ;;
    kimi) exec kimi -p "$PROMPT" --print ;;
    *)    exec "$AGENT_CMD" "$PROMPT" ;;
  esac
fi
exec $AGENT_CMD "$PROMPT"
