---
name: plan-template
description: Canonical implementation plan template and usage guidance. Use when creating a structured implementation plan for a feature or initiative (e.g., from /sdd:plan), where the plan organizes work into multiple phases.
---

# Implementation Plan Template

The canonical template for a structured, multi-phase implementation plan.

## When to Use

- Creating a new implementation plan (`/sdd:plan`)
- Validating an existing plan's structure
- Describing the plan format to a user

## Plan vs. Spec vs. Task

It is easy to confuse the three workflow documents. Quick disambiguation:

- **Plan** — a single document covering an entire initiative across multiple phases. Created with `/sdd:plan`. Use this when the work is a self-contained feature or refactor that does not warrant a full PRD.
- **Spec** — a per-phase document, one per phase, derived from a PRD. Created with `/sdd:generate-specs`. Use this when the project has a PRD and you want phase-level detail.
- **Task** — a per-work-item document, one per concrete deliverable. Created with `/sdd:generate-tasks` or `/sdd:next-task`. Always the smallest unit.

A plan can contain phase breakdowns inline (no separate spec files needed), or you can promote each phase into its own spec for larger projects.

## Where the Template Lives

The canonical template is `plan.md`, **in this skill's own directory**. The harness
reports that directory when this skill loads; the template sits beside `SKILL.md`.

**Read it directly** when you need the full content. Do not duplicate the template here — the file is the single source of truth.

## Quick Reference

Most of the template adapts to the work. These six sections do not, because other parts
of the workflow read them:

- **Title** - H1 with feature name, e.g., `# Cross-Workspace Search - Implementation Plan`
- **Metadata** - Status, Created, Last Updated, Estimated Completion
- **Quick Links** - related docs, dependencies, blockers
- **Progress Summary** - the phase table, **whenever the plan has more than one phase**
- **Implementation Phases** - Phase 1, Phase 2, ... each with objectives and tasks
- **Progress Tracking** - append-only dated log

**The Progress Summary table is the one most often dropped, and the one that costs most.**
It is not decoration. `/sdd:implement` writes into it (a phase row goes 🟡 IN PROGRESS when
work starts and 🟢 COMPLETE when it lands), and `spec-inventory.py` in
`sdd:tidying-spec-repos` counts its status cells to report how far a plan has got. A plan
without the table does not fail loudly: `/sdd:implement` skips the update silently and the
inventory reports the plan as 0/0 forever. Write the table whenever there are phases to put
in it, however small the plan, and keep its rows in step with the `### Phase N` headings.

Everything below is included when it earns its space and omitted when it does not:
Executive Summary, Context & Background, Technical Approach, Testing Strategy, Deployment &
Rollout, Documentation Requirements, Future Considerations.

## Usage

To generate a plan file:

1. Read `plan.md` from this skill's directory
2. Substitute placeholders:
   - `[Feature Name]` → the initiative title
   - `[Date]` → today's date in `YYYY-MM-DD` format
   - All other `[bracketed]` placeholders → real content from the user's spec or your prior research
3. Adapt the template to scope: a small bug fix does not need every section. Skip or collapse sections that would otherwise be trivial, but keep the six in Quick Reference.
4. Write the result to the path the user specified

If a target file already exists with meaningful content, **preserve it** rather than overwriting. Incorporate it into the template's structure rather than discarding it.

## Adapting the Template

The template is comprehensive on purpose: it covers what a complex plan needs. For smaller
plans, collapse or omit sections that do not earn their space. Use judgment. The goal is a
self-contained brief that gives a developer full context at a glance, not a rigid form to
fill in.

That judgment stops at the six sections in Quick Reference. They are small, they are cheap
to write, and dropping one breaks something downstream rather than merely shortening the
document. A one-hour, three-phase plan still gets the Progress Summary table.

## Companion Skills

- **`sdd:spec-template`** — for promoting a plan's phases into standalone spec files (uncommon, but useful for large initiatives)
- **`sdd:task-template`** — for the per-task files generated from a plan's phases

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
