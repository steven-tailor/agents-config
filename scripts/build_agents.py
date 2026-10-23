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

Codex `name` uses underscores instead of hyphens. Codex ignores `sandbox_mode`
in agent files (agents inherit the parent session's sandbox), so none is set.

Generated files are tracked by hash in build/<target>/manifest.json. A file
changed outside the generator (e.g. edited by the tool through its symlink) is
kept and reported as `kept <file>` instead of being overwritten; pass --force to
overwrite. Stale generated files are removed only if unchanged.

Usage: build_agents.py [--target claude|codex ...] [--out DIR] [--force]
"""

import argparse
import hashlib
import json
import re
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE_DIR = REPO / "agents"
TARGETS = ("claude", "codex")
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
    fields = {
        "name": meta["name"].replace("-", "_"),
        "description": meta["description"],
    }
    if "effort" in meta:
        fields["model_reasoning_effort"] = meta["effort"]
    fields.update(meta.get("codex", {}))

    # Keep the conventional key order: identity, model, then the rest.
    order = ["name", "description", "model", "model_reasoning_effort"]
    keys = [k for k in order if k in fields] + [k for k in fields if k not in order]
    lines = [f"{key} = {toml_value(fields[key])}" for key in keys]

    instructions = body_for(body, "codex").replace("\\", "\\\\").replace('"""', '""\\"')
    lines.append(f'developer_instructions = """\n{instructions}"""')
    return "\n".join(lines) + "\n"


RENDERERS = {"claude": (render_claude, ".md"), "codex": (render_codex, ".toml")}


def digest(data):
    return hashlib.sha256(data.encode()).hexdigest()


def write_outputs(out_dir, files, force):
    """Write {filename: content}, never clobbering files changed by others.

    Returns the names of files that were kept because they changed outside
    the generator.
    """
    manifest_path = out_dir.parent / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else None
    out_dir.mkdir(parents=True, exist_ok=True)

    def ours(path):
        # Without a manifest (older builds) nothing is known to be ours, so
        # only files identical to the new output are rewritten.
        return manifest is not None and manifest.get(path.name) == digest(path.read_text())

    for path in out_dir.iterdir():
        if path.name not in files and manifest and path.name in manifest and ours(path):
            path.unlink()

    kept, new_manifest = [], {}
    for name, content in files.items():
        path = out_dir / name
        if path.exists() and not force and not ours(path) and path.read_text() != content:
            kept.append(name)
            if manifest and name in manifest:
                new_manifest[name] = manifest[name]
            continue
        path.write_text(content)
        new_manifest[name] = digest(content)

    manifest_path.write_text(json.dumps(new_manifest, indent=2, sort_keys=True) + "\n")
    return kept


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--target", action="append", choices=TARGETS)
    parser.add_argument("--out", type=Path, default=REPO / "build")
    parser.add_argument("--force", action="store_true", help="overwrite changed files")
    args = parser.parse_args()

    sources = sorted(SOURCE_DIR.glob("*.md"))
    parsed = [(path.stem, *parse(path)) for path in sources]

    for target in args.target or TARGETS:
        render, ext = RENDERERS[target]
        out_dir = args.out / target / "agents"
        files = {f"{stem}{ext}": render(meta, body) for stem, meta, body in parsed}
        for name in write_outputs(out_dir, files, args.force):
            print(f"kept {name}")
        print(f"{target}: {len(files)} agents -> {out_dir}")


if __name__ == "__main__":
    main()
