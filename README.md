# agents-config

My personal collection of subagents, skills, and global instructions for [Claude Code](https://claude.com/claude-code) and [Codex](https://github.com/openai/codex), kept in one place and symlinked into each tool.

Most skills here are written by other people. This repo only collects them; see [Credits](#credits).

> `Codex/AGENTS.md` holds my own global rules for Codex. Installing replaces your `~/.codex/AGENTS.md` (the old file is backed up), so read it first or delete it from your clone.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/steven-tailor/agents-config/main/install.sh | bash
```

Requires `git`, `bash`, and Python 3.11+. The script clones this repo into `~/.agents-config` (override with `AGENTS_CONFIG_DIR`) and links your configs into it, so keep that folder.

Preview the changes first. The repo is still cloned, but your configs stay untouched:

```bash
curl -fsSL https://raw.githubusercontent.com/steven-tailor/agents-config/main/install.sh | bash -s -- --dry-run
```

## Update

Run the same install command again. It pulls the latest version and relinks everything.

Updates never delete what Claude Code, Codex or you created:

| What | On update |
| --- | --- |
| Your own agents and skills in `~/.claude` / `~/.codex` | untouched |
| Agents edited through the tool | kept, with a warning |
| Real files in the way | renamed to `<name>.backup-<timestamp>` |
| Local changes in `~/.agents-config` | update skipped |

## Credits

Skills are copied from their authors. All credit goes to them:

- [mattpocock/skills](https://github.com/mattpocock/skills): `ask-matt`, `code-review`, `codebase-design`, `diagnosing-bugs`, `domain-modeling`, `grill-me`, `grill-with-docs`, `grilling`, `handoff`, `implement`, `implement-spec`, `improve-codebase-architecture`, `loop-me`, `prototype`, `research`, `resolving-merge-conflicts`, `setup-matt-pocock-skills`, `tdd`, `to-questionnaire`, `to-spec`, `to-tickets`, `triage`, `wait-what`, `wayfinder`, `wizard`, `writing-for-agents`
- Apache-2.0 skills, with the license kept in each folder: `figma`, `gh-address-comments`, `gh-fix-ci`, `linear`, `security-best-practices`, `security-ownership-map`, `sentry`, `yeet`

If you wrote a skill here and want a different credit or want it removed, open an issue.

## License

My own work here (the install script, the generator, the agents, the `ship` skill and the docs) is released into the public domain under [the Unlicense](LICENSE). Use it however you like, no attribution needed.

Third-party skills keep their original licenses.
