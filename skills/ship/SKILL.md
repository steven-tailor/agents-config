---
name: ship
description: Take a task end-to-end with sub-agents — design and plan, tests first, implement, verify (lint, types, tests), review until clean, test manually like a user, update docs, commit and open a PR. Use when the user says /ship, "ship it", "ship me X", "take this task", "finish/end the task", or hands over a task or issue to be delivered as a PR.
---

# Ship a task

You are the orchestrator. These agents have no tool to spawn other agents, so you run every step yourself and pass context between them. Give each agent everything it needs in its prompt: it has not seen this conversation. The project's own instructions decide *how*; this skill only decides *in what order*.

Agents: `solution-architect`, `planner`, `test-writer`, `implementer`, `reviewer`, `tester`, `docs-owner` (fall back to `general-purpose` if one doesn't exist). In Codex their names use underscores: `solution_architect`, `test_writer`, `docs_owner`. Only you commit, push and open the PR; tell every agent not to commit or stage.

## Context budget

Every agent call re-reads its whole context, so context size drives cost. Keep yours and theirs small:

- Do not read source code yourself; agents do. You read the project rules (step 0), `git diff --stat`, and agent reports.
- Write the design and the plan to files outside the repo once (e.g. `/tmp/ship-<branch>/design.md`, `plan.md`). Give each agent the paths and name the sections it needs; paste only short items such as acceptance criteria and findings.
- Ask every agent for a report of at most 30 lines: changed files, check results (failures only), risks, open decisions. No code or full logs.
- One agent, one small task: at most one plan step or 3 findings. Give the next task to a fresh agent, not a long-running one.

## 0. Learn the project

Before anything else, read whatever the project provides: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README.md`, and the manifest (`package.json`, `Makefile`, `pyproject.toml`, `Cargo.toml`, …). Extract:

- the commands for **lint**, **typecheck**, **tests**, and **running the app** (use the project's own scripts; if one doesn't exist, skip it and say so);
- branch naming, commit and PR conventions, changelog rules, and any "never do X" rules.

The project's rules win over this skill wherever they conflict.

## 1. Understand the task

Take the task from the user's prompt, or fetch the ticket it references (e.g. `gh issue view <n>`, or the tracker's MCP). Write down the acceptance criteria: the observable behaviors that mean "done". If the task is ambiguous or needs a product/architecture decision, ask the user before writing code. Create a branch following the project's convention.

## 2. Design and plan

When the task touches architecture (a new module, dependency, data model, or public interface), launch `solution-architect` with: the task, the acceptance criteria and the project rules from step 0. It returns the approach, the files it touches, the risks, and open decisions. For any other task, skip it and say so in the report.

When the task spans several steps or files, or the architect ran, launch `planner` with: the task, the acceptance criteria, the project rules and the architect's design, if there is one. Ask for a bounded plan:

- the steps, each with the files it changes;
- the test for each acceptance criterion;
- the commands that verify the change;
- what is out of scope.

For a single local change (one file, one behavior), skip it and say so in the report.

If either agent surfaces a product or architecture decision the task doesn't answer, ask the user before step 3. Otherwise save the design and the plan, whichever exist, to files and pass their paths to every later agent.

## 3. Write tests, then implement (at most 3 rounds)

When the change has behavior to test, launch `test-writer` with: the task, the acceptance criteria, the project rules and commands from step 0, the design and plan from step 2, and these instructions:

1. Write tests for each acceptance criterion, following the project's existing test patterns.
2. Run them and confirm they fail for the right reason.
3. Edit only tests and fixtures. Do not commit. Report the test files, the failing output, and any criterion it could not test.

For a change with no behavior to test (docs, config, wording), skip it and say so in the report. For a small change (one behavior, a few files), skip it too and have `implementer` write the failing test first, then the code.

Launch `implementer` with: the task, the acceptance criteria, the project rules and commands from step 0, the design and plan from step 2, the test files from `test-writer`, and these instructions:

1. Implement the smallest change that makes the tests pass. Do not edit the tests; if one looks wrong, report it instead.
2. Run lint, typecheck and the tests for the changed area.
3. Do not commit. Report changed files, check results, and risks.

When the plan has several steps, launch one `implementer` per step.

Then compare `git diff --stat` and the reports with the acceptance criteria: is each one implemented and covered by a test? Trust the agents' check results here; you run the full checks once, in step 7.

If a criterion has no test or a test is wrong, send the gap to `test-writer`; if anything else is red or a criterion is missing, send the output and the gap to `implementer`. Each send-back is one round. **At most 3 rounds**: if it's still not done, stop and report to the user.

## 4. Review (at most 2 rounds)

Round 1: launch `reviewer` on the branch diff against the base branch. Give it the task, the acceptance criteria, the design path and the project rules. Ask for findings ranked by severity, each with file:line and a concrete failure scenario.

- No blocking or major findings: go to step 5.
- Otherwise run `git add -A` to stage the reviewed state. Send test findings to `test-writer` and the rest to `implementer`, at most 3 findings per fresh agent.

Round 2: launch a fresh `reviewer` with the round-1 findings and only the fixes: `git diff` (unstaged changes against the staged, reviewed state). Ask it to confirm each finding is fixed and to review the fixes for new defects.

Blocking or major findings left after round 2 go into the PR description as known issues.

## 5. Test manually like a user

Launch `tester` with: the acceptance criteria, how to run the changed code (step 0), and the instructions for the kind of change.

**User-facing UI:**

1. Use the `webapp-testing` skill: it starts the app, waits until it responds, and stops it afterwards.
2. Write a throwaway Python Playwright script outside the repo with Bash that walks each acceptance criterion like a user: navigate, click, type, check what's on screen. Take a screenshot per criterion.
3. If Python Playwright isn't available, report that as a blocker; don't install anything.
4. Report pass/fail per criterion with screenshot paths, and the exact failure for each fail.

**No UI** (CLI, script, library, API, config):

1. Exercise each acceptance criterion the way a user or caller would: run the command or script, call the endpoint or function, from a scratch directory outside the repo where possible.
2. Cover the error paths too: bad input, missing files, unknown options.
3. Report pass/fail per criterion with the exact command and its output, and anything that couldn't be tested here (another OS, a real service).

On a blocker, ask the user how to proceed. On a failure, send it to `implementer` (or to `test-writer` if a test is wrong) and test again. These fixes share the 3-round budget from step 3.

## 6. Update docs

Launch `docs-owner` with: the base branch (it reads the diff itself), the task, the design path from step 2 and the project's docs rules from step 0. Ask it to:

1. Update the docs the change makes stale: README, `AGENTS.md`/`CLAUDE.md`, usage text, changelog, comments that describe behavior.
2. Document new functionality or behavior for other agents, using the `writing-for-agents` skill: what an agent working in this repo later needs to know and can't find by reading the code (the convention, the reason behind a choice, the gotcha). Place it where the project keeps agent docs, reached by a pointer in `AGENTS.md`/`CLAUDE.md`.
3. Not commit, and report each doc it changed or added, or "no docs affected" if nothing needs to change.

## 7. Ship

Run lint, typecheck and the full test suite yourself, once, keeping only the failure output. If anything is red, send it to `implementer`; this shares the 3-round budget from step 3.

Follow the project's conventions for commits, changelog, and PR (conventional commits by default). Push and open the PR with: what changed, how it was verified (checks, review summary, manual test results), and any known issues. **Never merge** unless the user explicitly says so.

## 8. Report

Tell the user in a few lines: the PR link, what was done, verification results, and anything left open.
