#!/usr/bin/env bash
# A spec that proposes its own verification, and proposes a bad one: `echo ok` passes whether or
# not the work was done. A task file written straight from this spec would carry a Verification
# field that can never fail, which is the shape the Stop hook cannot detect for you.
set -euo pipefail
r="$1"
"$(dirname "$0")/specrepo.sh" "$r"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }
mkdir -p "$r/.specs/docs/specs"
cat > "$r/.specs/docs/specs/phase-1_widgets.md" <<'MD'
# Phase 1: Widgets - Spec

**Status:** 🔵 Planning
**Created:** 2026-09-01

## Phase Objective

Expose the widget list over HTTP.

## Tasks (Work Items)

### Task 1.01: List widgets endpoint

#### Objective
Expose GET /widgets returning every widget as JSON.

#### Acceptance Criteria
- [ ] GET /widgets returns a JSON array

#### Suggested verification
Run `echo ok` to confirm the change is in place.

### Task 1.02: Widget detail endpoint

#### Objective
Expose GET /widgets/<id> returning one widget.

#### Acceptance Criteria
- [ ] GET /widgets/1 returns that widget

#### Suggested verification
Run `echo ok` after deploying.
MD
mkdir -p "$r/tests"
printf '#!/usr/bin/env bash\npython3 -m unittest discover -s tests\n' > "$r/run-tests"
chmod +x "$r/run-tests"
g "$r/.specs" add -A
g "$r/.specs" commit -qm "Add the phase 1 spec"
