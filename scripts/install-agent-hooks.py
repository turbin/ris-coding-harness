#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Install the compact-recall hooks (PostCompact archive + recall briefing)
for a coding agent, adapted to each agent's hook mechanism:

  kimi     user-level ~/.kimi-code/config.toml [[hooks]] managed block
  claude   .claude/settings.json (project) or ~/.claude/settings.json (user)
  codex    .codex/hooks.json (project) or ~/.codex/hooks.json (user)
  pi       .pi/extensions/compact-recall.ts (or ~/.pi/agent/extensions/)
  opencode .opencode/plugins/compact-recall.ts (or ~/.config/opencode/plugins/)

Usage:
  install-agent-hooks.py <agent> [--target PATH] [--scope project|user]

Idempotent: previously managed entries are replaced; foreign config entries
are left untouched. Exit codes: 0 installed, 1 error, 2 usage error.
"""
import argparse
import json
import os
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
    home = Path(os.environ.get("KIMI_CODE_HOME") or (Path.home() / ".kimi-code"))
    home.mkdir(parents=True, exist_ok=True)
    cfg = home / "config.toml"
    cfg.touch(exist_ok=True)
    if IS_WINDOWS:
        cmd_archive = f'powershell -NoProfile -ExecutionPolicy Bypass -File "{fwd(root)}/scripts/compact-archive.ps1"'
        cmd_recall = f'powershell -NoProfile -ExecutionPolicy Bypass -File "{fwd(root)}/scripts/session-recall.ps1"'
    else:
        cmd_archive = f'bash "{root}/scripts/compact-archive.sh"'
        cmd_recall = f'bash "{root}/scripts/session-recall.sh"'
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
    log(f"kimi: hooks registered in {cfg}")
    log("kimi: next /compact (or auto compaction) will archive into <project>/conversations/")


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
    args, _unknown = ap.parse_known_args()

    target = Path(args.target).resolve()
    if not target.is_dir():
        log(f"error: target not found: {target}")
        return 1
    rc = INSTALLERS[args.agent](target, args.scope)
    return rc or 0


if __name__ == "__main__":
    sys.exit(main())
