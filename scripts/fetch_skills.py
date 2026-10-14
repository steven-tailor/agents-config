#!/usr/bin/env python3
"""Fetch the external skills listed in skills.toml into build/external/skills.

Each repo is kept as a shallow, sparse clone in build/external/sources/, moved
to the latest commit of its branch on every run. Skill folders are copied out
of it, so the clones can be reset freely.

Copied skills are tracked by hash in build/external/manifest.json. A skill
changed outside this script (e.g. edited by a tool through its symlink) is kept
and reported as `kept <name>` instead of being overwritten; pass --force to
overwrite. If a repo can't be fetched, the previous copy stays and the skill is
reported as `failed <name>: <reason>`. A skill's `frontmatter` table in
skills.toml overrides keys in its SKILL.md frontmatter. Skills dropped from skills.toml are
removed only if unchanged.

Usage: fetch_skills.py [--force]
"""

import argparse
import os
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONFIG = REPO / "skills.toml"
LOCAL_SKILLS = REPO / "skills"
OUT = REPO / "build" / "external"
SKILLS_DIR = OUT / "skills"
SOURCES_DIR = OUT / "sources"
MANIFEST = OUT / "manifest.json"
FRONTMATTER = re.compile(r"\A---\n(.*?\n)---\n", re.DOTALL)


def load_config():
    skills = tomllib.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    for name, spec in skills.items():
        for key in ("repo", "path"):
            if key not in spec:
                sys.exit(f"skills.toml: [{name}] missing `{key}`")
        if (LOCAL_SKILLS / name).exists():
            sys.exit(f"skills.toml: [{name}] clashes with skills/{name}")
    return skills


def yaml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    return json.dumps(value, ensure_ascii=False)


def override_frontmatter(skill, overrides):
    """Replace or add `key: value` lines in the SKILL.md frontmatter."""
    text = skill.read_text()
    match = FRONTMATTER.match(text)
    if not match:
        raise ValueError("SKILL.md has no --- frontmatter")
    head = match.group(1)
    for key, value in overrides.items():
        line = f"{key}: {yaml_value(value)}\n"
        pattern = re.compile(rf"^{re.escape(key)}:.*\n", re.MULTILINE)
        head = pattern.sub(lambda _: line, head, count=1) if pattern.search(head) else head + line
    skill.write_text(f"---\n{head}---\n" + text[match.end():])


def git(*args, cwd=None):
    # Never wait for credentials: this also runs from the daily update job.
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    subprocess.run(["git", *args], cwd=cwd, env=env, check=True, capture_output=True, text=True)


def source_dir(repo, ref):
    slug = re.sub(r"^\w+://|\.git$", "", repo).strip("/")
    slug = re.sub(r"[^A-Za-z0-9._-]+", "_", slug)
    return SOURCES_DIR / (f"{slug}@{ref}" if ref else slug)


def sync_source(repo, ref, paths):
    """Bring the clone of `repo` to the latest `ref` with only `paths` checked out."""
    dest = source_dir(repo, ref)
    if not (dest / ".git").exists():
        shutil.rmtree(dest, ignore_errors=True)
        dest.parent.mkdir(parents=True, exist_ok=True)
        branch = ["--branch", ref] if ref else []
        git("clone", "--quiet", "--depth", "1", "--filter=blob:none", "--sparse",
            *branch, repo, str(dest))
        git("sparse-checkout", "set", "--no-cone", *paths, cwd=dest)
        return dest
    git("sparse-checkout", "set", "--no-cone", *paths, cwd=dest)
    git("fetch", "--quiet", "--depth", "1", "origin", ref or "HEAD", cwd=dest)
    git("reset", "--quiet", "--hard", "FETCH_HEAD", cwd=dest)
    git("reflog", "expire", "--expire=now", "--all", cwd=dest)
    git("gc", "--quiet", "--prune=now", cwd=dest)
    return dest


def tree_digest(folder):
    h = hashlib.sha256()
    for path in sorted(p for p in folder.rglob("*") if p.is_file() or p.is_symlink()):
        if path.name == ".DS_Store":
            continue
        h.update(str(path.relative_to(folder)).encode() + b"\0")
        h.update(path.read_bytes() if path.is_file() else b"")
        h.update(b"\0")
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--force", action="store_true", help="overwrite changed skills")
    args = parser.parse_args()

    skills = load_config()
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    SKILLS_DIR.mkdir(parents=True, exist_ok=True)

    def ours(name):
        folder = SKILLS_DIR / name
        return not folder.exists() or manifest.get(name) == tree_digest(folder)

    for name in list(manifest):
        if name not in skills and ours(name):
            shutil.rmtree(SKILLS_DIR / name, ignore_errors=True)
            del manifest[name]

    # One clone per repo and ref, holding every folder we need from it.
    groups = {}
    for name, spec in skills.items():
        groups.setdefault((spec["repo"], spec.get("ref")), []).append(name)

    if SOURCES_DIR.exists():
        wanted = {source_dir(repo, ref) for repo, ref in groups}
        for path in SOURCES_DIR.iterdir():
            if path not in wanted:
                shutil.rmtree(path, ignore_errors=True)

    fetched = 0
    for (repo, ref), names in groups.items():
        try:
            src = sync_source(repo, ref, [skills[n]["path"] for n in names])
        except subprocess.CalledProcessError as e:
            reason = (e.stderr or "").strip().splitlines()[-1:] or ["git failed"]
            for name in names:
                print(f"failed {name}: {reason[0]}")
            continue

        for name in names:
            spec, dest = skills[name], SKILLS_DIR / name
            folder = src / spec["path"]
            if not (folder / "SKILL.md").is_file():
                print(f"failed {name}: no SKILL.md at {spec['path']}")
                continue
            if not args.force and not ours(name):
                print(f"kept {name}")
                continue
            shutil.rmtree(dest, ignore_errors=True)
            shutil.copytree(folder, dest, symlinks=True)
            if spec.get("frontmatter"):
                try:
                    override_frontmatter(dest / "SKILL.md", spec["frontmatter"])
                except ValueError as e:
                    shutil.rmtree(dest)
                    print(f"failed {name}: {e}")
                    continue
            manifest[name] = tree_digest(dest)
            fetched += 1

    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"{fetched}/{len(skills)} external skills -> {SKILLS_DIR}")


if __name__ == "__main__":
    main()
