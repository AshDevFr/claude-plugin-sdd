---
argument-hint: [tasks-dir]
description: Identify (or create) the next task to work on
---

Identify the next task to work on. Find the first incomplete task in the directory if one exists, otherwise create a new one from the current spec.

## Arguments

The arguments arrive as one string in `$ARGUMENTS`. Read them from there:

- **the tasks directory** — all of `$ARGUMENTS`, or empty

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1`
binds to the **second** token, and typed as a slash command it arrives as the literal text
`$1`. Neither is the first argument. `$ARGUMENTS` is correct on both paths.

**Tasks directory**: from `$ARGUMENTS`, or resolved from CLAUDE.md when empty

## Step 0: Resolve Paths

Use the **`sdd:resolve-task-paths`** skill to resolve the tasks directory, spec/PRD locations, and file pattern. Pass the tasks directory as the arg; the skill will fall back to the project's CLAUDE.md `## Task Workflow` section, then ask the user if needed.

## Step 1: Find the Next Incomplete Task

**Do not read every task file.** A mature project has dozens, and pulling all of them into context
to find one status line costs more than the task that follows. Read the status lines only, in
number order, and stop at the first that is not Complete:

```sh
grep -m1 -H '^\*\*Status:\*\*' <tasks-dir>/**/*.md | sort -t/ -k2 -V
```

One line per file, in the order the file pattern implies. Then open **only** the first file whose
status is not Complete (Draft, In Progress, Blocked, and so on), plus anything its **Depends On**
names.

If the glob is unavailable, `find <tasks-dir> -name '*.md' | sort -V` and `grep -m1` each in turn,
stopping at the first match. The point is the stopping, not the tool.

- **If found**, this is the next task. **Report its absolute path** and stop. Suggest `/sdd:implement <task-path>` to begin working on it.
- **If every task is Complete (or no tasks exist yet)**, proceed to Step 2 to create a new one.

## Step 2: Read Project Documents

To create a new task, read for context:

- The PRD (path resolved in Step 0)
- The current or next phase spec (the one whose tasks come next in sequence)
- The project CLAUDE.md for conventions, structure, and coding standards

If no spec exists for the next phase of work, **stop and tell the user** to run `/sdd:generate-specs <prd>` (to produce specs from the PRD) or `/sdd:generate-tasks <spec>` (to bulk-generate tasks for a known spec). Do not invent work without a source document.

## Step 3: Determine the Next Task

Decide what the next logical task should be by:

- Following the spec's "Tasks (Work Items)" order, or if no spec, the PRD's phase plan
- **Checking dependencies** - never create a task whose prerequisites are still incomplete
- Matching granularity to the spec's task boundaries (one spec work item = one task file)
- Considering "Out of Scope" hints from the most recently completed task, which often signal what should come next

If the next logical task is ambiguous, **ask the user** which work item to draft rather than guessing.

## Step 4: Read the Codebase

Before writing the task file, read the relevant existing code:

- Files referenced in the spec's file plan for this work item
- Files in the same module or directory as the planned changes
- Existing tests covering the area being changed
- Code from the prerequisites this task depends on

This context is needed to write an accurate file plan and implementation notes.

## Step 5: Write the Task File

Write the new task file using the **`sdd:task-template`** skill. That skill owns the canonical template and tells you where to read it from. Substitute placeholders with content from the spec, and adapt to the task (skip sections that add no value).

**Number every acceptance criterion `AC1`, `AC2`, and annotate `(covers SC-NN)` where the phase
spec's Success Criteria are numbered.** The number is what lets converge name `2.03/AC2` instead
of gesturing at a file, and what lets `/sdd:analyze` report a spec criterion no task covers. Take
the `SC-NN` from the spec; leave the annotation off where none applies, because a wrong `covers`
reports a requirement as accounted for when it is not. Numbers are never reused and never
renumbered: a criterion added later takes the next free number.

**Before writing each `**Verification:**` field, ask: could this command pass if the work were
not done?** `echo ok` always passes. So does a command that does not touch what changed, and so
does a suite that has no test for the behaviour yet. If the answer is yes, the field is
decoration: name the command that would actually fail, or say in the task that the verification
has to be written as part of it. A Stop hook checks that the command ran, and cannot tell a real
check from one that cannot fail. That part is yours.


Write to the resolved tasks directory using the configured file pattern (e.g., `2.03-team-crud-api.md`). Create the phase subdirectory if your pattern uses one.

## Step 6: Commit the Spec Repo

Only if Step 5 actually wrote a new task file, and it lives inside a nested spec repo, commit and push it in this same turn, per the spec-repo commit policy:

```sh
git -C .specs add -A && git -C .specs commit -m "Add task N.NN <name>" && git -C .specs push
```

Skip the push if the repo has no `origin` remote. Never touch the main repo's index. If Step 1 found an existing incomplete task and nothing was written, there is nothing to commit.

## Step 7: Report the Next Task

Report to the user:

- The absolute path of the task to work on (the existing incomplete one from Step 1, or the newly created one from Step 5)
- The task title and a one-line summary of its objective
- Any open questions or assumptions that need validation
- Suggest `/sdd:implement <task-path>` to start working on it
