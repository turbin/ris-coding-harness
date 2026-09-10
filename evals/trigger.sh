#!/usr/bin/env bash
set -euo pipefail

# RSI eval trigger: maintain the "pending eval" marker from git events.
# Hooks only set the marker — they never run an eval (the construction phase
# needs an agent and must not block the user's git operation). The marker is
# consumed by an OS scheduler thin shell or the next agent session, which runs
# the full campaign (setup -> agent works -> verify -> check) and then calls
# `trigger.sh consume`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKER="$SCRIPT_DIR/.eval-pending"
COUNTER="$SCRIPT_DIR/.commit-count"
DEFAULT_THRESHOLD=5

usage() {
  cat <<'USAGE'
RSI eval trigger

Usage:
  trigger.sh merge            Set the marker (reason: merge)
  trigger.sh commit [N]       Post-commit debounce: rule-path commits set the
                              marker immediately; other commits set it after
                              every N commits (default 5). L1P platform cards
                              (docs/engineering/platform/**) never trigger.
  trigger.sh status           Exit 0 and print the reason when a marker exists;
                              exit 1 otherwise.
  trigger.sh consume          Print the reason, clear the marker, exit 0;
                              exit 1 when nothing is pending.
  trigger.sh reset            Clear marker and counter.
  trigger.sh -h|--help        Show this help
USAGE
}

set_pending() {
  printf '%s %s\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MARKER"
  echo "eval pending: $1"
}

cmd_merge() {
  set_pending "merge"
}

cmd_commit() {
  threshold="${1:-$DEFAULT_THRESHOLD}"
  names="$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || true)"
  rules_hit=""
  while IFS= read -r p; do
    case "$p" in
      docs/engineering/platform/*) ;;  # L1P has no eval gate
      docs/engineering/*|.agents/skills/*|.rsi/*) rules_hit="$p"; break ;;
    esac
  done <<< "$names"
  if [ -n "$rules_hit" ]; then
    set_pending "rules"
    echo 0 > "$COUNTER"
    return
  fi
  count=0
  [ -f "$COUNTER" ] && count="$(cat "$COUNTER")"
  count=$((count + 1))
  if [ "$count" -ge "$threshold" ]; then
    set_pending "commits:$threshold"
    echo 0 > "$COUNTER"
  else
    echo "$count" > "$COUNTER"
  fi
}

cmd_status() {
  if [ -f "$MARKER" ]; then
    cat "$MARKER"
    return 0
  fi
  echo "no pending eval" >&2
  return 1
}

cmd_consume() {
  if [ -f "$MARKER" ]; then
    cat "$MARKER"
    rm -f "$MARKER"
    echo 0 > "$COUNTER"
    return 0
  fi
  echo "no pending eval" >&2
  return 1
}

cmd_reset() {
  rm -f "$MARKER" "$COUNTER"
  echo "cleared"
}

case "${1:-}" in
  merge) shift; cmd_merge "$@" ;;
  commit) shift; cmd_commit "$@" ;;
  status) shift; cmd_status "$@" ;;
  consume) shift; cmd_consume "$@" ;;
  reset) shift; cmd_reset "$@" ;;
  -h|--help|"") usage ;;
  *) echo "Unknown command: $1" >&2; usage >&2; exit 2 ;;
esac
