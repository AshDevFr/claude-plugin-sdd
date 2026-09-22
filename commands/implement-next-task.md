---
argument-hint: [tasks-dir]
description: Find the next incomplete task and implement it
---

Find and implement the next task. This is a thin wrapper that composes the `sdd:next-task` and `sdd:implement` skills.

## Arguments

The arguments arrive as one string in `$ARGUMENTS`. Read them from there:

- **the tasks directory** — all of `$ARGUMENTS`, or empty

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1`
binds to the **second** token, and typed as a slash command it arrives as the literal text
`$1`. Neither is the first argument. `$ARGUMENTS` is correct on both paths.

**Tasks directory**: from `$ARGUMENTS`, or empty

## Step 1: Find or Create the Next Task

Invoke the **`sdd:next-task`** skill via the Skill tool, passing the tasks directory as its argument (or no argument if none was provided — `next-task` will resolve paths from CLAUDE.md or ask).

The `sdd:next-task` skill will either:

- Return the absolute path to the first incomplete task in the tasks directory, or
- Create a new task file from the current spec and return its path

If `sdd:next-task` cannot determine a next task (e.g., no spec exists for the next phase, or the user needs to clarify which work item to draft), **stop and forward the message to the user**. Do not proceed to Step 2.

Capture the returned task path. You will also want the task title (the first H1 heading, e.g., "Task 2.1: Team CRUD API") to pass as the section identifier in Step 2.

## Step 2: Implement the Task

Invoke the **`sdd:implement`** skill via the Skill tool, passing two arguments:

one string: **the absolute task path from Step 1, then a space, then the task title**
  (for example `/abs/path/2.01-crud.md Task 2.1: Team CRUD API`). The path must come first;
  `sdd:implement` reads `$ARGUMENTS` and takes the first token as the document.

The `sdd:implement` skill handles everything from here:

- Reads the task and the relevant codebase
- Marks the task active (Status → In Progress)
- Builds a TodoWrite checklist from the acceptance criteria
- Implements incrementally with TDD
- Updates the Progress Summary table and Progress Notes as it goes
- Runs the localized tests, then formatter and linter
- Marks the task Complete and checks off acceptance criteria
- Suggests a commit message via `/sdd:commit-msg`

## Step 3: Suggest the Next Iteration

After `sdd:implement` finishes, briefly tell the user:

- Which task was just completed (title and path)
- A one-line summary of what shipped
- Suggest running `/sdd:implement-next-task` again to continue with the next task in the queue
