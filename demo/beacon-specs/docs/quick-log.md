# Quick log

The fast lane. Changes describable in one sentence, fitting one session, where done is obvious.
No phase spec, no task file, one dated entry each.

## 2026-09-04 — `check` exits 1 while an incident is open

**Why:** the deploy pipeline had no way to refuse to ship into an outage, and was reading the
command's stdout with `grep`. An exit code is the interface a pipeline already understands. Exit 2
stays reserved for a malformed or missing file, so "we are in an incident" and "your file is
broken" are distinguishable.
**Verification:** `./run-tests` — 30 tests passing, including
`test_exits_non_zero_while_an_incident_is_open`.
**Touched:** `beacon/cli.py`, `tests/test_cli.py`

## 2026-09-09 — Duplicate incident ids are refused at load

**Why:** two incidents copied from each other kept the same id, and the anchors on the page
silently collided, so a link to the second scrolled to the first. Found while writing the webhook
backlog entry by copying the API outage one, which is presumably how it will happen to everyone.
**Verification:** `./run-tests` — 33 tests passing.
**Touched:** `beacon/model.py`, `tests/test_model.py`

## 2026-09-13 — `run-tests` discovers instead of listing three files

**Why:** `run-tests` named its test files by hand, and a fourth was written and then not run for
two days because nobody remembered to add the line. Discovery cannot forget. `tests/__init__.py`
comes with it, which is what `unittest discover -t .` needs to import the package.
**Verification:** `./run-tests` — 36 tests passing, one more file than the old script listed.
**Touched:** `run-tests`, `tests/__init__.py`
