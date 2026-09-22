#!/usr/bin/env bash
# A spec repo mid-phase: one task Complete, one not. The shape next-task and
# implement-next-task have to read correctly.
set -euo pipefail
r="$1"
"$(dirname "$0")/specrepo.sh" "$r"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }
cat > "$r/.specs/docs/tasks/phase-1/1.01-health-check.md" <<'MD'
# Task 1.01: Health check endpoint

**Status:** Complete
**Phase:** 1
**Verification:** `./scripts/widget-test.sh`
**Created:** 2026-09-01

## Objective
Expose /healthz.
MD
cat > "$r/.specs/docs/tasks/phase-1/1.02-list-widgets.md" <<'MD'
# Task 1.02: List widgets endpoint

**Status:** Not Started
**Phase:** 1
**Verification:** `./scripts/widget-test.sh`
**Created:** 2026-09-01

## Objective
Expose a read-only GET /widgets returning every widget as JSON.

## Acceptance Criteria
- [ ] GET /widgets returns 200 and a JSON array
MD
# The Complete task's verification command must exist, and the work it claims must be
# visible. An incoherent fixture makes the command under test argue with the fixture
# instead of answering the question.
mkdir -p "$r/scripts"
printf '#!/usr/bin/env bash\necho "widget tests pass"\n' > "$r/scripts/widget-test.sh"
chmod +x "$r/scripts/widget-test.sh"
cat > "$r/src/main.py" <<'PY2'
def healthz():
    return {"status": "ok"}
PY2
g "$r" add -A
g "$r" commit -qm "Add healthz and its test script"
g "$r/.specs" add -A
g "$r/.specs" commit -qm "Add phase 1 tasks"
