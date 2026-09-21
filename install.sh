#!/usr/bin/env bash
set -euo pipefail

REPO="${PROJECT_INIT_REPO:-turbin/ris-coding-harness}"
REF="${PROJECT_INIT_REF:-main}"
TARGET="."
MODE="auto"
FORCE=0
GIT_INIT=1
INSTALL_SKILL=1
CHECK=0
SKIP_ENV=0
DRY_RUN_ENV=0
STRICT_ENV=0
AGENTS_LIST=""
SCOPE="project"
SEARCH="zvec"
INSTALLED_FILES=""
BEGIN_MARK='<!-- ris-coding-harness:begin -->'
END_MARK='<!-- ris-coding-harness:end -->'

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
  --check                Verify skills, policy, and the AGENTS.md managed section;
                         write nothing. Exit 0 when all present, 1 when
                         missing/incomplete, 2 on usage errors
  --skip-env             Skip the environment bootstrap stage entirely
  --dry-run-env          Print the env bootstrap commands without executing them
  --strict-env           Exit with code 3 when the env bootstrap stage fails
  --agent LIST           Also install the skill for these agents (comma-separated,
                         repeatable): claude, pi, kimi, kimi-code, opencode,
                         codex, agents, all
  --scope project|user   Skill install scope (default: project)
  --search zvec|off      Workspace search routing (default: zvec). zvec injects
                         the search-routing section into AGENTS.md and
                         provisions the zg CLI (npm -g @zvec/zvec-grep) when
                         missing; off skips both
  -h, --help             Show this help

Modes:
  auto   Use init for an empty/near-empty directory, otherwise adopt
  init   Create the canonical engineering directory skeleton
  adopt  Add agent routing/rules/skill without restructuring source layout

Examples:
  ./install.sh                                   # initialize the CURRENT directory
  ./install.sh --target my-project --mode init   # create a NEW project dir;
                                                 # run this from its PARENT directory
  ./install.sh --target existing-project --mode adopt
  ./install.sh --agent claude,opencode
  ./install.sh --agent all --scope user
  curl -fsSL https://raw.githubusercontent.com/turbin/ris-coding-harness/main/install.sh | bash -s -- --target .
USAGE
}

# Usage errors exit 2 (see README "Exit code contract").
require_value() {
  opt="$1"
  shift
  if [ "$#" -eq 0 ] || [ -z "$1" ]; then
    echo "Missing value for $opt" >&2
    exit 2
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) require_value "$1" "${2:-}"; TARGET="$2"; shift 2 ;;
    --mode) require_value "$1" "${2:-}"; MODE="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --no-git) GIT_INIT=0; shift ;;
    --no-skill) INSTALL_SKILL=0; shift ;;
    --check) CHECK=1; shift ;;
    --skip-env) SKIP_ENV=1; shift ;;
    --dry-run-env) DRY_RUN_ENV=1; shift ;;
    --strict-env) STRICT_ENV=1; shift ;;
    --agent) require_value "$1" "${2:-}"; AGENTS_LIST="${AGENTS_LIST:+$AGENTS_LIST,}$2"; shift 2 ;;
    --scope) require_value "$1" "${2:-}"; SCOPE="$2"; shift 2 ;;
    --search) require_value "$1" "${2:-}"; SEARCH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MODE" in auto|init|adopt) ;; *) echo "Invalid mode: $MODE" >&2; exit 2 ;; esac
case "$SCOPE" in project|user) ;; *) echo "Invalid scope: $SCOPE" >&2; exit 2 ;; esac
case "$SEARCH" in zvec|off) ;; *) echo "Invalid search: $SEARCH (want zvec|off)" >&2; exit 2 ;; esac

if [ "$CHECK" -eq 1 ] && [ "$INSTALL_SKILL" -eq 0 ]; then
  echo "--check and --no-skill are mutually exclusive" >&2
  exit 2
fi

# A bare relative --target (no '/') is treated as a NAME by the docs, so when
# it does not exist and the current directory looks like the project root the
# user wants to initialize (empty, or already harness-managed), refuse with
# guidance instead of silently nesting. An explicit ./name or an absolute
# path bypasses the guard.
is_near_empty() {
  count="$(find "${1:-.}" -mindepth 1 -maxdepth 1 ! -name '.git' ! -name '.DS_Store' | wc -l | tr -d ' ')"
  [ "$count" -eq 0 ]
}

if [ "$CHECK" -eq 1 ]; then
  # Never create the target in check mode; an absent target simply means
  # every project-scoped destination is missing.
  if abs_target="$(cd "$TARGET" 2>/dev/null && pwd)"; then
    TARGET="$abs_target"
  fi
else
  if ! printf '%s' "$TARGET" | grep -q '/' && [ ! -e "$TARGET" ] \
     && { is_near_empty || grep -qF "$BEGIN_MARK" "$TARGET/AGENTS.md" 2>/dev/null; }; then
    echo "error: refusing --target \"$TARGET\": it does not exist and the current directory" >&2
    echo "looks like the project root you want to initialize (empty or already harness-managed)." >&2
    echo "Initialize in place with --target . , or pass an explicit path like ./$TARGET to nest" >&2
    echo "a new project deliberately." >&2
    exit 2
  fi
  mkdir -p "$TARGET"
  TARGET="$(cd "$TARGET" && pwd)"
fi

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

if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/.harness/templates/project/docs/engineering/index.md" ] && [ -d "$SCRIPT_DIR/.harness/skills" ]; then
  # Repo self-hosts its mechanism layer under .harness/ (G1).
  SOURCE_ROOT="$SCRIPT_DIR/.harness"
elif [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/templates/project/docs/engineering/index.md" ] && [ -d "$SCRIPT_DIR/skills" ]; then
  # Legacy repo layout (mechanism layer at repo root).
  SOURCE_ROOT="$SCRIPT_DIR"
else
  command -v curl >/dev/null 2>&1 || { echo "curl is required for remote installation" >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { echo "tar is required for remote installation" >&2; exit 1; }
  TMP_ROOT="$(mktemp -d)"
  ARCHIVE="$TMP_ROOT/source.tar.gz"
  curl -fsSL "https://github.com/$REPO/archive/$REF.tar.gz" -o "$ARCHIVE"
  tar -xzf "$ARCHIVE" -C "$TMP_ROOT"
  SOURCE_ROOT="$(find "$TMP_ROOT" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -f "$SOURCE_ROOT/.harness/templates/project/docs/engineering/index.md" ]; then
    SOURCE_ROOT="$SOURCE_ROOT/.harness"
  fi
  [ -f "$SOURCE_ROOT/templates/project/docs/engineering/index.md" ] || { echo "Installer templates not found in $REPO@$REF" >&2; exit 1; }
fi

managed_copy() {
  src="$1"
  dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    printf 'keep   %s\n' "${dst#$TARGET/}"
    INSTALLED_FILES="$INSTALLED_FILES
$dst"
    return 0
  fi
  cp "$src" "$dst"
  INSTALLED_FILES="$INSTALLED_FILES
$dst"
  printf 'write  %s\n' "${dst#$TARGET/}"
}

write_if_missing() {
  dst="$1"
  content="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    printf 'keep   %s\n' "${dst#$TARGET/}"
    INSTALLED_FILES="$INSTALLED_FILES
$dst"
    return 0
  fi
  printf '%s\n' "$content" > "$dst"
  INSTALLED_FILES="$INSTALLED_FILES
$dst"
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

if [ "$MODE" = "auto" ] && [ "$CHECK" -eq 0 ]; then
  if is_near_empty "$TARGET"; then MODE="init"; else MODE="adopt"; fi
fi

# Resolve and validate skill destinations up front so an unknown --agent
# fails before any file is written.
SKILL_DESTS=()
if [ "$INSTALL_SKILL" -eq 1 ]; then
  SKILL_DESTS=("$TARGET/.harness/skills")
  if [ -n "$AGENTS_LIST" ]; then
    requested=""
    OLD_IFS="$IFS"; IFS=','
    for a in $AGENTS_LIST; do
      a="$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')"
      if [ -z "$a" ]; then continue; fi
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

# Print one status line per required skill x destination and return 0 only
# when every required skill has its SKILL.md in every destination.
check_required_skills() {
  rc=0
  for skill_src in "$SOURCE_ROOT"/skills/*/; do
    [ -d "$skill_src" ] || continue
    skill="$(basename "$skill_src")"
    for dest in "${SKILL_DESTS[@]}"; do
      rel="${dest#"$TARGET"/}"
      if [ -f "$dest/$skill/SKILL.md" ]; then
        printf 'ok         %s\n' "$rel/$skill"
      elif [ -d "$dest/$skill" ]; then
        printf 'incomplete %s (SKILL.md missing)\n' "$rel/$skill"
        rc=1
      else
        printf 'missing    %s\n' "$rel/$skill"
        rc=1
      fi
    done
  done
  return "$rc"
}


# --- Managed-section entry files (AGENTS.md / CLAUDE.md, G1) -------------------
# The installer owns only the marked section of each entry file: it creates
# the file when absent, refreshes the marked section on re-runs, and never
# touches content outside the markers.

AGENTS_SKEL='# Project Agent Entry

This file routes agents working in this repository. The marked section below
is generated and refreshed by the ris-coding-harness installer on every run;
content outside the markers is project-owned and is never modified by the
installer.'

CLAUDE_SKEL='# Claude Code notes

Only the harness-managed pointer below is required; add your own notes
outside the markers.'

build_agents_section() {
  # The repair hint can contain '|' (remote curl|bash form), which breaks
  # s|…|…| replacement — splice it in by line via awk instead of sed.
  hint_tmp="$(mktemp)"
  print_repair_hint | sed 's/^Repair: //' > "$hint_tmp"
  srch_tmp="$(mktemp)"
  if [ "${SEARCH:-zvec}" = "zvec" ]; then
    cat > "$srch_tmp" <<'ROUTING'
**Search routing (zvec is the default fuzzy-search layer)**

- Fuzzy/semantic lookups for code or evidence: `zg query --human "<question>"`.
  On first use run `zg status`, then `zg index` if missing (storage lives in
  `.zvec-grep/`, git-ignored); refresh with `zg index` after large changes.
- Exact string/symbol lookups: native Grep/Glob (or `zg query --rg`).
- Structure, relationships, architecture: `graphify` when `graphify-out/`
  exists; call graphs and blast radius: CodeGraph (`.codegraph/`).
- Verify retrieved evidence with native tools before editing.
ROUTING
  fi
  sed -e "s|@BEGIN@|$BEGIN_MARK|" -e "s|@END@|$END_MARK|" <<'SECTION' | awk -v hint="$hint_tmp" -v search="${SEARCH:-zvec}" -v srchf="$srch_tmp" '$0 == "@REPAIR@" { while ((getline line < hint) > 0) print line; close(hint); next } $0 == "@SEARCH@" { if (search == "zvec") { while ((getline line < srchf) > 0) print line; close(srchf) } next } { print }'
@BEGIN@
## Harness routing (managed by ris-coding-harness — do not edit between the markers)

**Skills (mechanism layer, inside `.harness/`)**

- `.harness/skills/pm-workers-engineering/SKILL.md` — PM-Workers protocol: PM decomposes, Coder TDD, Reviewer adversarial gate. Load role references only when the role is active.
- `.harness/skills/rsi-loop/SKILL.md` — RSI self-improvement loop. In this project it runs in observe-only self-check mode; the full loop runs only in the harness self-hosted repository.
- `.harness/skills/ponytail/SKILL.md` — anti-over-engineering ruleset (vendored, MIT): the simplicity ladder (YAGNI → reuse → stdlib → native → existing dep → one line → minimum). The pm-workers Coder and Reviewer roles reference it; invoke directly for coding-task minimalism.

**Engineering rules (decision layer, outside `.harness/`)**

- Start with `docs/engineering/index.md`; load only task-relevant rule files.
- `decisions/`, `issues/`, `progress/` hold project records — use each `index.md` before reading many child files.
- `evals/results/` receives structured reviewer verdicts.

@SEARCH@

**Harness mechanism boundary**

- `.harness/` holds everything the installer manages: skills, gate policy, manifest, reports. Do not hand-edit; re-run the installer to repair.
- The installer never restructures project source and never overwrites project files outside the managed section of this file.

**Self-check / self-heal**

If a required `SKILL.md` is missing or incomplete, re-run the installer — it only fills what is missing and refreshes this managed section:

@REPAIR@
@END@
SECTION
  rm -f "$hint_tmp" "$srch_tmp"
}

build_claude_section() {
  sed -e "s|@BEGIN@|$BEGIN_MARK|" -e "s|@END@|$END_MARK|" <<'SECTION'
@BEGIN@
## Harness pointer (managed by ris-coding-harness — do not edit between the markers)

This project is managed by ris-coding-harness. The repository-root `AGENTS.md` is the single routing entry (skills, engineering rules, conventions) — read it instead of duplicating rules here. Required skills live under `.harness/skills/`; gate policy under `.harness/.rsi/policy.yaml`; the managed file list is `.harness/manifest.json`.
@END@
SECTION
}

merge_managed() {
  # $1 = target file, $2 = file holding the new section, $3 = skeleton for new files
  file="$1"; section_file="$2"; skeleton="$3"
  if [ ! -f "$file" ]; then
    {
      printf '%s\n\n' "$skeleton"
      cat "$section_file"
      printf '\n'
    } > "$file"
    printf 'write  %s\n' "${file#$TARGET/}"
    INSTALLED_FILES="$INSTALLED_FILES
$file"
    return 0
  fi
  if grep -qF "$BEGIN_MARK" "$file"; then
    # Refresh only the marked section (POSIX awk, no extra dependencies).
    awk -v sect="$section_file" -f - "$file" > "$file.ris-new" <<'AWKPROG' && mv "$file.ris-new" "$file"
$0 == "<!-- ris-coding-harness:begin -->" {
  while ((getline line < sect) > 0) print line
  close(sect)
  skip = 1
  next
}
skip && $0 != "<!-- ris-coding-harness:end -->" { next }
skip && $0 == "<!-- ris-coding-harness:end -->" { skip = 0; next }
{ print }
AWKPROG
    printf 'merge  %s\n' "${file#$TARGET/}"
  else
    {
      cat "$file"
      printf '\n'
      cat "$section_file"
      printf '\n'
    } > "$file.ris-new" && mv "$file.ris-new" "$file"
    printf 'merge  %s\n' "${file#$TARGET/}"
  fi
  INSTALLED_FILES="$INSTALLED_FILES
$file"
}


# --- Legacy layout migration (G1) ----------------------------------------------
# Files identical to the managed source move into .harness/; customized or
# outdated files stay in place and are reported. The installer never deletes
# content it cannot prove is an unmodified managed copy.
migrate_one() {
  # $1 = legacy file, $2 = legacy root prefix, $3 = managed source root, $4 = new root
  f="$1"; lroot="$2"; sroot="$3"; nroot="$4"
  rel="${f#$lroot/}"
  src="$sroot/$rel"
  dst="$nroot/$rel"
  if [ ! -f "$src" ]; then
    printf 'legacy   %s (no managed counterpart; left in place)\n' "${f#$TARGET/}"
    return 0
  fi
  # Only a legacy file BYTE-IDENTICAL to the managed source may be moved or
  # deduplicated; anything else is user content and stays untouched.
  if ! cmp -s "$src" "$f"; then
    if [ -f "$dst" ]; then
      printf 'legacy   %s (differs from managed copy; left in place)\n' "${f#$TARGET/}"
    else
      printf 'legacy   %s (customized; left in place)\n' "${f#$TARGET/}"
    fi
    return 0
  fi
  if [ -f "$dst" ]; then
    rm -f "$f"
  else
    mkdir -p "$(dirname "$dst")"
    mv "$f" "$dst"
    INSTALLED_FILES="$INSTALLED_FILES
$dst"
  fi
  return 0
}

migrate_legacy() {
  migrated=0
  if [ "$INSTALL_SKILL" -eq 1 ] && [ -d "$TARGET/.agents/skills" ]; then
    while IFS= read -r -d '' f; do
      migrate_one "$f" "$TARGET/.agents/skills" "$SOURCE_ROOT/skills" "$TARGET/.harness/skills"
    done < <(find "$TARGET/.agents/skills" -type f -print0 2>/dev/null)
    find "$TARGET/.agents/skills" -depth -type d -empty -delete 2>/dev/null || true
    migrated=1
  fi
  if [ -d "$TARGET/.rsi" ]; then
    while IFS= read -r -d '' f; do
      migrate_one "$f" "$TARGET/.rsi" "$SOURCE_ROOT/templates/project/.rsi" "$TARGET/.harness/.rsi"
    done < <(find "$TARGET/.rsi" -type f -print0 2>/dev/null)
    find "$TARGET/.rsi" -depth -type d -empty -delete 2>/dev/null || true
    migrated=1
  fi
  [ "$migrated" -eq 0 ] || echo "migrate  legacy layout: identical files moved into .harness/; customized files left in place (see legacy lines above)"
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' || echo unknown
  fi
}

write_manifest() {
  man_dir="$TARGET/.harness"
  mkdir -p "$man_dir"
  man="$man_dir/manifest.json"
  tmp="$man.tmp"
  skills_json=""
  for skill_src in "$SOURCE_ROOT"/skills/*/; do
    [ -d "$skill_src" ] || continue
    skills_json="$skills_json\"$(basename "$skill_src")\","
  done
  skills_json="${skills_json%,}"
  dests_json=""
  for d in "${SKILL_DESTS[@]}"; do
    dests_json="$dests_json\"${d#"$TARGET"/}\","
  done
  dests_json="${dests_json%,}"
  entries=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$TARGET"/}"
    h="$(hash_file "$f" 2>/dev/null || echo unknown)"
    if [ -z "$entries" ]; then
      entries="    {\"path\": \"$rel\", \"sha256\": \"$h\"}"
    else
      entries="$entries,
    {\"path\": \"$rel\", \"sha256\": \"$h\"}"
    fi
  done <<EOF_FILES
$INSTALLED_FILES
EOF_FILES
  {
    printf '{\n'
    printf '  \"schema_version\": 1,\n'
    printf '  \"generated_at\": \"%s\",\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf '  \"harness_repo\": \"%s\",\n' "$REPO"
    printf '  \"harness_ref\": \"%s\",\n' "$REF"
    printf '  \"skills\": [%s],\n' "$skills_json"
    printf '  \"agent_destinations\": [%s],\n' "$dests_json"
    printf '  \"files\": [\n%s\n  ]\n' "$entries"
    printf '}\n'
  } > "$tmp" && mv "$tmp" "$man"
  printf 'write  %s\n' "${man#$TARGET/}"
}

print_repair_hint() {
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/install.sh" ]; then
    scope_flag=""
    [ "$SCOPE" = "user" ] && scope_flag=" --scope user"
    agent_flag=""
    [ -n "$AGENTS_LIST" ] && agent_flag=" --agent $AGENTS_LIST"
    echo "Repair: \"$SCRIPT_DIR/install.sh\" --target \"$TARGET\" --mode adopt$scope_flag$agent_flag"
  else
    echo "Repair: curl -fsSL https://raw.githubusercontent.com/$REPO/$REF/install.sh | bash -s -- --target \"$TARGET\" --mode adopt"
  fi
}

if [ "$CHECK" -eq 1 ]; then
  if ! ls -d "$SOURCE_ROOT"/skills/*/ >/dev/null 2>&1; then
    echo "No skills found in $SOURCE_ROOT; cannot verify required skills" >&2
    exit 1
  fi
  echo "Skill check: target=$TARGET scope=$SCOPE"
  check_rc=0
  check_required_skills || check_rc=1
  if [ -f "$TARGET/.harness/.rsi/policy.yaml" ]; then
    printf 'ok         .harness/.rsi/policy.yaml\n'
  else
    printf 'missing    .harness/.rsi/policy.yaml\n'
    check_rc=1
  fi
  if [ -f "$TARGET/AGENTS.md" ] && grep -qF "$BEGIN_MARK" "$TARGET/AGENTS.md"; then
    printf 'ok         AGENTS.md managed section\n'
  else
    printf 'missing    AGENTS.md managed section\n'
    check_rc=1
  fi
  # Legacy layout leftovers are reported, not failed.
  [ -e "$TARGET/.agents/skills" ] && printf 'legacy     .agents/skills (old layout; re-run installer to migrate)\n'
  [ -e "$TARGET/.rsi" ] && printf 'legacy     .rsi/ (old layout; re-run installer to migrate)\n'
  if [ "$check_rc" -eq 0 ]; then
    echo "All required skills present."
    exit 0
  fi
  echo
  echo "Missing or incomplete skills detected."
  print_repair_hint
  exit 1
fi

echo "Project bootstrap: mode=$MODE target=$TARGET"

SECTION_TMP="$(mktemp)"
build_agents_section > "$SECTION_TMP"
merge_managed "$TARGET/AGENTS.md" "$SECTION_TMP" "$AGENTS_SKEL"
build_claude_section > "$SECTION_TMP"
merge_managed "$TARGET/CLAUDE.md" "$SECTION_TMP" "$CLAUDE_SKEL"
rm -f "$SECTION_TMP"
for f in "$SOURCE_ROOT"/templates/project/docs/engineering/*.md; do
  managed_copy "$f" "$TARGET/docs/engineering/$(basename "$f")"
done
PLATFORM_SRC="$SOURCE_ROOT/templates/project/docs/engineering/platform"
if [ -d "$PLATFORM_SRC" ]; then
  while IFS= read -r -d '' f; do
    rel="${f#$PLATFORM_SRC/}"
    managed_copy "$f" "$TARGET/docs/engineering/platform/$rel"
  done < <(find "$PLATFORM_SRC" -type f -print0)
fi

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
    managed_copy "$f" "$TARGET/.harness/.rsi/$rel"
  done < <(find "$RSI_SRC" -type f -print0)
fi

# Distribute the Kimi Code compact-recall hook scripts (PostCompact archive +
# UserPromptSubmit recall). Canonical copies live in the harness repo's own
# scripts/ directory; SOURCE_ROOT may have been re-rooted into .harness.
HOOK_SRC_ROOT="$SOURCE_ROOT"
if [ ! -f "$HOOK_SRC_ROOT/scripts/compact-archive.sh" ]; then
  HOOK_SRC_ROOT="$(cd "$(dirname "$SOURCE_ROOT")" && pwd)"
fi
for name in compact-archive.sh compact-archive.ps1 compact-archive.py \
            session-recall.sh session-recall.ps1 session-recall.py \
            install-kimi-hooks.sh install-kimi-hooks.ps1 \
            install-agent-hooks.py install-agent-hooks.sh install-agent-hooks.ps1 \
            compact-recall.pi.ts compact-recall.opencode.ts; do
  if [ -f "$HOOK_SRC_ROOT/scripts/$name" ]; then
    managed_copy "$HOOK_SRC_ROOT/scripts/$name" "$TARGET/scripts/$name"
  fi
done

# Adapt and install compact-recall hooks for every agent selected via
# --agent (best effort: a failure warns but never fails the install).
if [ -n "$AGENTS_LIST" ]; then
  requested=""
  OLD_IFS="$IFS"; IFS=','
  for a in $AGENTS_LIST; do
    a="$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')"
    [ -n "$a" ] || continue
    if [ "$a" = "all" ]; then
      requested="$requested claude pi kimi opencode codex"
    else
      requested="$requested $a"
    fi
  done
  IFS="$OLD_IFS"
  seen=" "
  for a in $requested; do
    case "$a" in kimi-code) a=kimi ;; agents) continue ;; esac
    case " claude pi kimi opencode codex " in *" $a "*) ;; *) continue ;; esac
    case "$seen" in *" $a "*) continue ;; esac
    seen="$seen$a "
    py=""
    for c in python3 python py; do
      if command -v "$c" >/dev/null 2>&1; then py="$c"; break; fi
    done
    if [ -z "$py" ]; then
      echo "warn: no python interpreter; skipping $a hooks"
      continue
    fi
    echo "hooks  $a"
    "$py" "$TARGET/scripts/install-agent-hooks.py" "$a" --target "$TARGET" --scope "$SCOPE" \
      || echo "warn: $a hook adaptation failed (non-fatal)"
  done
fi

migrate_legacy

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

# compact-recall hook state: archived summaries + per-session recall markers.
mkdir -p "$TARGET/conversations/archive" "$TARGET/conversations/.state"

write_manifest

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

# zvec (zg) local search index
.zvec-grep/

# Environment / secrets
.env
.env.*
!.env.example

# Temporary project artifacts
tmp/*
!tmp/index.md

# compact-recall per-session recall markers (local state)
conversations/.state/

# OS / editor noise
.DS_Store
Thumbs.db
.idea/
.vscode/
GITIGNORE
  echo "write  .gitignore"
else
  echo "keep   .gitignore"
fi

if [ "$GIT_INIT" -eq 1 ]; then
  if command -v git >/dev/null 2>&1; then
  if [ -e "$TARGET/.git" ]; then
      echo "keep   .git"
    else
      if git -C "$TARGET" init -b main >/dev/null 2>&1; then
        :
      else
        git -C "$TARGET" init >/dev/null
      fi
      echo "init   .git"
    fi
  else
    echo "warn   git not found; repository not initialized" >&2
  fi
fi

# --- Environment bootstrap (G6) -------------------------------------------------
# Discovers scripts/setup-env.sh first; otherwise detects ecosystem manifests
# and installs dependencies with the matching package manager. Only repository
# evidence is used — commands are never invented. Everything is recorded in
# .harness/reports/env-report.md. Failures warn by default; --strict-env
# upgrades them to exit code 3.
ENV_REPORT_DIR="$TARGET/.harness/reports"
ENV_REPORT="$ENV_REPORT_DIR/env-report.md"

if [ "$SKIP_ENV" -eq 1 ]; then
  echo "skip   env bootstrap (--skip-env)"
else
  echo
  echo "Environment bootstrap:"
  mkdir -p "$ENV_REPORT_DIR"
  ENV_STATUS=0
  UNKNOWN_COUNT=0
  env_any_manifest=0
  REPORT_BODY=""

  env_note() {
    printf 'note   %s\n' "$1"
    REPORT_BODY="$REPORT_BODY
- note: $1"
  }

  env_unknown() {
    UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
    printf 'unknown %s\n' "$1" >&2
    REPORT_BODY="$REPORT_BODY
- UNKNOWN: $1"
  }

  env_run() {
    label="$1"; shift
    if [ "$DRY_RUN_ENV" -eq 1 ]; then
      printf 'dryrun %s: %s\n' "$label" "$*"
      REPORT_BODY="$REPORT_BODY
- [dry-run] $label: $*"
      return 0
    fi
    printf 'run    %s: %s\n' "$label" "$*"
    started="$(date +%s)"
    if command -v timeout >/dev/null 2>&1; then
      if ( cd "$TARGET" && timeout 600 "$@" ) >/dev/null 2>&1; then rc=0; else rc=$?; fi
    else
      if ( cd "$TARGET" && "$@" ) >/dev/null 2>&1; then rc=0; else rc=$?; fi
    fi
    ended="$(date +%s)"
    REPORT_BODY="$REPORT_BODY
- $label: $* - exit $rc ($((ended - started))s)"
    if [ "$rc" -ne 0 ]; then ENV_STATUS=1; fi
    return 0
  }

  if [ -f "$TARGET/scripts/setup-env.sh" ]; then
    echo "found  scripts/setup-env.sh"
    env_run "setup-env" bash "$TARGET/scripts/setup-env.sh"
  else
    env_note "no scripts/setup-env.sh; falling back to ecosystem detection"
    # Node.js
    if [ -f "$TARGET/package.json" ]; then
      env_any_manifest=1
      if grep -q '"dependencies"\|"devDependencies"' "$TARGET/package.json"; then
        if [ -f "$TARGET/pnpm-lock.yaml" ]; then
          if command -v pnpm >/dev/null 2>&1; then env_run "node (pnpm)" pnpm install --frozen-lockfile; else env_unknown "pnpm not found; cannot install deps from pnpm-lock.yaml"; fi
        elif [ -f "$TARGET/yarn.lock" ]; then
          if command -v yarn >/dev/null 2>&1; then env_run "node (yarn)" yarn --frozen-lockfile; else env_unknown "yarn not found; cannot install deps from yarn.lock"; fi
        elif [ -f "$TARGET/package-lock.json" ]; then
          if command -v npm >/dev/null 2>&1; then env_run "node (npm ci)" npm ci; else env_unknown "npm not found; cannot install deps from package-lock.json"; fi
        else
          if command -v npm >/dev/null 2>&1; then
            env_run "node (npm install)" npm install
            env_unknown "package.json has no lockfile; installed with npm install - review version pinning"
          else
            env_unknown "npm not found; cannot install node dependencies"
          fi
        fi
        if grep -q '"build"[[:space:]]*:' "$TARGET/package.json" && command -v npm >/dev/null 2>&1; then
          env_run "build (npm run build)" npm run build
        fi
      else
        env_note "package.json declares no dependencies; skipping node install"
      fi
    fi
    # Python (requirements.txt)
    if [ -f "$TARGET/requirements.txt" ]; then
      env_any_manifest=1
      vpy=""
      if [ -x "$TARGET/.venv/bin/python" ]; then vpy="$TARGET/.venv/bin/python"
      elif [ -x "$TARGET/.venv/Scripts/python" ]; then vpy="$TARGET/.venv/Scripts/python"
      elif [ -x "$TARGET/.venv/Scripts/python.exe" ]; then vpy="$TARGET/.venv/Scripts/python.exe"
      fi
      if [ -n "$vpy" ]; then
        env_run "python (.venv pip)" "$vpy" -m pip install -r requirements.txt
      else
        env_unknown "requirements.txt found but no .venv; create a venv or provide scripts/setup-env.sh (harness will not create one)"
      fi
    fi
    # Python (pyproject.toml)
    if [ -f "$TARGET/pyproject.toml" ]; then
      env_any_manifest=1
      if [ -f "$TARGET/poetry.lock" ]; then
        if command -v poetry >/dev/null 2>&1; then env_run "python (poetry)" poetry install; else env_unknown "poetry not found; cannot install deps from poetry.lock"; fi
      elif [ -f "$TARGET/uv.lock" ]; then
        if command -v uv >/dev/null 2>&1; then env_run "python (uv)" uv sync; else env_unknown "uv not found; cannot install deps from uv.lock"; fi
      fi
    fi
    # Go / Rust / JVM / CMake
    if [ -f "$TARGET/go.mod" ]; then
      env_any_manifest=1
      if command -v go >/dev/null 2>&1; then env_run "go (mod download)" go mod download; else env_unknown "go not found; cannot fetch go.mod dependencies"; fi
    fi
    if [ -f "$TARGET/Cargo.toml" ]; then
      env_any_manifest=1
      if command -v cargo >/dev/null 2>&1; then env_run "rust (cargo fetch)" cargo fetch; else env_unknown "cargo not found; cannot fetch Cargo.toml dependencies"; fi
    fi
    if [ -f "$TARGET/pom.xml" ]; then
      env_any_manifest=1
      if [ -x "$TARGET/mvnw" ]; then
        env_run "maven (mvnw)" ./mvnw -B -q -DskipTests dependency:resolve
      elif command -v mvn >/dev/null 2>&1; then
        env_run "maven (mvn)" mvn -B -q -DskipTests dependency:resolve
      else
        env_unknown "maven not found and no mvnw wrapper; install Maven or add a mvnw wrapper to resolve pom.xml dependencies"
      fi
    fi
    if [ -f "$TARGET/build.gradle" ] || [ -f "$TARGET/build.gradle.kts" ]; then
      env_any_manifest=1
      if [ -x "$TARGET/gradlew" ]; then
        env_run "gradle (gradlew)" ./gradlew dependencies
      elif command -v gradle >/dev/null 2>&1; then
        env_run "gradle" gradle dependencies
      else
        env_unknown "gradle not found and no gradlew wrapper; cannot resolve gradle dependencies"
      fi
    fi
    if [ -f "$TARGET/CMakeLists.txt" ]; then
      env_any_manifest=1
      if [ -f "$TARGET/vcpkg.json" ] || [ -f "$TARGET/conanfile.txt" ] || [ -f "$TARGET/conanfile.py" ]; then
        env_unknown "CMakeLists.txt found with vcpkg/conan manifests; toolchain choice needs human input (provide scripts/setup-env.sh)"
      elif command -v cmake >/dev/null 2>&1; then
        env_run "cmake (configure)" cmake -S . -B build
      else
        env_unknown "cmake not found; cannot configure CMakeLists.txt"
      fi
    fi
    if [ "$env_any_manifest" -eq 0 ]; then
      env_note "no dependency manifests detected (package.json / requirements.txt / go.mod etc.)"
    fi
  fi

  # Workspace search provisioning (zvec/zg) — on by default via --search zvec.
  # The CLI is installed when missing (npm channel); the index itself is
  # deferred to the first fuzzy search per the AGENTS.md search routing.
  if [ "$SEARCH" = "zvec" ]; then
    if command -v zg >/dev/null 2>&1; then
      zg_ver="$(zg version 2>/dev/null | head -n 1 || true)"
      env_note "zvec (zg ${zg_ver:-unknown}) available; index builds on first fuzzy search (see AGENTS.md search routing)"
    elif command -v npm >/dev/null 2>&1; then
      env_run "zvec install (npm -g @zvec/zvec-grep)" npm install -g "@zvec/zvec-grep"
      if command -v zg >/dev/null 2>&1; then
        env_note "zvec installed; index builds on first fuzzy search (see AGENTS.md search routing)"
      else
        env_unknown "zvec install ran but zg is still not on PATH; check the npm global bin directory"
      fi
    else
      env_unknown "zvec (zg) not found and npm unavailable; install @zvec/zvec-grep to enable the default fuzzy-search layer"
    fi
  fi

  if [ "$ENV_STATUS" -eq 1 ]; then report_result="failed"; else report_result="ok"; fi
  if [ "$DRY_RUN_ENV" -eq 1 ]; then report_mode="dry-run"; else report_mode="apply"; fi
  {
    echo "# Environment Bootstrap Report"
    echo
    echo "- date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- target: $TARGET"
    echo "- mode: $report_mode"
    echo "- result: $report_result"
    echo "- unknown_count: $UNKNOWN_COUNT"
    echo
    echo "## Actions"
    printf '%s\n' "$REPORT_BODY"
  } > "$ENV_REPORT"
  echo "report $ENV_REPORT"

  if [ "$STRICT_ENV" -eq 1 ] && [ "$ENV_STATUS" -eq 1 ]; then
    echo "strict-env: environment bootstrap failed" >&2
    exit 3
  fi
fi

echo
echo "Bootstrap complete."
echo "Next: fill docs/engineering/index.md and only the rule files relevant to this project."
echo "Agent entry: AGENTS.md (managed section) + CLAUDE.md"
echo "Mechanism: .harness/ (skills, policy, manifest, reports)"
if [ "$INSTALL_SKILL" -eq 1 ]; then
  echo
  echo "Required skills:"
  if ! check_required_skills; then
    echo "warn   some skills are still missing; re-run the installer to repair" >&2
  fi
fi
