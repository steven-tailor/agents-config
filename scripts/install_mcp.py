#!/usr/bin/env python3
"""Add the MCP servers listed in mcp.toml to one tool.

Never reinstalls or updates: a server is skipped when the tool already has one
with that name, however it was added. Claude Code gets them in user scope.
Prints one line per entry:

    installed <name>
    present <name>
    skipped <name>: <reason>
    failed <name>: <reason>

Usage: install_mcp.py --tool claude|codex [--dry-run]
"""

import argparse
import json
import shutil
import subprocess
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONFIG = REPO / "mcp.toml"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True,
                          stdin=subprocess.DEVNULL).stdout


def error(e):
    lines = (getattr(e, "stderr", "") or str(e)).strip().splitlines()
    return lines[-1] if lines else type(e).__name__


def has(tool, name, codex_names):
    if tool == "codex":
        return name in codex_names
    return subprocess.run(["claude", "mcp", "get", name], capture_output=True,
                          stdin=subprocess.DEVNULL).returncode == 0


def add_args(tool, name, spec):
    command = spec.get(f"{tool}_command", spec.get("command"))
    if tool == "claude":
        if "url" in spec:
            return ["claude", "mcp", "add", "--scope", "user", "--transport", "http", name, spec["url"]]
        return ["claude", "mcp", "add", "--scope", "user", name, "--", *command]
    if "url" in spec:
        return ["codex", "mcp", "add", name, "--url", spec["url"]]
    return ["codex", "mcp", "add", name, "--", *command]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tool", required=True, choices=("claude", "codex"))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    tool = args.tool
    config = tomllib.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    if not shutil.which(tool):
        for name in config:
            print(f"skipped {name}: no {tool} on PATH")
        return
    codex_names = set()
    if tool == "codex":
        try:
            codex_names = {s["name"] for s in json.loads(run("codex", "mcp", "list", "--json"))}
        except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as e:
            for name in config:
                print(f"failed {name}: can't list MCP servers · {error(e)}")
            return

    for name, spec in config.items():
        if has(tool, name, codex_names):
            print(f"present {name}")
            continue
        missing = [c for c in spec.get("requires", []) if not shutil.which(c)]
        if missing:
            print(f"skipped {name}: no {', '.join(missing)} on PATH")
            continue
        if args.dry_run:
            print(f"installed {name}")
            continue
        try:
            if spec.get("warm"):
                run(*spec["warm"])
            run(*add_args(tool, name, spec))
            print(f"installed {name}")
        except (subprocess.CalledProcessError, OSError) as e:
            print(f"failed {name}: {error(e)}")


if __name__ == "__main__":
    main()
