---
name: resolve-task-paths
description: Resolve PRD, specs directory, tasks directory, and task file pattern from command arguments or the project's CLAUDE.md `## Task Workflow` section. Use at the start of any task-workflow command (/sdd:generate-specs, /sdd:generate-tasks, /sdd:next-task, /sdd:implement-next-task) before reading or writing files.
---

# Resolve Task Workflow Paths

Resolve the project paths used by the task workflow commands. Returns a single canonical set of paths the calling command can rely on.

## Resolution Order

For each path the calling command needs:

1. **Args first.** If the calling command was invoked with explicit path arguments (e.g., `/sdd:generate-tasks <spec-file> <tasks-dir>`), use those. Args always win.
2. **CLAUDE.md fallback.** Read the project's CLAUDE.md and look for a `## Task Workflow` section. These are the canonical keys:

   ```markdown
   ## Task Workflow

   - **Spec Repo**: `.specs/` (remote `https://example.com/team/<project>-specs.git`)
   - **PRD**: `.specs/docs/PRD.md`
   - **Implementation Plan**: `.specs/docs/plans/<name>.md` (or "none")
   - **Phase Specs**: `.specs/docs/specs/phase-N_<title>.md`
   - **Task Directory**: `.specs/docs/tasks/phase-N/`
   - **Task File Pattern**: `N.NN-descriptive-name.md`
   - **Spec Model**: `flow-back` (or `flow-forward`, or `living`)
   ```

   Note: the **Phase Specs** and **Task Directory** values can either be a literal directory path or include a phase placeholder like `phase-N`. Substitute the phase number when generating files. Some projects use a different unit (e.g. `feature-N`); follow whatever the project's own keys say.

   Older projects may use a project-named spec directory (`.codex/`, `.tsundoku/`) instead of `.specs/`. Their CLAUDE.md keys are authoritative for *resolution*: read the paths, do not rewrite them.

   **But the hooks only fire for `.specs/`.** The commit guard, the verification gate, the rules emission and the learnings capture all test for `.specs/.git` specifically. In a project using another name the commands work and none of the enforcement does, silently. Report that when you detect it, and say the fix is to rename the directory to `.specs`.

3. **Spec repo detection.** Independently of the keys, check whether `.specs/.git` exists at the repo root (or the dir named by **Spec Repo**). If it does, the resolved paths live inside a nested spec repo, and the caller must apply the spec-repo commit policy after writing. Report this to the caller.

4. **Ask the user** if neither args nor CLAUDE.md provide the value. Ask only for paths the calling command actually needs — do not pre-emptively ask for everything.

## Defaults

Apply these only when the calling command does not require a specific value and none was provided:

- **Spec Model**: `flow-back`, which is what a project that never declared one has been doing
- **Spec Repo**: `.specs/` if `.specs/.git` exists, otherwise none
- **Task File Pattern**: `N.NN-descriptive-name.md` (e.g., `2.01-team-crud-api.md`)
- **Specs directory**: `.specs/docs/specs/` when a spec repo exists, else `./specs/`
- **Tasks directory**: `.specs/docs/tasks/` when a spec repo exists, else `./tasks/`

Never default to another tool's own docs directory, a top-level `docs/plans/`, or `tmp/`. If a command is about to write a planning document into the main repo, stop and say so.

## The Spec Model, and why the caller needs it

**Report it to the caller along with the paths.** It says what happens to a document when the
requirement behind it changes, which is a question every command that proposes an edit is already
answering, silently and differently each time.

| Model | What it means | What a command may propose |
|---|---|---|
| `flow-back` | any document may be edited, and the set is reconciled afterwards | editing a Complete task's criteria, then reconciling the spec |
| `flow-forward` | a Complete document is a record | a new task or spec referencing the old one. **Never propose editing a Complete task's criteria** |
| `living` | the spec is the contract and tasks are derived from it | editing the spec, then revising the tasks under it |

**`flow-back` is the default for a project that declares nothing**, because it describes what
those projects already do: this suite's own remediation log has a "Deviations from the plan as
written" section, which is flow-back by another name. The default is a description, not a
recommendation.

Say which model is in force when you report, and say whether it was declared or defaulted. A
command told `flow-back` by default and a command told `flow-back` deliberately should behave the
same way, but the owner reading the report should be able to tell which happened.

## Validation

After resolving:

- **Verify input files exist** when the command needs to read them (e.g., the PRD for `/sdd:generate-specs`, the spec file for `/sdd:generate-tasks`). If a required input is missing, **stop and report to the user** rather than improvising.
- **Do not pre-create output directories.** Let the writing step create them as needed.
- **Resolve paths to absolute form** when possible, so downstream tool calls do not depend on the current working directory.

## Project Layout Conventions Seen in the Wild

These are common layouts you may encounter via CLAUDE.md. The skill handles all of them:

- **Flat layout**: all task files in a single directory (e.g., `docs/tasks/1.01-...md`, `docs/tasks/1.02-...md`)
- **Per-phase subdirectory**: tasks grouped by phase (e.g., `docs/tasks/phase-1/1.01-...md`, `docs/tasks/phase-2/2.01-...md`)
- **Per-phase spec files**: named `phase-N_<title>.md` or `phase-N-<slug>.md`

When the layout is per-phase, derive the phase number from the spec being processed (or from the next-task heuristics) and substitute into the configured path template.

## Returning to the Caller

When you finish, return a clear summary to the calling command:

- Each resolved path (PRD, spec, tasks dir, file pattern)
- Whether each came from args, CLAUDE.md, defaults, or user input
- Whether the paths are inside a nested spec repo, and if so its directory (so the caller can apply the commit policy)
- Any defaults that were applied
- Any input file that does not exist (so the caller can stop)

Keep the report short — the caller will use these values immediately.
