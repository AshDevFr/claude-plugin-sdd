---
name: spec-template
description: Canonical phase spec file template and usage guidance for the project task workflow. Use when generating per-phase spec files from a PRD (e.g., from /sdd:generate-specs).
---

# Phase Spec File Template

The canonical template for per-phase spec files. A spec is a focused plan for one phase of a multi-phase project, listing the work items (tasks) that make up that phase.

## When to Use

- Splitting a PRD into per-phase specs (`/sdd:generate-specs`)
- Creating a single new phase spec by hand
- Validating an existing spec's structure
- Describing the spec file format to a user

## Where the Template Lives

The canonical template is `spec.md`, **in this skill's own directory**. The harness
reports that directory when this skill loads; the template sits beside `SKILL.md`.

**Read it directly** when you need the full content. Do not duplicate the template here — the file is the single source of truth.

## Quick Reference

A spec file MUST include:

- **Title** — H1 with phase number and name, e.g., `# Phase 2: Teams & Multi-Agent - Spec`
- **Metadata** — Status, Created, Last Updated, PRD link, Estimated Completion
- **Quick Links** — PRD, related specs, dependencies, blockers
- **Tasks Summary** — table listing the tasks within this phase
- **Phase Objective** — what this phase delivers
- **Success Criteria** — measurable outcomes (checkboxes)
- **Context & Background** — current state, motivation, affected systems
- **Technical Approach** — architecture, stack, data model, API design, integration
- **Tasks (Work Items)** — detailed per-task subsections (objective, scope, file plan, acceptance criteria, testing, notes)
- **Testing Strategy** — phase-wide testing approach
- **Deployment & Rollout** — if applicable
- **Documentation Requirements** — what needs to be documented
- **Future Considerations** — known limitations, enhancements
- **Progress Tracking** — append-only log

## Usage

To generate a spec file:

1. Read `spec.md` from this skill's directory
2. Substitute placeholders:
   - `N` → actual phase number
   - `[Phase Name]` → phase title from the PRD
   - `[Date]` → today's date in `YYYY-MM-DD` format
   - All other `[bracketed]` placeholders → real content from the PRD
3. Populate the **Tasks (Work Items)** section with one subsection per task in the phase, including enough detail for `/sdd:generate-tasks` to expand each into a standalone task file
4. Write the result to the resolved specs directory (typically `docs/specs/phase-N_<title>.md` or `docs/specs/phase-N-<slug>.md` depending on project convention)

If a target file already exists with meaningful content, **preserve it** rather than overwriting. Restructure into the template only if doing so does not lose information.

## Adapting the Template

Skip sections that add no value for a particular phase. A foundation phase may not need a deployment section; a polish phase may not need a data model section. Use judgment.

## Companion Skills

- **`sdd:resolve-task-paths`** — resolve where to write the spec file
- **`sdd:task-template`** — for the per-task files generated from this spec
- **`sdd:plan-template`** — for the higher-level plan that organizes phases (less common when starting from a PRD)

## Acceptance criteria that can be checked

Keep the checkbox structure exactly as the template has it. What changes is what goes inside a
checkbox.

Where the behaviour is observable, phrase the criterion **Given / When / Then with concrete
values**, because a criterion is only useful if two people would agree on whether it is met:

- [ ] **SC-01:** Given three widgets in the store, when `GET /widgets` is called, then the
      response is 200 and a JSON array of length 3

Against the same criterion written the usual way:

- [ ] GET /widgets returns a JSON array

The second passes against an empty array, against a 500 with a JSON body, and against a stub that
returns `[]` unconditionally. It is not wrong, it is unfalsifiable, which is the same problem the
`**Verification:**` field has and the same fix.

Not every criterion earns it. "The page fetches nothing over the network" is already unambiguous
and Given/When/Then would pad it. Use it where the disagreement is possible: counts, statuses,
boundaries, ordering, error cases.

## Numbering criteria, so something can point at one

A phase spec's **Success Criteria** are numbered `SC-01`, `SC-02`, in bold at the head of the
checkbox. The numbers are local to the spec, so phase 1's `SC-01` and phase 2's `SC-01` are
different criteria and nothing outside a phase should refer to one by number alone. Per-task
**Acceptance Criteria** inside this spec use `AC1`, `AC2`, matching the task files.

A spec criterion is what a task's `(covers SC-NN)` annotation points at. That annotation is the
only thing connecting the two: `/sdd:analyze` reports a success criterion no task claims to cover,
and it reads the annotations rather than inferring coverage from prose, deliberately. Inferring it
would turn a wording coincidence into a claim that the work is accounted for.

**Numbers are never reused and never renumbered.** A criterion added later takes the next free
number. Renumbering silently rewrites every reference already written into a task file.

All of it is optional. A spec with no numbered criteria stays valid, and analyze reports nothing
about coverage rather than reporting it as missing.

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
