#!/usr/bin/env bash
# A task the path check cannot fault and the code does not satisfy.
#
# Every file in the File Plan exists, the status says Complete, and `task-converge.py` reports
# CONFIRMED, correctly: it answers whether the named paths are there, and they are. What it
# cannot see is that AC2 is unmet. `list_widgets` takes the `limit` argument and ignores it, so
# a request for two widgets returns all four.
#
# The gap is deliberately of the kind a path check can never reach, rather than merely one it
# happens to miss. No amount of looking at filenames tells you a parameter is accepted and
# discarded. That is the whole argument for a second pass, and this fixture is what makes the
# argument checkable rather than plausible.
#
# AC1 is genuinely met, so a run that reports both criteria as gaps is wrong in a way the graders
# can see. A fixture where everything is broken would pass a run that flags everything.
set -euo pipefail
r="$1"
"$(dirname "$0")/specrepo.sh" "$r"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }

mkdir -p "$r/app" "$r/tests"

cat > "$r/app/widgets.py" <<'PY'
"""Widget queries."""

_WIDGETS = [
    {"id": 1, "name": "bolt"},
    {"id": 2, "name": "nut"},
    {"id": 3, "name": "washer"},
    {"id": 4, "name": "screw"},
]


def list_widgets(limit=None):
    """Return the widgets.

    `limit` is accepted for API compatibility.
    """
    return list(_WIDGETS)
PY

: > "$r/tests/__init__.py"
cat > "$r/tests/test_widgets.py" <<'PY'
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from app.widgets import list_widgets


class Widgets(unittest.TestCase):
    def test_lists_every_widget(self):
        self.assertEqual(len(list_widgets()), 4)

    def test_accepts_a_limit(self):
        # Asserts the call does not raise. It does not assert the limit is applied, which is
        # how the gap survived a green suite.
        self.assertIsNotNone(list_widgets(limit=2))


if __name__ == "__main__":
    unittest.main()
PY

printf '__pycache__/\n*.pyc\n' > "$r/.gitignore"

cat > "$r/.specs/docs/specs/phase-1_widget-list.md" <<'MD'
# Phase 1: Widget list - Spec

**Status:** 🟢 Complete
**Created:** 2026-09-01

## Tasks Summary

| Task | Status      | Description           |
| ---- | ----------- | --------------------- |
| 1.01 | 🟢 COMPLETE | List widgets endpoint |

## Success Criteria

- [x] **SC-01:** Given four widgets in the store, when they are listed, then all four come back
- [ ] **SC-02:** Given a limit, when widgets are listed, then no more than that many come back
MD

cat > "$r/.specs/docs/tasks/phase-1/1.01-list-widgets.md" <<'MD'
# Task 1.01: List widgets

**Status:** 🟢 Complete
**Phase:** 1
**Depends On:** None
**Verification:** `python3 -m unittest discover -s tests -t .`
**Created:** 2026-09-01
**Last Updated:** 2026-09-02

## Objective

Expose the widget list, with an optional limit.

## File Plan

```
app/
└── widgets.py            (new)
tests/
└── test_widgets.py       (new)
```

## Acceptance Criteria

- [x] **AC1:** Given four widgets in the store, when `list_widgets()` is called, then it returns
      a list of length 4 (covers SC-01)
- [x] **AC2:** Given four widgets in the store, when `list_widgets(limit=2)` is called, then it
      returns a list of length 2 (covers SC-02)

## Testing Strategy

- **Unit:** `tests/test_widgets.py`

## Progress Notes

### 2026-09-02 - Task Complete

- Verification: `python3 -m unittest discover -s tests -t .` -> exit 0, 2 tests, OK
- Both criteria met
MD

g "$r" add -A
g "$r" commit -qm "Add the widget list"
g "$r/.specs" add -A
g "$r/.specs" commit -qm "Phase 1 complete"
