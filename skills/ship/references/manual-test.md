# Manual test procedures

Give `tester` the procedure that matches the change.

**User-facing UI:**

1. Use the `webapp-testing` skill: it starts the app, waits until it responds, and stops it afterwards.
2. Write a throwaway Python Playwright script outside the repo with Bash that walks each acceptance criterion like a user: navigate, click, type, check what's on screen. Take a screenshot per criterion.
3. If Python Playwright isn't available, report that as a blocker; don't install anything.
4. Report pass/fail per criterion with screenshot paths, and the exact failure for each fail.

**No UI** (CLI, script, library, API, config):

1. Exercise each acceptance criterion the way a user or caller would: run the command or script, call the endpoint or function, from a scratch directory outside the repo where possible.
2. Cover the error paths too: bad input, missing files, unknown options.
3. Report pass/fail per criterion with the exact command and its output, and anything that couldn't be tested here (another OS, a real service).
