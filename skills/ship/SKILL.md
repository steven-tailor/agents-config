---
name: ship
description: Take a task end-to-end with sub-agents — implement, review, fix, verify (lint, types, tests), commit and open a PR. Use when the user says /ship, "ship it", "ship me X", "take this task", "finish/end the task", or hands over a task or issue to be delivered as a PR.
---

# Ship a task

You are the orchestrator. Sub-agents cannot spawn sub-agents, so you run every step yourself and pass context between them. The project's own instructions decide *how*; this skill only decides *in what order*.

## 0. Learn the project

Before anything else, read whatever the project provides: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README.md`, and the manifest (`package.json`, `Makefile`, `pyproject.toml`, `Cargo.toml`, …). Extract:

- the commands for **lint**, **typecheck**, and **tests** (use the project's own scripts; if one of the three doesn't exist, skip it and say so);
- branch naming, commit and PR conventions, changelog rules, and any "never do X" rules.

The project's rules win over this skill wherever they conflict.

## 1. Understand the task

If it's an issue reference, fetch it (e.g. `gh issue view <n>`). If it's ambiguous or needs a product/architecture decision, ask the user before writing code. Create a branch following the project's convention.

## 2. Implement

Launch the `implementer` agent (or `general-purpose` if it doesn't exist) with: the task, acceptance criteria, the relevant project rules from step 0, and the instruction to report changed files and risks.

## 3. Review

Launch the `reviewer` agent (or `general-purpose`) on the branch diff against the base branch. Give it the task and the project rules. Ask for findings ranked by severity, each with file:line and a concrete failure scenario.

## 4. Fix

If there are blocking or major findings, send them back to the implementer. Re-review the fix. **At most 2 review→fix rounds**; anything left over goes into the PR description as known issues.

## 5. Verify

Run lint, typecheck, and tests with the project's commands from step 0. On failure, send the output back to the implementer and re-run. Don't proceed while anything is red; if you can't get it green, stop and report.

## 6. Ship

Follow the project's conventions for commits, changelog, and PR. Push and open the PR with: what changed, how it was verified, the review summary, and any known issues. **Never merge** unless the user explicitly says so.

## 7. Report

Tell the user in a few lines: the PR link, what was done, verification results, and anything left open.
