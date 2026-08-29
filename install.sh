#!/usr/bin/env bash
set -euo pipefail

REPO="${PROJECT_INIT_REPO:-turbin/ris-coding-harness}"
REF="${PROJECT_INIT_REF:-main}"
TARGET="."
MODE="auto"
FORCE=0
GIT_INIT=1
INSTALL_SKILL=1
AGENTS_LIST=""
SCOPE="project"

usage() {
  cat <<'USAGE'
Project engineering bootstrap installer

Usage:
  install.sh [options]

Options:
  --target PATH          Target project directory (default: .)
  --mode auto|init|adopt Initialization mode (default: auto)
  --force                Overwrite managed files created by this installer
  --no-git               Do not initialize a Git repository
  --no-skill             Do not install the PM-Workers skill
  --agent LIST           Also install the skill for these agents (comma-separated,
                         repeatable): claude, pi, kimi, kimi-code, opencode,
                         codex, agents, all
  --scope project|user   Skill install scope (default: project)
  -h, --help             Show this help

Modes:
  auto   Use init for an empty/near-empty directory, otherwise adopt
  init   Create the canonical engineering directory skeleton
  adopt  Add agent routing/rules/skill without restructuring source layout

Examples:
  ./install.sh --target my-project --mode init
  ./install.sh --target existing-project --mode adopt
  ./install.sh --agent claude,opencode
  ./install.sh --agent all --scope user
  curl -fsSL https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.sh | bash -s -- --target .
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:?missing value for --target}"; shift 2 ;;
    --mode) MODE="${2:?missing value for --mode}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --no-git) GIT_INIT=0; shift ;;
    --no-skill) INSTALL_SKILL=0; shift ;;
    --agent) AGENTS_LIST="${AGENTS_LIST:+$AGENTS_LIST,}${2:?missing value for --agent}"; shift 2 ;;
    --scope) SCOPE="${2:?missing value for --scope}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MODE" in auto|init|adopt) ;; *) echo "Invalid mode: $MODE" >&2; exit 2 ;; esac
case "$SCOPE" in project|user) ;; *) echo "Invalid scope: $SCOPE" >&2; exit 2 ;; esac

mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

SOURCE_ROOT=""
TMP_ROOT=""
cleanup() {
  [ -z "$TMP_ROOT" ] || rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/templates/project/AGENTS.md" ] && [ -f "$SCRIPT_DIR/skills/pm-workers-engineering/SKILL.md" ]; then
  SOURCE_ROOT="$SCRIPT_DIR"
else
  command -v curl >/dev/null 2>&1 || { echo "curl is required for remote installation" >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { echo "tar is required for remote installation" >&2; exit 1; }
  TMP_ROOT="$(mktemp -d)"
  ARCHIVE="$TMP_ROOT/source.tar.gz"
  curl -fsSL "https://github.com/$REPO/archive/$REF.tar.gz" -o "$ARCHIVE"
  tar -xzf "$ARCHIVE" -C "$TMP_ROOT"
  SOURCE_ROOT="$(find "$TMP_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [ -f "$SOURCE_ROOT/templates/project/AGENTS.md" ] || { echo "Installer templates not found in $REPO@$REF" >&2; exit 1; }
fi

managed_copy() {
  src="$1"
  dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    printf 'keep   %s\n' "${dst#$TARGET/}"
    return 0
  fi
  cp "$src" "$dst"
  printf 'write  %s\n' "${dst#$TARGET/}"
}

write_if_missing() {
  dst="$1"
  content="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    printf 'keep   %s\n' "${dst#$TARGET/}"
    return 0
  fi
  printf '%s\n' "$content" > "$dst"
  printf 'write  %s\n' "${dst#$TARGET/}"
}

# Print the skills directory for an agent according to SCOPE.
skill_dest() {
  case "$1" in
    claude)         [ "$SCOPE" = "user" ] && echo "$HOME/.claude/skills" || echo "$TARGET/.claude/skills" ;;
    pi)             [ "$SCOPE" = "user" ] && echo "$HOME/.pi/agent/skills" || echo "$TARGET/.pi/skills" ;;
    kimi|kimi-code) [ "$SCOPE" = "user" ] && echo "$HOME/.kimi/skills" || echo "$TARGET/.kimi/skills" ;;
    opencode)       [ "$SCOPE" = "user" ] && echo "$HOME/.config/opencode/skills" || echo "$TARGET/.opencode/skills" ;;
    codex)          [ "$SCOPE" = "user" ] && echo "$HOME/.codex/skills" || echo "$TARGET/.codex/skills" ;;
    agents)         [ "$SCOPE" = "user" ] && echo "$HOME/.agents/skills" || echo "$TARGET/.agents/skills" ;;
    *) return 1 ;;
  esac
}

is_near_empty() {
  count="$(find "$TARGET" -mindepth 1 -maxdepth 1 ! -name '.git' ! -name '.DS_Store' | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

if [ "$MODE" = "auto" ]; then
  if is_near_empty; then MODE="init"; else MODE="adopt"; fi
fi

# Resolve and validate skill destinations up front so an unknown --agent
# fails before any file is written.
SKILL_DESTS=()
if [ "$INSTALL_SKILL" -eq 1 ]; then
  SKILL_DESTS=("$TARGET/.agents/skills")
  if [ -n "$AGENTS_LIST" ]; then
    requested=""
    OLD_IFS="$IFS"; IFS=','
    for a in $AGENTS_LIST; do
      if [ "$a" = "all" ]; then
        requested="$requested claude pi kimi kimi-code opencode codex agents"
      else
        requested="$requested $a"
      fi
    done
    IFS="$OLD_IFS"
    for a in $requested; do
      if ! dest="$(skill_dest "$a")"; then
        echo "Unknown agent: $a" >&2
        echo "Supported agents: claude, pi, kimi, kimi-code, opencode, codex, agents, all" >&2
        exit 2
      fi
      dup=0
      for d in "${SKILL_DESTS[@]}"; do
        if [ "$d" = "$dest" ]; then dup=1; break; fi
      done
      [ "$dup" -eq 1 ] || SKILL_DESTS+=("$dest")
    done
  fi
fi

echo "Project bootstrap: mode=$MODE target=$TARGET"

managed_copy "$SOURCE_ROOT/templates/project/AGENTS.md" "$TARGET/AGENTS.md"
for f in "$SOURCE_ROOT"/templates/project/docs/engineering/*.md; do
  managed_copy "$f" "$TARGET/docs/engineering/$(basename "$f")"
done

install_skill_to() {
  dest="$1"
  skill_src="$2"
  skill_name="$(basename "$skill_src")"
  while IFS= read -r -d '' f; do
    rel="${f#$skill_src/}"
    managed_copy "$f" "$dest/$skill_name/$rel"
  done < <(find "$skill_src" -type f -print0)
}

if [ "$INSTALL_SKILL" -eq 1 ]; then
  for skill_src in "$SOURCE_ROOT"/skills/*/; do
    [ -d "$skill_src" ] || continue
    for dest in "${SKILL_DESTS[@]}"; do
      install_skill_to "$dest" "${skill_src%/}"
    done
  done
fi

RSI_SRC="$SOURCE_ROOT/templates/project/.rsi"
if [ -d "$RSI_SRC" ]; then
  while IFS= read -r -d '' f; do
    rel="${f#$RSI_SRC/}"
    managed_copy "$f" "$TARGET/.rsi/$rel"
  done < <(find "$RSI_SRC" -type f -print0)
fi

INDEX_BODY='# Index

Use this file as a lightweight navigation surface. Keep entries concise and point to the detailed artifact instead of duplicating it.

| Time | File | Summary |
|---|---|---|'

if [ "$MODE" = "init" ]; then
  for d in src tests docs decisions issues conversations output progress scripts tmp; do
    mkdir -p "$TARGET/$d"
    if [ "$d" != "docs" ] || [ ! -f "$TARGET/$d/index.md" ]; then
      write_if_missing "$TARGET/$d/index.md" "$INDEX_BODY"
    fi
  done
  mkdir -p "$TARGET/evals/results"
  write_if_missing "$TARGET/evals/index.md" "$INDEX_BODY"
fi

# Always provide routing indexes for project-management records when the directory exists.
for d in decisions issues progress; do
  if [ -d "$TARGET/$d" ]; then
    write_if_missing "$TARGET/$d/index.md" "$INDEX_BODY"
  fi
done

if [ ! -f "$TARGET/.gitignore" ]; then
  cat > "$TARGET/.gitignore" <<'GITIGNORE'
# Dependencies / virtual environments
node_modules/
.venv/
venv/

# Build outputs
build/
dist/

# Caches
__pycache__/
*.py[cod]
.cache/

# Environment / secrets
.env
.env.*
!.env.example

# Temporary project artifacts
tmp/*
!tmp/index.md

# OS / editor noise
.DS_Store
.idea/
.vscode/
GITIGNORE
  echo "write  .gitignore"
else
  echo "keep   .gitignore"
fi

if [ "$GIT_INIT" -eq 1 ]; then
  if command -v git >/dev/null 2>&1; then
    if [ ! -d "$TARGET/.git" ]; then
      if git -C "$TARGET" init -b main >/dev/null 2>&1; then
        :
      else
        git -C "$TARGET" init >/dev/null
      fi
      echo "init   .git"
    else
      echo "keep   .git"
    fi
  else
    echo "warn   git not found; repository not initialized" >&2
  fi
fi

echo
echo "Bootstrap complete."
echo "Next: fill docs/engineering/index.md and only the rule files relevant to this project."
echo "Agent entry: AGENTS.md"
if [ "$INSTALL_SKILL" -eq 1 ]; then
  for dest in "${SKILL_DESTS[@]}"; do
    echo "Skills: ${dest#$TARGET/}/{pm-workers-engineering,rsi-loop,min-loop}/SKILL.md"
  done
fi
