# agents-config

Personal collection of subagents, skills, and global instructions for Claude Code and Codex. `install.sh` symlinks them into each tool's config dir.

## Layout

```
agents/                  One file per subagent, the single source for both tools
skills/                  Own skills shared by Claude Code and Codex
skills.toml              Third-party skills: source repo, path, frontmatter overrides
plugins.toml             Plugins to install per tool (plugin CLI or skills.sh)
mcp.toml                 MCP servers to add to each tool, used by the agents
global/AGENTS.md         Global instructions, installed as CLAUDE.md and AGENTS.md
scripts/build_agents.py  Renders agents/ into build/claude and build/codex
scripts/fetch_skills.py  Fetches skills.toml entries into build/external/skills
scripts/install_plugins.py  Installs plugins.toml entries into one tool
scripts/install_mcp.py   Adds mcp.toml servers to one tool
install.sh               Fetches skills, builds agents, creates the symlinks, installs plugins and MCP servers
build/                   Generated, gitignored. Never edit or commit
```

## Install mechanics

`install.sh` sets up only the tools it detects (config dir or CLI on `PATH`). It fetches external skills once, then for each tool runs the generator, links, and installs plugins:

| Repo path | `~/.claude` (`CLAUDE_CONFIG_DIR`) | `~/.codex` (`CODEX_HOME`) |
| --- | --- | --- |
| `build/<tool>/agents/*` | `agents/<entry>` | `agents/<entry>` |
| `skills/*` | `skills/<entry>` | `skills/<entry>` |
| `build/external/skills/*` | `skills/<entry>` | `skills/<entry>` |
| `global/AGENTS.md` | `CLAUDE.md` | `AGENTS.md` |

Rule: never destroy what the tools or the user created.

- `agents/` and `skills/` in tool dirs are real folders with one symlink per managed entry. Anything else in them stays untouched.
- Managed entries are git-tracked files (skills), names in `build/<tool>/manifest.json` (agents) or in `build/external/manifest.json` (external skills). Never derive them from folder contents: tools may have written into the clone.
- Real files and folders in the way are renamed to `<name>.backup-<timestamp>`, never deleted.
- Links into the repo whose source is gone are removed.
- Older installs linked whole folders. They are converted to real folders and unmanaged entries are copied over; `skills/synced` (Claude) and `skills/.system` (Codex) go only to their own tool.
- Piped from curl, it clones or updates `AGENTS_CONFIG_REPO` into `AGENTS_CONFIG_DIR` (default `~/.agents-config`) and re-runs from there. The clone is shallow (`--depth 1`) and stays that way: updates fetch only the latest commit, `checkout -B` onto it (refuses to overwrite untracked files) and gc the rest. Full clones (development checkouts) get plain `pull --ff-only` and keep history. Updates are skipped on local changes, local commits or a detached HEAD.
- `--update` pulls the clone the script lives in (same safety checks), then re-runs the new version.
- Auto-update: every install registers a daily `install.sh --update` job, label `agents-config.update` (launchd plist in `~/Library/LaunchAgents` on macOS, tagged crontab line elsewhere), logging to `build/auto-update.log`. It captures the current `PATH`, `CLAUDE_CONFIG_DIR` and `CODEX_HOME`. Rewritten only when its content changes; `--no-auto-update` removes it.
- `--dry-run` prints actions without changing tool config dirs; the build still runs. `--force` overwrites generated agents and external skills edited outside the repo.
- `--help` / `-h` prints the `# Usage:` block of the `install.sh` header comment, up to its first blank line. Keep that block contiguous and give every new option a line in it. Piped from curl there is no file, so it prints a one-line fallback.

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
- Do not vendor [mattpocock/skills](https://github.com/mattpocock/skills). `plugins.toml` installs it: the Claude Code plugin, and skills.sh for Codex (Codex doesn't read its `.claude-plugin` marketplace yet). Agents may depend on it.

## Plugins

- `plugins.toml` lists, per entry, a plugin id (`<tool>`, optional `<tool>_marketplace` added first if missing) or a skills.sh source (`<tool>_skills_sh`, installs every skill globally with `npx skills add <source> -g`).
- Never reinstall or update: an entry is skipped when the tool lists the plugin as installed or a marker skill from `skills` exists in the tool's skills dirs (Codex: `$CODEX_HOME/skills` and `~/.agents/skills`). Plugins update themselves.
- `install_plugins.py` prints `installed`, `present`, `skipped` or `failed <name>: <reason>`; a missing CLI or `npx` skips, a failure warns and never stops the install. `--dry-run` installs nothing.
- `mcp.toml` lists the MCP servers the agents name. `install_mcp.py` adds each with `<tool> mcp add` (Claude: user scope) unless the tool already has that name, skips one whose `requires` CLI is missing, and prints the same lines. An agent that names a server needs its entry here.
- Keep both tools equal: agent instructions are shared, `<!-- claude -->`/`<!-- codex -->` blocks only for what the other tool lacks, and every skill and MCP server installs into both.
- Never copy third-party skills into `skills/`. Add them to `skills.toml` and credit the source in the README `Credits` section. A name must not exist in both.
- `fetch_skills.py` keeps one shallow, sparse clone per repo in `build/external/sources/`, resets it to the latest commit of the branch (default branch unless `ref` is set) on every run, and copies each skill folder into `build/external/skills/`. A `[<name>.frontmatter]` table replaces or adds keys in the copied `SKILL.md`.
- External skills are hashed in `build/external/manifest.json`. One changed outside the script is kept and printed as `kept <name>`; `--force` overwrites it. A failed fetch keeps the previous copy and prints `failed <name>: <reason>`. Skills dropped from `skills.toml` are removed only if unchanged.
- Validate after editing: `python3 scripts/fetch_skills.py`.
