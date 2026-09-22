#!/usr/bin/env bash
# A project shaped like the real ones: a nested spec repo with a PRD, and a CLAUDE.md
# carrying the Task Workflow keys that resolve-task-paths parses.
set -euo pipefail
r="$1"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }
mkdir -p "$r/.specs/docs/specs" "$r/.specs/docs/tasks/phase-1" "$r/src"
cat > "$r/CLAUDE.md" <<'MD'
# widgetd

A small service.

## Task Workflow

- **Spec Repo**: `.specs/`
- **PRD**: `.specs/docs/PRD.md`
- **Phase Specs**: `.specs/docs/specs/phase-N_<title>.md`
- **Task Directory**: `.specs/docs/tasks/phase-N/`
- **Task File Pattern**: `N.NN-descriptive-name.md`
MD
cat > "$r/.specs/docs/PRD.md" <<'MD'
# PRD: widgetd

## Goals

Serve widgets over HTTP with an audit trail.

## Phased delivery

### Phase 1 - HTTP surface

Scope: a read-only endpoint listing widgets, and a health check.

### Phase 2 - Audit trail

Scope: append every read to a durable log, and expose it.
MD
echo "print('hi')" > "$r/src/main.py"
g "$r" add -A
git -C "$r/.specs" init -q
g "$r/.specs" add -A
g "$r/.specs" commit -qm "Add the PRD"
