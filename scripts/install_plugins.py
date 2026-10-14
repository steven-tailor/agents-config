#!/usr/bin/env python3
"""Install the plugins listed in plugins.toml into one tool.

Each entry installs as a plugin through the tool's CLI (`<tool>`), or as
skills through skills.sh (`<tool>_skills_sh`, needs npx). Never reinstalls: an
entry is skipped when the tool already has the plugin, or when one of its
marker `skills` is in one of the given skills dirs (installed another way).
Nothing is updated here: plugins update themselves, skills.sh copies don't.
Prints one line per entry:

    installed <name>
    present <name>
    skipped <name>: <reason>
    failed <name>: <reason>

Usage: install_plugins.py --tool claude|codex [--skills-dir DIR ...] [--dry-run]
"""

import argparse
import json
import os
import shutil
import subprocess
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONFIG = REPO / "plugins.toml"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True,
                          stdin=subprocess.DEVNULL).stdout


def installed(tool):
    """Ids (plugin@marketplace) the tool has installed."""
    if tool == "claude":
        return {p["id"] for p in json.loads(run("claude", "plugin", "list", "--json"))}
    ids = set()
    for line in run("codex", "plugin", "list").splitlines():
        parts = line.split()
        if len(parts) > 1 and "@" in parts[0] and parts[1].startswith("installed"):
            ids.add(parts[0])
    return ids


def marketplaces(tool):
    if tool == "claude":
        return {m["name"] for m in json.loads(run("claude", "plugin", "marketplace", "list", "--json"))}
    lines = run("codex", "plugin", "marketplace", "list").splitlines()[1:]
    return {line.split()[0] for line in lines if line.strip()}


def install_skills_sh(tool, source):
    # Global, every skill in the repo, no prompts, no telemetry.
    subprocess.run(["npx", "-y", "skills@latest", "add", source, "-g", "-a", tool, "-s", "*", "-y"],
                   check=True, capture_output=True, text=True, stdin=subprocess.DEVNULL,
                   env={**os.environ, "DISABLE_TELEMETRY": "1"})


def install(tool, plugin, spec):
    """Add the plugin's marketplace if the tool doesn't know it, then install."""
    source = spec.get(f"{tool}_marketplace")
    if source and plugin.split("@", 1)[1] not in marketplaces(tool):
        run(tool, "plugin", "marketplace", "add", source)
    if tool == "claude":
        run("claude", "plugin", "install", plugin)
    else:
        run("codex", "plugin", "add", plugin)


def error(e):
    lines = (getattr(e, "stderr", "") or str(e)).strip().splitlines()
    return lines[-1] if lines else type(e).__name__


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tool", required=True, choices=("claude", "codex"))
    parser.add_argument("--skills-dir", action="append", type=Path, default=[])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    tool = args.tool
    config = tomllib.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    entries = {name: spec for name, spec in config.items()
               if spec.get(tool) or spec.get(f"{tool}_skills_sh")}
    have = None

    for name, spec in entries.items():
        plugin, skills_sh = spec.get(tool), spec.get(f"{tool}_skills_sh")
        cli = tool if plugin else "npx"
        if not shutil.which(cli):
            print(f"skipped {name}: no {cli} on PATH")
            continue
        if plugin and have is None:
            try:
                have = installed(tool)
            except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as e:
                print(f"failed {name}: can't list plugins · {error(e)}")
                continue
        if plugin and plugin in have:
            print(f"present {name}")
            continue
        marker = next((d / s for s in spec.get("skills", []) for d in args.skills_dir
                       if (d / s).exists()), None)
        if marker:
            print(f"{'skipped' if plugin else 'present'} {name}: already in {marker.parent}")
            continue
        if args.dry_run:
            print(f"installed {name}")
            continue
        try:
            if plugin:
                install(tool, plugin, spec)
            else:
                install_skills_sh(tool, skills_sh)
            print(f"installed {name}")
        except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError) as e:
            print(f"failed {name}: {error(e)}")


if __name__ == "__main__":
    main()
