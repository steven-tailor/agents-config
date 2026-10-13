# agents-config

Personal collection of subagents, skills, and global instructions for Claude Code and Codex. `install.sh` symlinks them into each tool's config dir.

## Layout

```
agents/                  One file per subagent, the single source for both tools
skills/                  Skills shared by Claude Code and Codex
global/AGENTS.md         Global instructions, installed as CLAUDE.md and AGENTS.md
scripts/build_agents.py  Renders agents/ into build/claude and build/codex
install.sh               Builds agents and creates the symlinks
build/                   Generated, gitignored. Never edit or commit
```

## Install mechanics

`install.sh` sets up only the tools it detects (config dir or CLI on `PATH`). For each it runs the generator, then links:

| Repo path | `~/.claude` (`CLAUDE_CONFIG_DIR`) | `~/.codex` (`CODEX_HOME`) |
| --- | --- | --- |
| `build/<tool>/agents/*` | `agents/<entry>` | `agents/<entry>` |
| `skills/*` | `skills/<entry>` | `skills/<entry>` |
| `global/AGENTS.md` | `CLAUDE.md` | `AGENTS.md` |

Rule: never destroy what the tools or the user created.

- `agents/` and `skills/` in tool dirs are real folders with one symlink per managed entry. Anything else in them stays untouched.
- Managed entries are git-tracked files (skills) or names in `build/<tool>/manifest.json` (agents). Never derive them from folder contents: tools may have written into the clone.
- Real files and folders in the way are renamed to `<name>.backup-<timestamp>`, never deleted.
- Links into the repo whose source is gone are removed.
- Older installs linked whole folders. They are converted to real folders and unmanaged entries are copied over; `skills/synced` (Claude) and `skills/.system` (Codex) go only to their own tool.
- Piped from curl, it clones or updates `AGENTS_CONFIG_REPO` into `AGENTS_CONFIG_DIR` (default `~/.agents-config`) and re-runs from there. The clone is shallow (`--depth 1`); updates are plain `pull --ff-only`, since `pull --depth` cannot fast-forward. The update is skipped if the clone has local changes or cannot fast-forward.
- `--update` pulls the clone the script lives in (same safety checks), then re-runs the new version.
- Auto-update: every install registers a daily `install.sh --update` job, label `agents-config.update` (launchd plist in `~/Library/LaunchAgents` on macOS, tagged crontab line elsewhere), logging to `build/auto-update.log`. It captures the current `PATH`, `CLAUDE_CONFIG_DIR` and `CODEX_HOME`. Rewritten only when its content changes; `--no-auto-update` removes it.
- `--dry-run` prints actions without changing tool config dirs; the build still runs. `--force` overwrites generated agents edited outside the repo.

## Agents

Write each agent once in `agents/<name>.md`: TOML frontmatter between `+++` lines, then instructions.

```markdown
+++
name = "reviewer"
description = "Review code for correctness, security, and missing tests."
effort = "high"

[claude]
tools = "Read, Grep, Glob, Bash"
permissionMode = "plan"

[codex]
model = "gpt-5.6-terra"
+++
Shared instructions for both tools.

<!-- codex -->
Only in the Codex version.
<!-- /codex -->
```

- `[claude]` and `[codex]` keys are copied as is into each tool's format.
- `effort` maps to Claude `effort` and Codex `model_reasoning_effort`.
- Codex `name` swaps hyphens for underscores. `sandbox_mode` defaults to `workspace-write` when Claude `tools` include an editing tool, else `read-only`; set it in `[codex]` to override.
- `<!-- claude -->` / `<!-- codex -->` blocks keep instructions for one tool only. They cannot nest.

The generator records each output's hash in `build/<tool>/manifest.json`. A generated file changed outside the generator (a tool editing it through its symlink) is kept and printed as `kept <file>`; `--force` overwrites it. Stale outputs are removed only if unchanged.

Validate after editing: `python3 scripts/build_agents.py`.

## Skills

- `skills/` is flat: one folder per skill.
- Do not add default skills that ship with Claude Code or Codex. `skills/synced/` and `skills/.system/` are app-managed and gitignored.
- Do not vendor [mattpocock/skills](https://github.com/mattpocock/skills). It is an external requirement users install themselves (see README `Requirements`); agents may depend on it.
- When adding a third-party skill, keep its license file and credit the source in the README `Credits` section.
