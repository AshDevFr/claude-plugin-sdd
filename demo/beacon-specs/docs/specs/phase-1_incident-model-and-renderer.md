# Phase 1: Incident model and renderer - Spec

**Status:** 🟢 Complete 2026-09-01
**Created:** 2026-08-25
**Last Updated:** 2026-09-01
**PRD:** `docs/PRD.md`
**Estimated Completion:** 2026-09-01 (met)

## Quick Links

- PRD: `docs/PRD.md`
- Related Specs: `phase-2_the-public-page.md`
- Designs: `docs/designs/2026-08-26-storage-format.md`
- Dependencies (other phases): none
- Blocked By: nothing

## Tasks Summary

| Task | Status | Description |
| ---- | ------ | ----------- |
| 1.01 | 🟢 COMPLETE | Incident and Update model with validation |
| 1.02 | 🟢 COMPLETE | Load and order incidents from TOML |
| 1.03 | 🟢 COMPLETE | Overall state from the open incidents |
| 1.04 | 🟢 COMPLETE | Render incidents to self-contained HTML |
| 1.05 | 🟢 COMPLETE | The `check` and `render` commands |

## Phase Objective

Turn a file of incidents into a correct page. Correct, not presentable: phase 2 owns how it looks.
This phase ends when `./beacon-cli render examples/incidents.toml` produces a page whose facts are
right and whose ordering is defensible.

## Success Criteria

- [x] A malformed file produces an error naming the incident and the field.
- [x] Open incidents sort above resolved ones, newest first within each group.
- [x] The headline is the worst severity still open, and resolved incidents never set it.
- [x] The rendered page fetches nothing over the network, enforced by a test.
- [x] `check` exits non-zero while an incident is open.

## Context & Background

### Current State

Nothing. Incidents live in a spreadsheet nobody updates and a Slack channel nobody can link to.

### Motivation

Everything else in the PRD needs a model to build on, and the ordering rules are where the product
judgment lives. Getting them wrong in phase 1 makes every later phase wrong quietly.

### Affected Systems

New repository. No existing system is touched.

## Technical Approach

### Architecture Overview

Three modules, one direction of dependency: `model` knows nothing about HTML, `render` knows
nothing about files, `cli` knows about both and about the filesystem. That is what makes the
renderer testable without a temp directory in every test.

### Technology Stack

- **Language:** Python 3.11+
- **Libraries:** standard library only, `tomllib` for parsing
- **Tools:** `unittest`, run through `./run-tests`

### Data Model

`Incident` carries id, title, severity, started, optional resolved, components and a list of
`Update`. Both use `__slots__`: not for memory, but so a typo in an attribute name fails loudly
instead of silently creating a field.

### Ordering rules

Open before resolved, then newest first. **This is the phase's one real product decision.** A
reader arriving during an outage wants the thing that is broken now, not the most recent thing
that happened. Within an incident, updates render newest first for the same reason, while being
stored oldest first because that is the order they are written in.

## Out of Scope

- Anything about how the page looks. Phase 2.
- Notifications, subscriptions, feeds. Phase 3.
- Pagination. Noted as a future task at around 600 incidents; we have 3.

## Risks

| Risk | Mitigation |
| --- | --- |
| The severity scale is wrong and the model bakes it in | Deferred to phase 2 with its own design record, after reading the incident log |
| Timezones handled inconsistently | Every time is UTC, parsed by `tomllib` as an aware datetime; no format strings anywhere |

## Verification

`./run-tests` - 27 tests at the close of this phase, all passing.
