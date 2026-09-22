---
argument-hint: [spec-file] [tasks-dir]
description: Generate task files from a phase spec
---

Generate one task file per work item from a phase spec.

## Arguments

The arguments arrive as one string in `$ARGUMENTS`. Read them from there:

- **the spec path** — the first token
- **the tasks directory** — the rest

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1`
binds to the **second** token, and typed as a slash command it arrives as the literal text
`$1`. Neither is the first argument. `$ARGUMENTS` is correct on both paths.

**Spec file** and **tasks directory** come from `$ARGUMENTS`, in that order.

## Step 0: Resolve Paths

Use the **`sdd:resolve-task-paths`** skill to resolve the spec path, tasks directory, and task file pattern. Pass both, in order, as the args; the skill will fall back to the project's CLAUDE.md `## Task Workflow` section, then ask the user if needed.

If the spec file does not exist, stop and tell the user.

## Step 1: Read the Spec

Read the spec file in full. Extract:

- Phase number and name
- The "Tasks (Work Items)" section
- Per task: objective, scope, file plan, acceptance criteria, testing strategy, dependencies, implementation notes

If the spec lacks a clear task breakdown, **stop and ask the user** how to split the work. Do not invent tasks.

## Step 2: Read Supporting Documents

For full context:

- The PRD (path resolved in Step 0) for architecture and design decisions
- The project's CLAUDE.md for conventions, structure, and coding standards
- Any related specs to understand inter-phase dependencies

## Step 3: Read Existing Tasks

Read all existing files in the tasks directory (sorted by number) to understand:

- What is already planned (avoid duplicates)
- The numbering convention in use
- The dependency chain from prior phases
- Patterns and formatting used in existing task files

## Step 4: Read the Codebase

Read relevant codebase files referenced in the spec's file plans. Use the project structure in CLAUDE.md, existing task files, and the spec to guide what to read. This context is critical for writing accurate file plans and implementation notes in each task.

## Step 5: Plan the Task Files

Before writing anything, plan the full task list for this phase:

- One task file per work item from the spec
- Number per the configured file pattern (e.g., `2.01`, `2.02`, ...)
- Order by dependency (within this phase and across phases)
- Determine file plan, acceptance criteria, testing strategy, and implementation notes per task

Present the planned task list to the user (task number, title, one-line description) and **ask for confirmation** before generating any files.

## Step 6: Generate Task Files

After confirmation, write each task file using the **`sdd:task-template`** skill. That skill owns the canonical template and tells you where to read it from. Substitute placeholders with content from the spec, and adapt to the task (skip sections that add no value).

**Where the source is ambiguous, write `[NEEDS CLARIFICATION: <the question>]` rather than
guessing.** A guess is indistinguishable from a decision once it is written down: the next reader
sees a specification, not an assumption, and the assumption becomes load-bearing without anyone
having agreed to it. A marker is visible, greppable, and costs one question to resolve.

Put the marker in place of the content, not beside it, and make the question answerable:
`[NEEDS CLARIFICATION: which HTTP stack, stdlib http.server or FastAPI?]` rather than
`[NEEDS CLARIFICATION: unclear]`. List every marker you wrote in your summary, so the user can
answer them all in one reply instead of discovering them later.

**Number every acceptance criterion `AC1`, `AC2`, and say which spec criterion it covers.** The
number is what lets a later finding name a requirement instead of gesturing at a file: converge
can say `2.03/AC2` is unmet, and `/sdd:analyze` can report a spec criterion no task covers. Write
`- [ ] **AC1:** Given ..., when ..., then ... (covers SC-02)`, taking the `SC-NN` from the spec's
Success Criteria where one applies. Leave the annotation off where none does; a wrong `covers` is
worse than none, because it reports the requirement as accounted for.

Numbers are never reused and never renumbered, in this run or any later one. A criterion added to
an existing file takes the next free number even where that puts `AC7` between `AC2` and `AC3`,
because every reference already written elsewhere points at the old numbering.

**Before writing each `**Verification:**` field, ask: could this command pass if the work were
not done?** `echo ok` always passes. So does a command that does not touch what changed, and so
does a suite that has no test for the behaviour yet. If the answer is yes, the field is
decoration: name the command that would actually fail, or say in the task that the verification
has to be written as part of it. A Stop hook checks that the command ran, and cannot tell a real
check from one that cannot fail. That part is yours.


Write each file to the resolved tasks directory using the configured file pattern (e.g., `2.01-team-crud-api.md`). Create the phase subdirectory if your pattern uses one (e.g., `tasks/phase-2/`).

If a task file at the target path already exists with meaningful content, **preserve it** and skip or merge rather than overwriting.

## Step 7: Update the Spec

Update the spec's "Tasks Summary" table to reference the generated task files (e.g., add a path or link in the Description column). Update the spec's **Last Updated** date.

## Step 8: Commit the Spec Repo

If the tasks directory lives inside a nested spec repo, commit and push in this same turn, per the spec-repo commit policy, before reporting:

```sh
git -C .specs add -A && git -C .specs commit -m "Generate phase-N task files" && git -C .specs push
```

Skip the push if the repo has no `origin` remote. Never touch the main repo's index.

## Step 9: Present Summary

Briefly report to the user:

- Total number of tasks created and the path to the tasks directory
- The dependency graph (which tasks depend on which)
- Any notes, concerns, or open questions about the phase plan
- Suggest using `/sdd:implement-next-task` to start working through them, or `/sdd:implement <task-file>` to jump to a specific one
