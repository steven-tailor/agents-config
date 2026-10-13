---
name: ship
description: Take a task end-to-end with sub-agents — tests first, implement, verify (lint, types, tests), review, fix, test manually in a browser, commit and open a PR. Use when the user says /ship, "ship it", "ship me X", "take this task", "finish/end the task", or hands over a task or issue to be delivered as a PR.
---

# Ship a task

You are the orchestrator. Sub-agents cannot spawn sub-agents, so you run every step yourself and pass context between them. Give each agent everything it needs in its prompt: it has not seen this conversation. The project's own instructions decide *how*; this skill only decides *in what order*.

Agents: `implementer`, `reviewer`, `tester` (fall back to `general-purpose` if one doesn't exist). Only you commit, push and open the PR; tell every agent not to.

## 0. Learn the project

Before anything else, read whatever the project provides: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README.md`, and the manifest (`package.json`, `Makefile`, `pyproject.toml`, `Cargo.toml`, …). Extract:

- the commands for **lint**, **typecheck**, **tests**, and **running the app** (use the project's own scripts; if one doesn't exist, skip it and say so);
- branch naming, commit and PR conventions, changelog rules, and any "never do X" rules.

The project's rules win over this skill wherever they conflict.

## 1. Understand the task

Take the task from the user's prompt, or fetch the ticket it references (e.g. `gh issue view <n>`, or the tracker's MCP). Write down the acceptance criteria: the observable behaviors that mean "done". If the task is ambiguous or needs a product/architecture decision, ask the user before writing code. Create a branch following the project's convention.

## 2. Implement (at most 3 rounds)

Launch `implementer` with: the task, the acceptance criteria, the project rules and commands from step 0, and these instructions:

1. Write basic tests for the acceptance criteria first, following the project's existing test patterns. Run them and confirm they fail for the right reason.
2. Implement the smallest change that makes them pass.
3. Run lint, typecheck and tests.
4. Do not commit. Report changed files, test results, and risks.

Then check it yourself:

- Run lint, typecheck and tests with the project's commands.
- Compare the diff with the acceptance criteria: is each one implemented and covered by a test?

If anything is red or a criterion is missing, send the output and the gap back to `implementer`. Each send-back is one round. **At most 3 rounds**: if it's still not done, stop and report to the user.

## 3. Review (at most 2 rounds)

Launch `reviewer` on the branch diff against the base branch. Give it the task, the acceptance criteria and the project rules. Ask for findings ranked by severity, each with file:line and a concrete failure scenario.

- No blocking or major findings: go to step 4.
- Otherwise send them to `implementer`, re-run the step 2 checks, and re-review.

**At most 2 review rounds**; anything left over goes into the PR description as known issues.

## 4. Test manually in a browser

Skip this step if the change has no user-facing UI, and say so in the report.

Launch `tester` with: the acceptance criteria, how to run the app (step 0), and these instructions:

1. Start the app in the background and wait until it responds.
2. Write a throwaway Playwright script outside the repo that walks each acceptance criterion like a user: navigate, click, type, check what's on screen. Take a screenshot per criterion.
3. Use the project's Playwright if it has one. If Playwright isn't available, report that as a blocker; don't install anything.
4. Stop the app. Report pass/fail per criterion with screenshot paths, and the exact failure for each fail.

On a blocker, ask the user how to proceed. On a failure, send it to `implementer`, re-run the step 2 checks, and test again. These fixes share the 3-round budget from step 2.

## 5. Ship

Follow the project's conventions for commits, changelog, and PR (conventional commits by default). Push and open the PR with: what changed, how it was verified (checks, review summary, manual test results), and any known issues. **Never merge** unless the user explicitly says so.

## 6. Report

Tell the user in a few lines: the PR link, what was done, verification results, and anything left open.
