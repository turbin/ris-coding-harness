#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Install the compact-recall hooks (PostCompact archive + recall briefing)
for a coding agent, adapted to each agent's hook mechanism:

  kimi     user-level ~/.kimi-code/config.toml [[hooks]] managed block;
           hook scripts hosted in ~/.kimi-code/hooks/ (no project path dep)
  claude   .claude/settings.json (project) or ~/.claude/settings.json (user)
  codex    .codex/hooks.json (project) or ~/.codex/hooks.json (user)
  pi       .pi/extensions/compact-recall.ts (or ~/.pi/agent/extensions/)
  opencode .opencode/plugins/compact-recall.ts (or ~/.config/opencode/plugins/)

Usage:
  install-agent-hooks.py <agent> [--target PATH] [--scope project|user]
  install-agent-hooks.py kimi --check   verify installed state (hosted scripts
                                        vs repo sources + managed block target)

Idempotent: previously managed entries are replaced; foreign config entries
are left untouched. Exit codes: 0 installed/ok, 1 error/drift, 2 usage error.
"""
import argparse
import hashlib
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError, OSError):
        pass

AGENTS = ("kimi", "claude", "codex", "pi", "opencode")
MANAGED_MARK = "ris-coding-harness compact-recall"
KIMI_MARK_BEGIN = "# >>> managed by ris-coding-harness: compact-recall"
KIMI_MARK_END = "# <<< managed by ris-coding-harness: compact-recall"
KIMI_HOOK_FILES = (
    "compact-archive.sh", "compact-archive.ps1", "compact-archive.py",
    "session-recall.sh", "session-recall.ps1", "session-recall.py",
)

IS_WINDOWS = os.name == "nt"
SCRIPT_DIR = Path(__file__).resolve().parent


def log(msg):
    print(f"[install-agent-hooks] {msg}")


def fwd(path):
    """Windows-friendly forward-slash path for config files."""
    return str(path).replace("\\", "/")


def managed_command(*needles):
    def is_ours(handler):
        cmd = str(handler.get("command", "")) + str(handler.get("commandWindows", ""))
        return any(n in cmd for n in needles)
    return is_ours


def merge_hook_groups(existing_groups, is_ours, new_group):
    """Filter out our previous entries from a claude/codex hook group list and
    append the freshly built managed group."""
    kept = []
    for group in existing_groups or []:
        handlers = [h for h in group.get("hooks", []) if not is_ours(h)]
        if handlers or not group.get("hooks"):
            g = dict(group)
            g["hooks"] = handlers
            kept.append(g)
    kept.append(new_group)
    return kept


def atomic_write_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".hooks-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as out:
            out.write(text)
        os.replace(tmp, path)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def atomic_write_json(path, data):
    atomic_write_text(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------- kimi

def install_kimi(root, scope):
    # Hooks are user-global (one config.toml), so the registered commands must
    # not live inside any single project: host the scripts under
    # $KIMI_CODE_HOME/hooks/. The scripts resolve the project from the hook
    # payload cwd, so a user-level copy serves every project.
    del root, scope
    home = Path(os.environ.get("KIMI_CODE_HOME") or (Path.home() / ".kimi-code"))
    home.mkdir(parents=True, exist_ok=True)
    hooks_dir = home / "hooks"
    hooks_dir.mkdir(parents=True, exist_ok=True)
    copied = 0
    for name in KIMI_HOOK_FILES:
        src = SCRIPT_DIR / name
        if not src.is_file():
            log(f"kimi: warn: missing {src}; re-run the ris-coding-harness installer to refresh hook scripts")
            continue
        shutil.copy2(src, hooks_dir / name)
        copied += 1
    if copied == 0:
        log("kimi: error: no hook scripts found next to this installer; nothing registered")
        return 1
    cfg = home / "config.toml"
    cfg.touch(exist_ok=True)
    if IS_WINDOWS:
        cmd_archive = f'powershell -NoProfile -ExecutionPolicy Bypass -File "{fwd(hooks_dir)}/compact-archive.ps1"'
        cmd_recall = f'powershell -NoProfile -ExecutionPolicy Bypass -File "{fwd(hooks_dir)}/session-recall.ps1"'
    else:
        cmd_archive = f'bash "{hooks_dir}/compact-archive.sh"'
        cmd_recall = f'bash "{hooks_dir}/session-recall.sh"'
    block = [
        KIMI_MARK_BEGIN,
        "# Archive each context compaction into <project>/conversations/ and inject a",
        "# recall briefing on the first prompt of every session. Managed by",
        "# ris-coding-harness — edit via scripts/install-agent-hooks.py, not by hand.",
        "[[hooks]]",
        'event = "PostCompact"',
        f"command = '{cmd_archive}'",
        "timeout = 10",
        "",
        "[[hooks]]",
        'event = "UserPromptSubmit"',
        f"command = '{cmd_recall}'",
        "timeout = 10",
        KIMI_MARK_END,
    ]
    lines = cfg.read_text(encoding="utf-8", errors="replace").splitlines()
    kept, skip = [], False
    for line in lines:
        if line.strip() == KIMI_MARK_BEGIN:
            skip = True
            continue
        if line.strip() == KIMI_MARK_END:
            skip = False
            continue
        if not skip:
            kept.append(line)
    kept.extend(block)
    atomic_write_text(cfg, "\n".join(kept) + "\n")
    log(f"kimi: hooks registered in {cfg} (scripts hosted in {hooks_dir})")
    log("kimi: run /reload in the TUI (or restart) to activate hook changes")
    log("kimi: next /compact (or auto compaction) will archive into <project>/conversations/")


def check_kimi():
    """Verify installed state instead of installing: hosted scripts must
    byte-match the repo sources and the managed block must point at the
    user-level hooks dir. The config scan is scoped to the managed block so
    foreign hooks that merely mention compact-archive stay out of the report.
    Exit 0 clean, 1 drift. An installing run silently repairs drift, so this
    never repairs — it only reports."""
    home = Path(os.environ.get("KIMI_CODE_HOME") or (Path.home() / ".kimi-code"))
    hooks_dir = home / "hooks"
    problems = []
    for name in KIMI_HOOK_FILES:
        src, dst = SCRIPT_DIR / name, hooks_dir / name
        if not src.is_file():
            problems.append(f"source missing: {src}")
            continue
        if not dst.is_file():
            problems.append(f"hosted copy missing: {dst} (re-run: install-agent-hooks.py kimi)")
            continue
        if hashlib.sha256(src.read_bytes()).hexdigest() != hashlib.sha256(dst.read_bytes()).hexdigest():
            problems.append(f"hosted copy drifted from repo: {dst} (re-run: install-agent-hooks.py kimi)")
    cfg = home / "config.toml"
    text = cfg.read_text(encoding="utf-8", errors="replace") if cfg.is_file() else ""
    block_lines, in_block = [], False
    for line in text.splitlines():
        if line.strip() == KIMI_MARK_BEGIN:
            in_block = True
            continue
        if line.strip() == KIMI_MARK_END:
            in_block = False
            continue
        if in_block:
            block_lines.append(line)
    if not block_lines:
        problems.append(f"managed block missing in {cfg}")
    else:
        block_text = "\n".join(block_lines)
        for event in ("PostCompact", "UserPromptSubmit"):
            if f'event = "{event}"' not in block_text:
                problems.append(f"managed block missing event {event}")
        for needle in ("compact-archive", "session-recall"):
            line = next((l for l in block_lines if needle in l and "command" in l), "")
            if not line:
                problems.append(f"managed command missing for {needle}")
            elif fwd(hooks_dir).lower() not in line.lower():
                problems.append(f"managed command not hosted in {hooks_dir}: {line.strip()}")
    if problems:
        for p in problems:
            log(f"kimi check: DRIFT {p}")
        return 1
    log("kimi check: ok (hosted scripts match repo; managed block points at user-level hooks dir)")
    return 0


# ---------------------------------------------------------------- claude

def install_claude(root, scope):
    cfg = (root / ".claude/settings.json") if scope == "project" else (Path.home() / ".claude/settings.json")
    data = {}
    if cfg.is_file():
        try:
            data = json.loads(cfg.read_text(encoding="utf-8", errors="replace"))
        except ValueError as exc:
            log(f"claude: {cfg} is not valid JSON ({exc}); leaving it untouched")
            return 1
    hooks = data.setdefault("hooks", {})
    ours = managed_command("compact-archive", "session-recall")
    archive_group = {
        "matcher": "manual|auto",
        "hooks": [
            {
                "type": "command",
                "command": 'bash "$CLAUDE_PROJECT_DIR/scripts/compact-archive.sh" --flavor claude',
                "timeout": 10,
            }
        ],
    }
    recall_group = {
        "hooks": [
            {
                "type": "command",
                "command": 'bash "$CLAUDE_PROJECT_DIR/scripts/session-recall.sh"',
                "timeout": 10,
            }
        ]
    }
    hooks["PostCompact"] = merge_hook_groups(hooks.get("PostCompact"), ours, archive_group)
    hooks["UserPromptSubmit"] = merge_hook_groups(hooks.get("UserPromptSubmit"), ours, recall_group)
    atomic_write_json(cfg, data)
    log(f"claude: hooks registered in {cfg} (PostCompact archive + UserPromptSubmit recall)")
    log("claude: requires Git Bash on Windows (default hook shell); stdout of UserPromptSubmit is injected as context")


# ---------------------------------------------------------------- codex

def install_codex(root, scope):
    cfg = (root / ".codex/hooks.json") if scope == "project" else (Path.home() / ".codex/hooks.json")
    data = {"description": "Optional lifecycle hooks for this workspace.", "hooks": {}}
    if cfg.is_file():
        try:
            loaded = json.loads(cfg.read_text(encoding="utf-8", errors="replace"))
            if isinstance(loaded, dict):
                data.update(loaded)
        except ValueError as exc:
            log(f"codex: {cfg} is not valid JSON ({exc}); leaving it untouched")
            return 1
    hooks = data.setdefault("hooks", {})
    ours = managed_command("compact-archive", "session-recall")
    if IS_WINDOWS:
        archive_cmd = f'python "{fwd(root)}/scripts/compact-archive.py" --flavor codex'
        recall_cmd = f'python "{fwd(root)}/scripts/session-recall.py"'
    else:
        archive_cmd = f'bash "{root}/scripts/compact-archive.sh" --flavor codex'
        recall_cmd = f'bash "{root}/scripts/session-recall.sh"'
    archive_group = {
        "matcher": "manual|auto",
        "hooks": [
            {
                "type": "command",
                "command": archive_cmd,
                "timeout": 30,
                "async": True,
                "statusMessage": "Archiving compaction summary",
            }
        ],
    }
    recall_group = {
        "hooks": [
            {
                "type": "command",
                "command": recall_cmd,
                "timeout": 10,
                "additionalContextLimit": 5000,
            }
        ]
    }
    hooks["PostCompact"] = merge_hook_groups(hooks.get("PostCompact"), ours, archive_group)
    hooks["UserPromptSubmit"] = merge_hook_groups(hooks.get("UserPromptSubmit"), ours, recall_group)
    atomic_write_json(cfg, data)
    log(f"codex: hooks registered in {cfg}")
    log("codex: review and trust them once with /hooks in the CLI (non-managed hooks are skipped until trusted)")


# ------------------------------------------------------- pi / opencode

def install_ts_adapter(root, scope, agent, src_name, rel_project, rel_user, extra_note=None):
    src = SCRIPT_DIR / src_name
    if not src.is_file():
        log(f"{agent}: missing {src}; run the ris-coding-harness installer first")
        return 1
    dst = (root / rel_project) if scope == "project" else (Path.home() / rel_user)
    if dst.is_file():
        head = dst.read_text(encoding="utf-8", errors="replace")[:2048]
        if MANAGED_MARK not in head and "compact-recall" not in head:
            log(f"{agent}: keep {dst} (exists, not managed by harness)")
            return 0
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(src.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")
    log(f"{agent}: adapter installed at {dst}")
    if extra_note:
        log(f"{agent}: {extra_note}")
    return 0


def install_pi(root, scope):
    note = None
    if scope == "project":
        note = ("project extensions require pi project trust — approve the prompt interactively, "
                "or set defaultProjectTrust to always / run with --approve for headless use")
    return install_ts_adapter(
        root, scope, "pi", "compact-recall.pi.ts",
        ".pi/extensions/compact-recall.ts", ".pi/agent/extensions/compact-recall.ts", note,
    )


def install_opencode(root, scope):
    return install_ts_adapter(
        root, scope, "opencode", "compact-recall.opencode.ts",
        ".opencode/plugins/compact-recall.ts", ".config/opencode/plugins/compact-recall.ts",
    )


INSTALLERS = {
    "kimi": install_kimi,
    "claude": install_claude,
    "codex": install_codex,
    "pi": install_pi,
    "opencode": install_opencode,
}


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("agent", choices=AGENTS)
    ap.add_argument("--target", default=".")
    ap.add_argument("--scope", choices=("project", "user"), default="project")
    ap.add_argument("--check", action="store_true",
                    help="verify installed state instead of installing (kimi only)")
    args, _unknown = ap.parse_known_args()

    if args.check:
        if args.agent == "kimi":
            return check_kimi()
        log(f"{args.agent}: --check is not supported yet")
        return 2

    target = Path(args.target).resolve()
    if not target.is_dir():
        log(f"error: target not found: {target}")
        return 1
    rc = INSTALLERS[args.agent](target, args.scope)
    return rc or 0


if __name__ == "__main__":
    sys.exit(main())
