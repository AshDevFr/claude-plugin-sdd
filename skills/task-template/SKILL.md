---
name: task-template
description: Canonical task file template and usage guidance for the project task workflow. Use when creating, validating, or describing task files (e.g., from /sdd:generate-tasks or /sdd:next-task).
---

# Task File Template

The canonical template for individual implementation task files.

## When to Use

- Creating a new task file (`/sdd:generate-tasks`, `/sdd:next-task`)
- Validating an existing task file's structure
- Describing the task file format to a user

## Where the Template Lives

The canonical template is `task.md`, **in this skill's own directory**. The harness
reports that directory when this skill loads; the template sits beside `SKILL.md`.

**Read it directly** when you need the full content. Do not duplicate the template here — the file is the single source of truth.

## Quick Reference

A task file MUST include:

- **Title** — H1 with task number, e.g., `# Task 2.1: Team CRUD API`
- **Metadata** — Status, Phase, Priority, Depends On, **Verification**, Created, Last Updated
- **Progress Summary** — table tracking each implementation step (🔵/🟡/🟢)
- **Objective** — what this task accomplishes and why
- **Scope** — explicit In Scope and Out of Scope sections
- **File Plan** — tree of files to create or modify
- **Implementation Notes** — design decisions, patterns, references
- **Acceptance Criteria** — checkboxes (unchecked at draft time)
- **Testing Strategy** — specific tests, what they verify
- **Progress Notes** — append-only log at the bottom

## The Verification field is mandatory

One runnable command that proves the task is done. Not a description of testing, not a
list of criteria: a command someone can paste.

```
**Verification:** `./scripts/test-hooks.sh`
```

It is enforced. A `Stop` hook refuses to end a turn when a task became Complete this session and
that command did not run as its own command: a pipe, `|| true`, `; true`, an `echo` of the
command or a comment all read as "mentioned, not run", because each hands the exit status to
something other than the command. Scope comes from the spec repo's git state, so it makes no
difference whether an `Edit` call, a `sed -i` or a subagent wrote the status. So a Status of
Complete means the command ran and passed, rather than meaning someone believed it would.

Good: `cargo test -p parser`, `make lint`, `./run-tests`, `pytest tests/test_widgets.py`.
Bad: `run the tests` (not a command), `see Testing Strategy` (not runnable).

**The command must be capable of failing.** Before accepting it, ask: could this pass if the
work were not done? `echo ok` passes always. A command that does not touch what changed
passes always. Neither is a verification, and the Stop hook cannot tell the difference: it
sees only that a command ran and exited zero. That is the one thing the gate cannot check
for you.

If a task genuinely has no runnable verification, it probably should not be a task file.
The fitness rubric and the fast lane exist for that case.

## Usage

To generate a task file:

1. Read `task.md` from this skill's directory
2. Substitute placeholders:
   - `N.M` → actual task number (e.g., `2.01`)
   - `[Task Name]` → descriptive title
   - `[Date]` → today's date in `YYYY-MM-DD` format
   - All other `[bracketed]` placeholders → real content from the spec
3. Derive the **Progress Summary** rows from the task's acceptance criteria
4. Write the result to the resolved tasks directory using the configured file pattern (typically `P.NN-descriptive-name.md`)

If a target file already exists with meaningful content, **preserve it** rather than overwriting. Restructure into the template only if doing so does not lose information.

## Adapting the Template

Skip sections that add no value for a particular task. Small tasks do not need every field. The goal is a self-contained brief that gives whoever implements it full context, not a rigid form. Use judgment.

## Companion Skills

- **`sdd:resolve-task-paths`** — resolve where to write the task file
- **`sdd:spec-template`** — for the parent spec (which lists tasks)
- **`sdd:plan-template`** — for the higher-level plan (which lists phases)

## Acceptance criteria that can be checked

Keep the checkbox structure exactly as the template has it. What changes is what goes inside a
checkbox.

Where the behaviour is observable, phrase the criterion **Given / When / Then with concrete
values**, because a criterion is only useful if two people would agree on whether it is met:

- [ ] **AC1:** Given three widgets in the store, when `GET /widgets` is called, then the response
      is 200 and a JSON array of length 3 (covers SC-02)

Against the same criterion written the usual way:

- [ ] GET /widgets returns a JSON array

The second passes against an empty array, against a 500 with a JSON body, and against a stub that
returns `[]` unconditionally. It is not wrong, it is unfalsifiable, which is the same problem the
`**Verification:**` field has and the same fix.

Not every criterion earns it. "The page fetches nothing over the network" is already unambiguous
and Given/When/Then would pad it. Use it where the disagreement is possible: counts, statuses,
boundaries, ordering, error cases.

## Numbering criteria, so something can point at one

Each criterion is numbered `AC1`, `AC2`, in bold at the head of the checkbox. The number is local
to the file; from outside, a criterion is `<task>/AC1`, as in `2.03/AC1`.

Without this there is nothing to cite. A convergence finding can say a task is wrong, but not
which requirement is unmet, and `/sdd:analyze` cannot tell a spec criterion no task covers from
one that three tasks cover between them.

**Numbers are never reused and never renumbered.** A criterion inserted later takes the next free
number, even where that puts `AC7` between `AC2` and `AC3`. Renumbering rewrites the meaning of
every reference already written down elsewhere, and those references are the whole point.

Where a criterion fulfils one of the parent spec's success criteria, say so with `(covers SC-NN)`
at the end of the line. One criterion may cover several: `(covers SC-01, SC-03)`. Coverage is
declared, never inferred: `/sdd:analyze` reads these references and does not guess from prose,
which means a criterion nobody annotated reads as uncovered rather than as covered by accident.

All of it is optional. A task file with no numbered criteria stays valid and every command and
script keeps working on it; it simply cannot be cited.

## Assumptions, so a guess is visible

`## Assumptions` holds the defaults chosen where the input was silent. Writing one down costs a
line; not writing it down means the guess is indistinguishable from a decision the moment anyone
else reads the document, and it becomes load-bearing without a person having agreed to it.

It is not the same as `[NEEDS CLARIFICATION: ...]`, and the difference is whether the work can
proceed. A marker stops implementation and asks. An assumption says: this was undecided, here is
what was picked, here is what would overturn it, carry on. Use the marker where a wrong guess
would waste the work, and an assumption where it would cost one edit.

Cite the criterion each one affects. `/sdd:analyze` reports a criterion that is both assumed and
later clarified, which is the shape a stale default takes after a conversation overtakes it.

Delete the section if nothing was assumed. An empty Assumptions heading reads as "nothing was
guessed", which is a claim, not a formality.
