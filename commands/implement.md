---
argument-hint: [document] [section]
description: Work on a specific section from any project document
---

Start or continue work on the document, at the named section.

## Arguments

The arguments arrive as one string in `$ARGUMENTS`. Read them from there:

- **the document** — the first whitespace-separated token: a plan or task file path
- **the section** — everything after it, naming the phase, task or section to work on. May be empty, in which case take the first incomplete section

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1`
binds to the **second** token, and typed as a slash command it arrives as the literal text
`$1`. Neither is the first argument. `$ARGUMENTS` is correct on both paths.

## Context

- Project Document: the first token of `$ARGUMENTS`
- Current Section: the rest of `$ARGUMENTS`

## Step 1: Review Current Status

Read the document in full. Pay special attention to:

- Any **Progress Summary** table. It is near the top but not necessarily first: the plan template puts it after **Quick Links**
- The status of the section (not started, in progress, complete, blocked)
- The dated log at the bottom. Plans call it **Progress Tracking** and task files call it **Progress Notes**; a document may use either, or a changelog
- Dependencies, blockers, and prerequisites listed for the section

**Record the exact headings of the Progress Summary table and the log before editing anything**, with `grep -n '^## ' <the document>`. Every later step updates those sections in place under the names the document already uses. Never add a second Progress Summary table and never rename the log: a document with two tables has one of them silently going stale, and every other command reads whichever it finds first.

Rows are matched by phase or step number, not by exact title: `Phase 1` in the table and `Phase 1 - parseCondition` as the section are the same row.

If the section is already marked complete, ask the user whether to verify it, redo it, or move to the next incomplete section.

## Step 2: Understand the Scope

From the section, extract:

- **Objective**: what success looks like
- **Acceptance criteria** or **success metrics**: the concrete checkboxes
- **Tasks**: the work items to complete
- **File plan**: what files will be created or modified
- **Implementation notes**: design decisions and patterns to follow
- **Testing strategy**: how the work will be validated

If the section is ambiguous, has no clear acceptance criteria, or lacks technical detail, **stop and ask the user for clarification** before writing any code. Don't guess at requirements.

**A `[NEEDS CLARIFICATION: ...]` marker is a hard stop.** If the section still carries one, do not
start it. The marker exists because whoever wrote the document declined to guess; guessing now
just moves the guess later, where it is harder to see. Quote every marker in the section, ask
those questions, and wait. If the user answers, edit the document to replace the marker with the
answer before you write any code, so the next reader inherits the decision rather than the
question.

**Which direction does the sync go?** A **behaviour change** updates the task file first and the
code second: the document is what the change is being measured against, and editing it afterwards
turns it into a description of whatever happened to be built. A **pure refactor** goes code-first
and syncs the document after, because nothing about the intended behaviour changed and rewriting
the criteria beforehand would be theatre. When in doubt it is a behaviour change, because the
cost of being wrong that way is one extra edit, and the other way is a document that agrees with
the code by construction and therefore says nothing.

## Step 3: Read the Codebase

Before changing anything, read the relevant code:

- Files explicitly referenced in the section's **File Plan**
- Files in the same module or directory as the planned changes
- Existing tests that cover the area being changed
- Any related code mentioned in the section's **Dependencies** or **Integration Points**

The goal is to understand current behavior, conventions, and patterns so the changes fit the codebase.

## Step 4: Mark the Section Active

Update the document to reflect that work has started:

- If there is a **Progress Summary** table, set the row for the section to 🟡 IN PROGRESS, keeping the table's existing columns and descriptions
- If the section has its own **Status** field, change it to "In Progress"
- Update the **Last Updated** date if present

If the document has no Progress Summary table and more than one phase, add one, once, after **Quick Links** (or after the header block if there are none), in the plan template's columns. If it has one, you edit that one. There is no case where this step produces a second.

## Step 5: Build a Working Checklist

Create a TodoWrite checklist from the section's acceptance criteria or task list. One todo per concrete deliverable. Mark the first item as `in_progress`.

## Step 6: Implement Incrementally

Work through the checklist one item at a time. For each item:

a. Mark it `in_progress` in TodoWrite
b. **Write a failing test first** when the criterion is testable (TDD), unless the project's CLAUDE.md or the section's notes indicate otherwise
c. Implement the production code until the test passes
d. Run **only the localized tests** related to the change, not the full suite
e. Mark the todo `completed`
f. Append a short note to the log at the bottom of the document (**Progress Tracking** or **Progress Notes**, whichever it already has; create **Progress Notes** only if neither exists):

```
### [Date] - [Item name] Complete
- [What was accomplished]
- Files: [key files created/modified]
- Tests: [test names or brief result]
```

While implementing:

- Follow the conventions in the project's CLAUDE.md
- Follow the **Implementation Notes** from the section precisely
- Follow the **File Plan** for where to create or modify files
- Verify interfaces match any specifications in the document
- Test against available data or mocks before full integration
- Regenerate any auto-generated documentation, schemas, or specs after changes
- Add examples or samples for new endpoints or interfaces when relevant
- Keep any generated artifacts in sync with their source

**Record every departure from the File Plan, as it happens, under `### Deviations` in Progress
Notes.** One line per path: where it went and why, or that it was dropped and why.

```md
### Deviations

- `app/old.py` -> `app/new.py`, moved when the package was renamed
- `app/cache.py` dropped: the query turned out to be fast enough
```

Departing is normal. A File Plan is written before the work and the work teaches you things.
What is not normal is departing silently, because from outside the two are identical: the File
Plan names a path, the path is absent, the status says Complete. `task-converge.py` reads this
section and reports such a task `DEVIATION-RECORDED` rather than `CLAIMED-UNBUILT`, which is the
finding reserved for a task claiming work it did not do.

Write it at the time. Nobody reconstructs why a file moved three weeks later, and **partial
accounting does not count**: one unexplained missing entry and the task reads as unbuilt again,
correctly.

## Step 7: Final Validation

Once all checklist items are done:

1. **Run the document's `**Verification:**` command.** A task file carries one runnable command,
   and Complete is supposed to mean it passed. Run it **as its own Bash call**: no pipe, no
   `| tail`, no `|| true`, no `&&` chain. Its exit status is the entire point, and a pipe hands
   that status to another program. Keep the command and the tail of its output; Step 8 records
   them.
2. Run the full test suite (or the relevant subset for the area changed) to verify no regressions
3. Run the project's formatter and linter (e.g., `cargo fmt && cargo clippy`, `prettier`, `ruff`, etc., per the project's CLAUDE.md)
4. Build the project if applicable to confirm it compiles cleanly
5. If anything fails, fix the issues before marking the section complete

If the document has no Verification field, say so rather than inventing one, and do not mark it
Complete: a task with nothing runnable behind it belongs in the fast lane, not the pipeline.

## Step 8: Mark the Section Complete

Update the document:

- Set the row for the section in the existing **Progress Summary** table to 🟢 COMPLETE
- Change the section's **Status** field to "Complete" if present
- Check off **only the acceptance criteria you actually checked** (`[ ]` -> `[x]`). A criterion
  nobody verified stays unticked and is named in the log entry. Ticking the whole list because the
  work feels done is the habit this step exists to break.
- Update the **Last Updated** date
- Append a final entry to the same log Step 6 appended to, naming the command and what it printed
  rather than asserting success:

  ```
  ### [Date] - <section> Complete
  - Verification: `<the command from the document>` -> <exit status and the last line or two>
  - [Criteria met, and any left unticked with the reason]
  - [Any notable decisions or deviations]
  ```

  "All tests passing, build clean" is not evidence; it is the claim the evidence is supposed to
  support. A Stop hook independently checks that the Verification command ran as its own command
  this session, so a Complete status without one will refuse to end the turn.

## Step 9: Commit the Spec Repo (Documents Only)

An `/sdd:implement` run touches two places: product code in the main repo, and the plan or task document. They are committed by different rules.

- **The document.** If the document lives inside a nested spec repo, the status updates from Step 8 must be committed and pushed in this same turn, per the spec-repo commit policy:
  ```sh
  git -C .specs add -A && git -C .specs commit -m "<task/phase> status: <what changed>" && git -C .specs push
  ```
  Skip the push if the repo has no `origin` remote.
- **The product code.** Stays uncommitted. Never `git add`/`commit`/`push` in the main repo. Step 10 suggests a message; the user commits it themselves.

The Status field and Progress Summary table in the task document are the durable record of progress. Any scratch ledger a subagent workflow keeps outside the spec repo is disposable and is not a substitute.

## Step 10: Present Summary

Report to the user:

- What was implemented (high-level)
- Files created or modified
- Test results
- Any deviations from the section's spec and why
- Any follow-up work that surfaced (note it in the document's **Future Considerations** or as a new section if appropriate)

## Step 11: Suggest a Commit Message

**You MUST invoke the `sdd:commit-msg` skill via the Skill tool to do this — do not hand-write a message inline.** The skill analyzes the diff and recent git log and produces both a short (one-line) and a long (subject + body) version; an inline message you compose yourself is not a substitute and skips that analysis.

This step is required, not optional: always run it as the final step of an `/sdd:implement` run. Do **not** run `git commit` unless explicitly asked.

## Repeating

If the user asks to continue with the next section, repeat from Step 1 with the new section.
