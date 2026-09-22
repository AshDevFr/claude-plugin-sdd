#!/usr/bin/env bash
# A spec repo with a phase spec already written, so task generation has something to
# expand. Two work items, so "one task per work item" is checkable.
set -euo pipefail
r="$1"
"$(dirname "$0")/specrepo.sh" "$r"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }
cat > "$r/.specs/docs/specs/phase-1_http-surface.md" <<'MD'
# Phase 1: HTTP surface - Spec

**Status:** 🔵 Planning
**Created:** 2026-09-01

## Tasks Summary

| Task | Status         | Description            |
| ---- | -------------- | ---------------------- |
| 1.01 | 🔵 NOT STARTED | Health check endpoint  |
| 1.02 | 🔵 NOT STARTED | List widgets endpoint  |

## Tasks (Work Items)

### Task 1.01: Health check endpoint

#### Objective
Expose GET /healthz returning a status document.

#### Acceptance Criteria
- [ ] GET /healthz returns 200

### Task 1.02: List widgets endpoint

#### Objective
Expose GET /widgets returning every widget as JSON.

#### Acceptance Criteria
- [ ] GET /widgets returns a JSON array
MD
g "$r/.specs" add -A
g "$r/.specs" commit -qm "Add the phase 1 spec"
