#!/usr/bin/env bash
set -euo pipefail

# rsi-loop thin shell: build the invocation prompt and hand it to an agent CLI.
# For interactive use, talk to your agent directly — this script exists for
# cron/CI (unattended) scenarios. The agent CLI is taken from:
#   1. --agent-cmd flag
#   2. RSI_AGENT_CMD environment variable
#   3. first available of: pi, opencode, claude, codex, kimi
# The script only invokes the agent; the actual loop runs inside the agent
# via the rsi-loop skill. Use --dry-run to print the prompt without running.

GATE="${RSI_GATE:-observe-only}"
ROUNDS="${RSI_ROUNDS:-5}"
QUEUE=""
RESUME=0
AGENT_CMD="${RSI_AGENT_CMD:-}"
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
  for c in pi opencode claude codex kimi; do
    if command -v "$c" >/dev/null 2>&1; then AGENT_CMD="$c"; break; fi
  done
fi
if [ -z "$AGENT_CMD" ]; then
  echo "No agent CLI found. Set RSI_AGENT_CMD (e.g. RSI_AGENT_CMD='pi' run-loop.sh ...)" >&2
  exit 2
fi

RESUME_FLAG=""
[ "$RESUME" -eq 1 ] && RESUME_FLAG="--resume"
PROMPT="Invoke the rsi-loop skill (skills/rsi-loop/SKILL.md, or .agents/skills/rsi-loop/ in the target project) with: --gate $GATE --rounds $ROUNDS $QUEUE $RESUME_FLAG. Read the skill and follow its procedure."

echo "gate: $GATE   rounds: $ROUNDS   agent: $AGENT_CMD   resume: $([ "$RESUME" -eq 1 ] && echo yes || echo no)"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "prompt: $PROMPT"
  exit 0
fi
exec $AGENT_CMD "$PROMPT"
