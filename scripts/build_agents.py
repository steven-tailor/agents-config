#!/usr/bin/env python3
"""Generate Claude Code and Codex agent files from the single source in agents/.

Source format (agents/<name>.md):

    +++
    name = "reviewer"
    description = "..."
    effort = "high"            # -> Claude `effort`, Codex `model_reasoning_effort`

    [claude]                   # copied verbatim into Claude frontmatter
    tools = "Read, Grep, Glob, Bash"
    permissionMode = "plan"

    [codex]                    # copied verbatim into Codex TOML
    model = "gpt-5.6-terra"
    +++
    Shared instructions.

    <!-- claude -->
    Only in the Claude version.
    <!-- /claude -->
    <!-- codex -->
    Only in the Codex version.
    <!-- /codex -->

Codex defaults: `name` uses underscores instead of hyphens; `sandbox_mode` is
`workspace-write` when Claude tools include an editing tool, else `read-only`.

Usage: build_agents.py [--target claude|codex ...] [--out DIR]
"""

import argparse
import json
import re
import shutil
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO / "agents"
TARGETS = ("claude", "codex")
EDIT_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}
BLOCK = re.compile(r"^<!-- (/?)(claude|codex) -->[ \t]*\n?", re.MULTILINE)


def parse(path):
    text = path.read_text()
    match = re.match(r"\+\+\+\n(.*?)\n\+\+\+\n?(.*)", text, re.DOTALL)
    if not match:
        sys.exit(f"{path}: missing +++ TOML frontmatter")
    meta = tomllib.loads(match.group(1))
    for key in ("name", "description"):
        if key not in meta:
            sys.exit(f"{path}: missing `{key}`")
    return meta, match.group(2)


def body_for(body, target):
    """Keep shared text and `target` blocks, drop the other target's blocks."""
    out, pos, current = [], 0, None
    for m in BLOCK.finditer(body):
        closing, tag = m.group(1) == "/", m.group(2)
        if current in (None, target):
            out.append(body[pos:m.start()])
        if closing:
            if current != tag:
                sys.exit(f"unbalanced <!-- /{tag} -->")
            current = None
        else:
            if current:
                sys.exit(f"nested <!-- {tag} --> inside <!-- {current} -->")
            current = tag
        pos = m.end()
    if current:
        sys.exit(f"unclosed <!-- {current} -->")
    out.append(body[pos:])
    text = re.sub(r"\n{3,}", "\n\n", "".join(out))
    return text.strip() + "\n"


def yaml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    value = str(value)
    plain = re.fullmatch(r"[A-Za-z0-9_][^:#\n]*", value) and value == value.strip()
    return value if plain else json.dumps(value, ensure_ascii=False)


def render_claude(meta, body):
    fields = {"name": meta["name"], "description": meta["description"]}
    if "effort" in meta:
        fields["effort"] = meta["effort"]
    fields.update(meta.get("claude", {}))

    lines = ["---"]
    for key, value in fields.items():
        if isinstance(value, list):
            lines.append(f"{key}:")
            lines += [f"  - {yaml_value(item)}" for item in value]
        else:
            lines.append(f"{key}: {yaml_value(value)}")
    lines.append("---")
    return "\n".join(lines) + "\n\n" + body_for(body, "claude")


def toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    return json.dumps(str(value), ensure_ascii=False)


def render_codex(meta, body):
    tools = {t.strip() for t in str(meta.get("claude", {}).get("tools", "")).split(",")}
    fields = {
        "name": meta["name"].replace("-", "_"),
        "description": meta["description"],
    }
    if "effort" in meta:
        fields["model_reasoning_effort"] = meta["effort"]
    fields["sandbox_mode"] = "workspace-write" if tools & EDIT_TOOLS else "read-only"
    fields.update(meta.get("codex", {}))

    # Keep the conventional key order: identity, model, then the rest.
    order = ["name", "description", "model", "model_reasoning_effort", "sandbox_mode"]
    keys = [k for k in order if k in fields] + [k for k in fields if k not in order]
    lines = [f"{key} = {toml_value(fields[key])}" for key in keys]

    instructions = body_for(body, "codex").replace("\\", "\\\\").replace('"""', '""\\"')
    lines.append(f'developer_instructions = """\n{instructions}"""')
    return "\n".join(lines) + "\n"


RENDERERS = {"claude": (render_claude, ".md"), "codex": (render_codex, ".toml")}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", action="append", choices=TARGETS)
    parser.add_argument("--out", type=Path, default=REPO / "build")
    args = parser.parse_args()

    sources = sorted(SOURCE_DIR.glob("*.md"))
    parsed = [(path.stem, *parse(path)) for path in sources]

    for target in args.target or TARGETS:
        render, ext = RENDERERS[target]
        out_dir = args.out / target / "agents"
        shutil.rmtree(out_dir, ignore_errors=True)
        out_dir.mkdir(parents=True)
        for stem, meta, body in parsed:
            (out_dir / f"{stem}{ext}").write_text(render(meta, body))
        print(f"{target}: {len(parsed)} agents -> {out_dir.relative_to(REPO)}")


if __name__ == "__main__":
    main()
