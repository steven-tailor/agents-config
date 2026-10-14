---
name: ship
description: Take a task end-to-end with sub-agents — design and plan, tests first, implement, verify (lint, types, tests), review until clean, test manually like a user, update docs, commit and open a PR. Use when the user says /ship, "ship it", "ship me X", "take this task", "finish/end the task", or hands over a task or issue to be delivered as a PR.
---

# Ship a task

You are the orchestrator. Sub-agents cannot spawn sub-agents, so you run every step yourself and pass context between them. Give each agent everything it needs in its prompt: it has not seen this conversation. The project's own instructions decide *how*; this skill only decides *in what order*.

Agents: `solution-architect`, `planner`, `implementer`, `reviewer`, `tester`, `docs-owner` (fall back to `general-purpose` if one doesn't exist). In Codex their names use underscores: `solution_architect`, `docs_owner`. Only you commit, push and open the PR; tell every agent not to.

## 0. Learn the project

Before anything else, read whatever the project provides: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README.md`, and the manifest (`package.json`, `Makefile`, `pyproject.toml`, `Cargo.toml`, …). Extract:

- the commands for **lint**, **typecheck**, **tests**, and **running the app** (use the project's own scripts; if one doesn't exist, skip it and say so);
- branch naming, commit and PR conventions, changelog rules, and any "never do X" rules.

The project's rules win over this skill wherever they conflict.

## 1. Understand the task

Take the task from the user's prompt, or fetch the ticket it references (e.g. `gh issue view <n>`, or the tracker's MCP). Write down the acceptance criteria: the observable behaviors that mean "done". If the task is ambiguous or needs a product/architecture decision, ask the user before writing code. Create a branch following the project's convention.

## 2. Design and plan

When the task touches architecture (a new module, dependency, data model, or public interface), launch `solution-architect` with: the task, the acceptance criteria and the project rules from step 0. It returns the approach, the files it touches, the risks, and open decisions. For any other task, skip it and say so in the report.

Then launch `planner` with: the task, the acceptance criteria, the project rules and the architect's design, if there is one. Ask for a bounded plan:

- the steps, each with the files it changes;
- the test for each acceptance criterion;
- the commands that verify the change;
- what is out of scope.

If either agent surfaces a product or architecture decision the task doesn't answer, ask the user before step 3. Otherwise pass the design and the plan to every later agent.

## 3. Implement (at most 3 rounds)

Launch `implementer` with: the task, the acceptance criteria, the project rules and commands from step 0, the design and plan from step 2, and these instructions:

1. Write basic tests for the acceptance criteria first, following the project's existing test patterns. Run them and confirm they fail for the right reason.
2. Implement the smallest change that makes them pass.
3. Run lint, typecheck and tests.
4. Do not commit. Report changed files, test results, and risks.

Then check it yourself:

- Run lint, typecheck and tests with the project's commands.
- Compare the diff with the acceptance criteria: is each one implemented and covered by a test?

If anything is red or a criterion is missing, send the output and the gap back to `implementer`. Each send-back is one round. **At most 3 rounds**: if it's still not done, stop and report to the user.

## 4. Review (until clean, at most 3 rounds)

Launch `reviewer` on the branch diff against the base branch. Give it the task, the acceptance criteria, the design and the project rules. Ask for findings ranked by severity, each with file:line and a concrete failure scenario.

- No blocking or major findings: go to step 5.
- Otherwise send them to `implementer`, re-run the step 3 checks, and review again with a fresh `reviewer`.

Repeat until a review finds nothing blocking or major, **at most 3 review rounds**; anything left over goes into the PR description as known issues.

## 5. Test manually like a user

Launch `tester` with: the acceptance criteria, how to run the changed code (step 0), and the instructions for the kind of change.

**User-facing UI:**

1. Use the `webapp-testing` skill: it starts the app, waits until it responds, and stops it afterwards.
2. Write a throwaway Python Playwright script outside the repo that walks each acceptance criterion like a user: navigate, click, type, check what's on screen. Take a screenshot per criterion.
3. If Python Playwright isn't available, report that as a blocker; don't install anything.
4. Report pass/fail per criterion with screenshot paths, and the exact failure for each fail.

**No UI** (CLI, script, library, API, config):

1. Exercise each acceptance criterion the way a user or caller would: run the command or script, call the endpoint or function, from a scratch directory outside the repo where possible.
2. Cover the error paths too: bad input, missing files, unknown options.
3. Report pass/fail per criterion with the exact command and its output, and anything that couldn't be tested here (another OS, a real service).

On a blocker, ask the user how to proceed. On a failure, send it to `implementer`, re-run the step 3 checks, and test again. These fixes share the 3-round budget from step 3.

## 6. Update docs

Launch `docs-owner` with: the branch diff, the task, the design from step 2 and the project's docs rules from step 0. Ask it to:

1. Update the docs the change makes stale: README, `AGENTS.md`/`CLAUDE.md`, usage text, changelog, comments that describe behavior.
2. Document new functionality or behavior for other agents, using the `writing-for-agents` skill: what an agent working in this repo later needs to know and can't find by reading the code (the convention, the reason behind a choice, the gotcha). Place it where the project keeps agent docs, reached by a pointer in `AGENTS.md`/`CLAUDE.md`.
3. Not commit, and report each doc it changed or added, or "no docs affected" if nothing needs to change.

If it changed anything, re-run the step 3 checks.

## 7. Ship

Follow the project's conventions for commits, changelog, and PR (conventional commits by default). Push and open the PR with: what changed, how it was verified (checks, review summary, manual test results), and any known issues. **Never merge** unless the user explicitly says so.

## 8. Report

Tell the user in a few lines: the PR link, what was done, verification results, and anything left open.
