#!/usr/bin/env bash
# A spec repo whose phase spec numbers its success criteria, so a generated task file has
# something real to point `(covers SC-NN)` at.
#
# One work item, not two. The question here is whether criteria come out numbered and
# annotated, and a second task file would only make the artefact grader pick one of two
# files to read.
#
# The two success criteria are deliberately unequal: SC-01 is what the work item delivers,
# SC-02 is a latency target the same endpoint can be held to. A run that annotates only what
# it can justify is behaving correctly, which is why the graders below ask for a `covers`
# reference at all rather than for both of them.
set -euo pipefail
r="$1"
"$(dirname "$0")/specrepo.sh" "$r"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }
cat > "$r/.specs/docs/specs/phase-1_widget-list.md" <<'MD'
# Phase 1: Widget list - Spec

**Status:** 🔵 Planning
**Created:** 2026-09-01

## Tasks Summary

| Task | Status         | Description           |
| ---- | -------------- | --------------------- |
| 1.01 | 🔵 NOT STARTED | List widgets endpoint |

## Success Criteria

- [ ] **SC-01:** Given three widgets in the store, when `GET /widgets` is called, then the
      response is 200 and a JSON array of length 3
- [ ] **SC-02:** Given a store of 1000 widgets, when `GET /widgets` is called, then it responds
      within 200ms

## Tasks (Work Items)

### Task 1.01: List widgets endpoint

#### Objective
Expose GET /widgets returning every widget as JSON.

#### File Plan
- `app/routes.py` - the endpoint
- `tests/test_routes.py` - its tests

#### Acceptance Criteria
- [ ] **AC1:** Given three widgets in the store, when `GET /widgets` is called, then the response
      is 200 and a JSON array of length 3 (covers SC-01)

#### Testing Strategy
- `python3 -m pytest tests/test_routes.py`
MD
g "$r/.specs" add -A
g "$r/.specs" commit -qm "Add the phase 1 spec"
