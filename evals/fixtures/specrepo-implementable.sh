#!/usr/bin/env bash
# A task specific enough to implement without guessing, behind a verification that genuinely
# fails until it is done.
#
# Why this exists rather than reusing specrepo-withtasks.sh: that fixture's 1.02 says only
# "expose GET /widgets returning every widget as JSON", with no HTTP stack, no widget source and
# a widget-test.sh that echoes "widget tests pass" without testing anything. A correct run stops
# and asks, per /sdd:implement's own rule about ambiguous tasks, and a case that asks a command to
# finish an unfinishable task measures the fixture rather than the command.
set -euo pipefail
r="$1"
"$(dirname "$0")/specrepo.sh" "$r"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }

mkdir -p "$r/src" "$r/tests" "$r/.specs/docs/tasks/phase-1"
touch "$r/src/__init__.py" "$r/tests/__init__.py"

# The test exists and fails: src/widgets.py is not there yet. So ./run-tests is a verification
# that can actually distinguish done from not done.
cat > "$r/tests/test_widgets.py" <<'PY2'
import unittest

from src.widgets import list_widgets


class ListWidgets(unittest.TestCase):
    def test_returns_a_list(self):
        self.assertIsInstance(list_widgets(), list)

    def test_each_widget_has_an_id_and_a_name(self):
        for w in list_widgets():
            self.assertIn("id", w)
            self.assertIn("name", w)

    def test_ids_are_unique(self):
        ids = [w["id"] for w in list_widgets()]
        self.assertEqual(len(ids), len(set(ids)))


if __name__ == "__main__":
    unittest.main()
PY2

cat > "$r/run-tests" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec python3 -m unittest discover -s tests -t .
SH
chmod +x "$r/run-tests"

cat > "$r/.specs/docs/tasks/phase-1/1.02-list-widgets.md" <<'MD'
# Task 1.02: list_widgets()

**Status:** Not Started
**Phase:** 1
**Priority:** High
**Depends On:** None
**Verification:** `./run-tests`
**Created:** 2026-09-01
**Last Updated:** 2026-09-01

## Objective

Provide `list_widgets()` in `src/widgets.py`, returning the widgets this service knows about.
The tests are already written and currently fail, because the module does not exist.

## Scope

### In Scope

- `src/widgets.py` with a module-level `WIDGETS` list and a `list_widgets()` returning it.

### Out of Scope

- Any HTTP layer. This task is the data function only.
- Persistence. An in-memory list is the whole of it.

## File Plan

```
src/
└── widgets.py               (new)
```

## Implementation Notes

- Each widget is a dict with `id` (int) and `name` (str). Nothing else.
- Seed it with three widgets so the uniqueness test has something to check.
- `list_widgets()` returns the list; no filtering, no arguments.

## Acceptance Criteria

- [ ] `src/widgets.py` defines `list_widgets()`
- [ ] It returns a list of dicts, each with `id` and `name`
- [ ] Ids are unique
- [ ] `./run-tests` passes

## Testing Strategy

- **Unit:** `tests/test_widgets.py`, already written, covers all three criteria.

## Progress Notes

### 2026-09-01 - Task Created

- Drafted from the phase 1 spec. The tests were written first and fail until the module exists.
MD

g "$r/.specs" add -A
g "$r/.specs" commit -qm "Add task 1.02"
g "$r" add -A
g "$r" commit -qm "Add the failing widget tests"
