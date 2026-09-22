# Phase 2: The public page - Spec

**Status:** 🟡 In progress since 2026-09-03, 4 of 6 tasks done
**Created:** 2026-09-02
**Last Updated:** 2026-09-14
**PRD:** `docs/PRD.md`
**Estimated Completion:** 2026-09-19

## Quick Links

- PRD: `docs/PRD.md`
- Plan: `docs/plans/2026-09-03-phase-2-public-page.md`
- Designs: `docs/designs/2026-09-02-severity-scale.md`, `docs/designs/2026-09-08-static-vs-server.md`
- Mockups: `docs/designs/mockups/2026-09-12-status-page/`
- Blocked By: nothing, but 2.06 needs the severity palette chosen on the mockup

## Tasks Summary

| Task | Status | Description |
| ---- | ------ | ----------- |
| 2.01 | 🟢 COMPLETE | Four-level severity scale replacing the five-level sketch |
| 2.02 | 🟢 COMPLETE | Inline the stylesheet and prove the page fetches nothing |
| 2.03 | 🟢 COMPLETE | Human-readable incident durations |
| 2.04 | 🟢 COMPLETE | Timeline with newest update first |
| 2.05 | 🟡 IN PROGRESS | Phone layout down to 360 px |
| 2.06 | 🔴 BLOCKED | Severity palette, waiting on the owner's pick |

## Phase Objective

Make the page something you would put in front of a customer during an outage. The facts were
right at the end of phase 1; this phase is about whether someone under stress can read them.

## Success Criteria

- [x] Four severities, each visually distinguishable, including in dark mode.
- [x] The page makes no external requests, enforced by a test.
- [x] A resolved incident states how long it lasted, in words.
- [x] The newest update in an incident appears first.
- [ ] No horizontal scrolling at 360 px.
- [ ] The palette is legible for the most common forms of colour blindness.

## Context & Background

### Current State

Phase 1 renders a correct page with one unstyled block per incident. It is accurate and nobody
would link a customer to it.

### Motivation

The page exists to be read at four in the morning by someone who is worried. Every decision in
this phase is about that reader, which is why the palette is going to the owner rather than being
chosen here.

### Affected Systems

`beacon/render.py` only. The model is finished and this phase does not touch it.

## Technical Approach

### Architecture Overview

The whole of this phase is `render.py` and its tests. The CSS is a single inlined string; there is
no build step and there will not be one, because a build step is a thing that can fail between an
incident being written and the page going up.

### Severity and colour

Four levels from `docs/designs/2026-09-02-severity-scale.md`. Colour alone never carries the
meaning: every severity is also a word, because the palette is the part most likely to be wrong
for a given reader.

### Responsive approach

One breakpoint, not a grid system. The layout is a single column at every width; the phone work is
about padding, the timeline's left rule, and making the badge wrap without pushing the timestamp
off the edge.

## Out of Scope

- Notifications and feeds. Phase 3.
- The embeddable widget. Phase 4.
- Per-viewer timezones, which the static-render decision rules out entirely.

## Open questions

- **Which severity palette?** Four candidates are on the mockup at
  `docs/designs/mockups/2026-09-12-status-page/severity.html`. Task 2.06 is blocked on the answer.
- Timeline density at 360 px: the mockup asks this too, as a second group on the same page.

## Verification

`./run-tests` - 36 tests, all passing as of 2026-09-14.
