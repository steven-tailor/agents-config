# agents-config

Personal collection of subagents, skills, and global instructions for Claude Code and Codex. `install.sh` symlinks them into each tool's config dir.

## Layout

```
agents/                  One file per subagent, the single source for both tools
skills/                  Skills shared by Claude Code and Codex
Codex/                   Codex-only global config (AGENTS.md, keybindings.json)
scripts/build_agents.py  Renders agents/ into build/claude and build/codex
install.sh               Builds agents and creates the symlinks
build/                   Generated, gitignored. Never edit or commit
```

## Install mechanics

`install.sh` sets up only the tools it detects (config dir or CLI on `PATH`). For each it runs the generator, then links:

| Repo path | `~/.claude` (`CLAUDE_CONFIG_DIR`) | `~/.codex` (`CODEX_HOME`) |
| --- | --- | --- |
| `build/<tool>/agents` | `agents` | `agents` |
| `skills` | `skills` | `skills` |
| `Codex/AGENTS.md` | — | `AGENTS.md` |
| `Codex/keybindings.json` | — | `keybindings.json` |

- Existing symlinks are repointed; real files and dirs are moved to `<name>.backup-<timestamp>`.
- Piped from curl, it clones or updates `AGENTS_CONFIG_REPO` into `AGENTS_CONFIG_DIR` (default `~/.agents-config`) and re-runs from there.
- `--dry-run` prints actions without changing tool config dirs; the build still runs.

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

Validate after editing: `python3 scripts/build_agents.py`.

## Skills

- `skills/` is flat: one folder per skill.
- Do not add default skills that ship with Claude Code or Codex. `skills/synced/` and `skills/.system/` are app-managed and gitignored.
- When adding a third-party skill, keep its license file and credit the source in the README `Credits` section.
