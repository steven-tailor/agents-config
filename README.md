# agents-config

My personal collection of subagents, skills, and global instructions for [Claude Code](https://claude.com/claude-code) and [Codex](https://github.com/openai/codex), kept in one place and symlinked into each tool.

Most skills here are written by other people. This repo only collects them; see [Credits](#credits).

> `Codex/AGENTS.md` holds my own global rules for Codex. Installing replaces your `~/.codex/AGENTS.md` (the old file is backed up), so read it first or delete it from your clone.

## Install

```bash
git clone https://github.com/steven-tailor/agents-config.git ~/.agents-config && ~/.agents-config/install.sh
```

Requires `git`, `bash`, and Python 3.11+. Keep the clone where it is: the installed configs are symlinks into it.

Preview the changes without touching anything:

```bash
~/.agents-config/install.sh --dry-run
```

## Update

```bash
git -C ~/.agents-config pull && ~/.agents-config/install.sh
```

Re-run `install.sh` after any change to `agents/`, so the generated agent files are rebuilt.

## What gets installed

`install.sh` only sets up the tools it finds, either from their config directory or their CLI on `PATH`.

| Repo path | Claude Code (`~/.claude`) | Codex (`~/.codex`) |
| --- | --- | --- |
| `agents/` (generated) | `agents/` | `agents/` |
| `skills/` | `skills/` | `skills/` |
| `Codex/AGENTS.md` | — | `AGENTS.md` |
| `Codex/keybindings.json` | — | `keybindings.json` |

`CLAUDE_CONFIG_DIR` and `CODEX_HOME` override the default directories.

Existing symlinks are repointed. Real files and directories are moved to `<name>.backup-<timestamp>` first, so nothing is lost. To roll back, delete the symlink and rename the backup.

## Layout

```
agents/                 One file per subagent, the single source for both tools
skills/                 Skills shared by Claude Code and Codex
Codex/                  Codex-only global config
scripts/build_agents.py Renders agents/ into build/claude and build/codex
install.sh              Builds agents and creates the symlinks
```

## Agents

Each agent is written once in `agents/<name>.md` and rendered into Claude Code Markdown and Codex TOML:

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

- `[claude]` and `[codex]` are copied as is into each tool's format.
- `effort` becomes Claude's `effort` and Codex's `model_reasoning_effort`.
- For Codex, hyphens in `name` become underscores. `sandbox_mode` is `workspace-write` when the Claude tools include an editing tool, otherwise `read-only`.
- `<!-- claude -->` and `<!-- codex -->` blocks hold instructions that only apply to one tool.

To build without installing:

```bash
python3 scripts/build_agents.py
```

## Credits

Skills are copied from their authors. All credit goes to them:

- [mattpocock/skills](https://github.com/mattpocock/skills): `ask-matt`, `code-review`, `codebase-design`, `diagnosing-bugs`, `domain-modeling`, `grill-me`, `grill-with-docs`, `grilling`, `handoff`, `implement`, `implement-spec`, `improve-codebase-architecture`, `loop-me`, `prototype`, `research`, `resolving-merge-conflicts`, `setup-matt-pocock-skills`, `tdd`, `to-questionnaire`, `to-spec`, `to-tickets`, `triage`, `wait-what`, `wayfinder`, `wizard`, `writing-for-agents`
- [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman): `caveman`
- Apache-2.0 skills, with the license kept in each folder: `figma`, `gh-address-comments`, `gh-fix-ci`, `linear`, `security-best-practices`, `security-ownership-map`, `sentry`, `yeet`

If you wrote a skill here and want a different credit or want it removed, open an issue.

## License

My own work here (the install script, the generator, the agents, the `ship` skill and the docs) is released into the public domain under [the Unlicense](LICENSE). Use it however you like, no attribution needed.

Third-party skills keep their original licenses.
