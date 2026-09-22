---
argument-hint: [prd-file] [specs-dir]
description: Generate per-phase spec files from a PRD
---

Generate one spec file per phase from a PRD.

## Arguments

The arguments arrive as one string in `$ARGUMENTS`. Read them from there:

- **the PRD path** — the first token
- **the specs directory** — the rest

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1`
binds to the **second** token, and typed as a slash command it arrives as the literal text
`$1`. Neither is the first argument. `$ARGUMENTS` is correct on both paths.

**PRD file** and **specs directory** come from `$ARGUMENTS`, in that order.

## Step 0: Resolve Paths

Use the **`sdd:resolve-task-paths`** skill to resolve the PRD path and specs directory. Pass both, in order, as the args; the skill will fall back to the project's CLAUDE.md `## Task Workflow` section, then ask the user if needed.

If the PRD file does not exist, stop and tell the user.

## Step 1: Read the PRD

Read the PRD in full. Identify:

- Product vision, scope, and architecture
- The phased delivery plan (phase number, name, goals, scope)
- Cross-cutting concerns (testing strategy, deployment, security)
- Constraints, non-functional requirements, dependencies between phases

If the PRD does not have a clear phase breakdown, **stop and ask the user** how to split it. Do not invent phases.

## Step 2: Read Existing Specs

Read any existing files in the specs directory to:

- Avoid overwriting work already in progress
- Match existing naming conventions (e.g., `phase-N_<title>.md` vs `phase-N-<slug>.md`)
- See which phases are already specified (and skip them, unless the user wants regeneration)

## Step 3: Plan the Spec Files

Determine the full set of spec files to generate:

- One spec per phase
- Use a clear naming scheme based on the phase number and a short descriptive slug, matching any convention seen in existing specs
- Skip phases that already have a meaningful spec file unless the user asks to regenerate

Present the planned spec list to the user (filename + one-line description per phase) and **ask for confirmation** before writing any files.

**Where the source is ambiguous, write `[NEEDS CLARIFICATION: <the question>]` rather than
guessing.** A guess is indistinguishable from a decision once it is written down: the next reader
sees a specification, not an assumption, and the assumption becomes load-bearing without anyone
having agreed to it. A marker is visible, greppable, and costs one question to resolve.

Put the marker in place of the content, not beside it, and make the question answerable:
`[NEEDS CLARIFICATION: which HTTP stack, stdlib http.server or FastAPI?]` rather than
`[NEEDS CLARIFICATION: unclear]`. List every marker you wrote in your summary, so the user can
answer them all in one reply instead of discovering them later.

## Step 4: Generate Spec Files

After confirmation, write each spec file using the **`sdd:spec-template`** skill. That skill owns the canonical template and tells you where to read it from. Substitute placeholders with content from the PRD, and adapt to the phase (skip sections that add no value).

**Number the phase's Success Criteria `SC-01`, `SC-02`.** They are what a task file's
`(covers SC-NN)` annotation points at, and what `/sdd:analyze` reads to report a criterion no task
covers. The numbers are local to the spec, so phase 1's `SC-01` and phase 2's `SC-01` are
different criteria. Never reuse or renumber one: a later criterion takes the next free number.

For each phase, populate the **Tasks (Work Items)** section with one subsection per task in the phase, including enough detail (objective, scope, file plan, acceptance criteria, testing strategy, implementation notes, dependencies) for `/sdd:generate-tasks` to expand each into a standalone task file later.

If a spec file already exists with meaningful content, **preserve it**. Restructure into the template if helpful, but do not lose information.

## Step 5: Commit the Spec Repo

If the specs directory lives inside a nested spec repo, commit and push in this same turn, per the spec-repo commit policy, before reporting:

```sh
git -C .specs add -A && git -C .specs commit -m "Generate phase-N specs" && git -C .specs push
```

Skip the push if the repo has no `origin` remote. Never touch the main repo's index.

## Step 6: Present Summary

Briefly report to the user:

- Specs directory path
- List of spec files generated (with one-line descriptions)
- Any phases skipped (and why)
- Any open questions or assumptions to validate
- Suggest using `/sdd:generate-tasks <spec-file>` to break each spec into individual task files
