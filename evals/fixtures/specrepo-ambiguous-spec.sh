#!/usr/bin/env bash
# A spec repo whose phase spec carries two open markers and one unquantified adjective, so
# /sdd:clarify has something real to work down.
#
# The markers are deliberately unequal. The retention one is answerable from the prompt the
# eval supplies; the auth one is not, and is there so the run has something it must report as
# still open rather than resolve. A fixture where everything can be answered would let a run
# that quietly guesses look identical to one that asked.
#
# "fast" in SC-02 is the third kind: nothing declared it undecided, and it is undecided anyway.
set -euo pipefail
r="$1"
"$(dirname "$0")/specrepo.sh" "$r"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }
cat > "$r/.specs/docs/specs/phase-1_audit-log.md" <<'MD'
# Phase 1: Audit log - Spec

**Status:** 🔵 Planning
**Created:** 2026-09-01
**Last Updated:** 2026-09-01

## Quick Links

- PRD: `docs/PRD.md`

## Tasks Summary

| Task | Status         | Description          |
| ---- | -------------- | -------------------- |
| 1.01 | 🔵 NOT STARTED | Write audit records  |
| 1.02 | 🔵 NOT STARTED | Read audit records   |

## Phase Objective

Record what changed, who changed it and when, so an operator can answer a question about the
past without reading application logs.

## Success Criteria

- [ ] **SC-01:** Given a widget update, when it commits, then an audit record exists naming the
      actor, the widget and the time
- [ ] **SC-02:** Reading the audit log is fast

## Context & Background

### Current State

Nothing records changes. The application logs carry some of it, unstructured, and they rotate
after seven days.

### Motivation

An operator asked who deleted a widget and nobody could answer.

## Technical Approach

Records are appended on commit and never updated in place.

Records are kept for [NEEDS CLARIFICATION: how long are audit records retained before deletion?]

Reads are authorised by [NEEDS CLARIFICATION: which roles may read the audit log, and is an
actor allowed to read their own records?]

## Tasks (Work Items)

### Task 1.01: Write audit records

#### Objective
Append one record per committed change.

#### Acceptance Criteria
- [ ] **AC1:** Given a widget update, when it commits, then exactly one record is appended
      (covers SC-01)

### Task 1.02: Read audit records

#### Objective
Expose the log to an operator.

#### Acceptance Criteria
- [ ] **AC1:** Given 10000 records, when the log is queried by widget, then the matching records
      are returned
MD
g "$r/.specs" add -A
g "$r/.specs" commit -qm "Add the phase 1 spec"
