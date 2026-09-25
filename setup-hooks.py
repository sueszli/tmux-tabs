#!/usr/bin/env python3
"""Add tabs status hooks to the existing user-level agent settings."""

import json
import os
import re
import shlex
import shutil
import sys
import tempfile
from pathlib import Path


def add_hooks(path, agent, events, helper):
    path.parent.mkdir(parents=True, exist_ok=True)
    config = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(config, dict):
        raise ValueError(f"{path} must contain a JSON object")
    hooks = config.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError(f"{path}: hooks must be a JSON object")

    changed = False
    for event, matcher, action in events:
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            raise ValueError(f"{path}: {event} must be a JSON array")
        command = f"{shlex.quote(str(helper))} {agent} {action}"
        if any(
            item.get("command") == command
            for group in groups if isinstance(group, dict)
            for item in group.get("hooks", []) if isinstance(item, dict)
        ):
            continue
        group = {"hooks": [{"type": "command", "command": command, "timeout": 3}]}
        if matcher:
            group["matcher"] = matcher
        groups.append(group)
        changed = True

    if not changed:
        return
    if path.exists():
        backup = path.with_name(path.name + ".before-tabs")
        if not backup.exists():
            shutil.copy2(path, backup)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as staged:
        json.dump(config, staged, indent=2)
        staged.write("\n")
        staged_path = Path(staged.name)
    os.chmod(staged_path, mode)
    os.replace(staged_path, path)
    print(f"configured {agent} status hooks in {path}")


def add_codex_hooks(home, events, helper):
    config_path = home / ".codex" / "config.toml"
    json_path = home / ".codex" / "hooks.json"
    config_text = config_path.read_text() if config_path.exists() else ""
    inline_hooks = re.search(r"(?m)^\s*\[\[?hooks(?:\.|\])", config_text) is not None

    if inline_hooks:
        marker = "# BEGIN tabs-agent-status"
        if marker not in config_text:
            backup = config_path.with_name(config_path.name + ".before-tabs")
            if not backup.exists():
                shutil.copy2(config_path, backup)
            lines = ["", marker]
            for event, matcher, action in events:
                command = f"{shlex.quote(str(helper))} codex {action}"
                lines.append(f"[[hooks.{event}]]")
                if matcher:
                    lines.append(f"matcher = {json.dumps(matcher)}")
                lines.append(
                    f"hooks = [{{ type = \"command\", command = {json.dumps(command)}, timeout = 3 }}]"
                )
                lines.append("")
            lines.append("# END tabs-agent-status")
            with config_path.open("a") as output:
                output.write("\n".join(lines) + "\n")
            print(f"configured codex status hooks in {config_path}")

        # An older tabs setup may have written the same hooks to hooks.json.
        if json_path.exists():
            data = json.loads(json_path.read_text())
            groups = data.get("hooks", {}) if isinstance(data, dict) else {}
            commands = [
                item.get("command", "")
                for values in groups.values() if isinstance(values, list)
                for group in values if isinstance(group, dict)
                for item in group.get("hooks", []) if isinstance(item, dict)
            ]
            if isinstance(data, dict) and set(data) == {"hooks"} and commands and all(
                str(helper) in command for command in commands
            ):
                json_path.unlink()
        return

    add_hooks(json_path, "codex", events, helper)


def main():
    helper = Path(sys.argv[1]).resolve(strict=True)
    home = Path.home()
    claude_events = [
        ("SessionStart", "startup|resume", "SessionStart"),
        ("UserPromptSubmit", None, "UserPromptSubmit"),
        ("PermissionRequest", None, "PermissionRequest"),
        ("Notification", "^(permission_prompt|idle_prompt)$", "PermissionRequest"),
        ("PreToolUse", "^AskUserQuestion$", "PreQuestion"),
        ("Elicitation", None, "PreQuestion"),
        ("ElicitationResult", None, "PostQuestion"),
        ("PostToolUse", None, "PostToolUse"),
        ("PostToolUseFailure", None, "PostToolUseFailure"),
        ("Stop", None, "Stop"),
        ("StopFailure", None, "StopFailure"),
        ("SessionEnd", None, "SessionEnd"),
    ]
    codex_events = [
        ("SessionStart", "startup|resume", "SessionStart"),
        ("UserPromptSubmit", None, "UserPromptSubmit"),
        ("PermissionRequest", None, "PermissionRequest"),
        ("PostToolUse", None, "PostToolUse"),
        ("Stop", None, "Stop"),
        ("Interrupt", None, "Interrupt"),
        ("SessionEnd", None, "SessionEnd"),
    ]
    add_hooks(home / ".claude" / "settings.json", "claude", claude_events, helper)
    add_codex_hooks(home, codex_events, helper)


if __name__ == "__main__":
    main()
