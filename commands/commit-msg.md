---
description: Generate a commit message from the current diff
---

Write a commit message for the current changes.

1. Read the diff: `git diff --cached` if anything is staged, otherwise `git diff`.
2. Read `git log --oneline -20` and match the style of commits for the same work.
3. Write a conventional-commit subject (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`,
   `chore:`) and a body saying what changed and why. The reader has the diff; what they
   lack is the reason.

Never include:

- `Co-Authored-By:` or any other attribution trailer or footer.
- **A count of anything.** Not "four tests", not "3 files changed", not "two new
  endpoints". Say what the tests cover, not how many there are. This is the rule most
  often broken on a test-only diff, where the count is the most obvious thing to reach for.
- Phase numbers, task IDs or plan paths, which are dead pointers outside the gitignored
  spec repo.

Print the message inside a single fenced code block, so it can be copied without being
picked out of prose, and nothing else inside that fence. Anything you want to say about
the change goes outside it.

Then stop. Do not offer to commit, and do not run `git commit`.
