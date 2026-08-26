#!/usr/bin/env bash
set -euo pipefail

REPO="${PROJECT_INIT_REPO:-turbin/project-init-scripts}"
REF="${PROJECT_INIT_REF:-main}"
TARGET="."
MODE="auto"
FORCE=0
GIT_INIT=1
INSTALL_SKILL=1

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
  -h, --help             Show this help

Modes:
  auto   Use init for an empty/near-empty directory, otherwise adopt
  init   Create the canonical engineering directory skeleton
  adopt  Add agent routing/rules/skill without restructuring source layout

Examples:
  ./install.sh --target my-project --mode init
  ./install.sh --target existing-project --mode adopt
  curl -fsSL https://raw.githubusercontent.com/turbin/project-init-scripts/main/install.sh | bash -s -- --target .
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) TARGET="${2:?missing value for --target}"; shift 2 ;;
    --mode) MODE="${2:?missing value for --mode}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --no-git) GIT_INIT=0; shift ;;
    --no-skill) INSTALL_SKILL=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MODE" in auto|init|adopt) ;; *) echo "Invalid mode: $MODE" >&2; exit 2 ;; esac

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

is_near_empty() {
  count="$(find "$TARGET" -mindepth 1 -maxdepth 1 ! -name '.git' ! -name '.DS_Store' | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

if [ "$MODE" = "auto" ]; then
  if is_near_empty; then MODE="init"; else MODE="adopt"; fi
fi

echo "Project bootstrap: mode=$MODE target=$TARGET"

managed_copy "$SOURCE_ROOT/templates/project/AGENTS.md" "$TARGET/AGENTS.md"
for f in "$SOURCE_ROOT"/templates/project/docs/engineering/*.md; do
  managed_copy "$f" "$TARGET/docs/engineering/$(basename "$f")"
done

if [ "$INSTALL_SKILL" -eq 1 ]; then
  SKILL_SRC="$SOURCE_ROOT/skills/pm-workers-engineering"
  while IFS= read -r -d '' f; do
    rel="${f#$SKILL_SRC/}"
    managed_copy "$f" "$TARGET/.agents/skills/pm-workers-engineering/$rel"
  done < <(find "$SKILL_SRC" -type f -print0)
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
  echo "Skill entry: .agents/skills/pm-workers-engineering/SKILL.md"
fi
