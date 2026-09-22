# Beacon

A static incident status page generator. One TOML file in, one self-contained HTML file out.
Python 3.11+, standard library only, no build step.

This repository is a teaching artifact for the `sdd` plugin suite; see the note at the top of
`README.md`. Its commit dates are synthetic. Nothing else about it is.

## Conventions

- **Standard library only.** A status page is read during an outage. Every dependency is another
  thing that can be unavailable when it is needed most, so there are none.
- **The rendered page makes no external requests.** No stylesheet, font, script or image is
  fetched. `test_page_makes_no_external_requests` enforces it; do not work around that test.
- **Errors name the incident and the field.** `incident 3: missing required field 'title'`, never
  `invalid input`. Someone reads these at 04:00.
- **Four severities.** `resolved`, `monitoring`, `partial`, `major`. Adding a fifth is a decision
  with a design record against it, not a small change.

## Task Workflow

- **Spec Repo**: `.specs/` (no remote: this copy is materialised locally by `sdd-demo`)
- **PRD**: `.specs/docs/PRD.md`
- **Phase Specs**: `.specs/docs/specs/phase-N_<title>.md`
- **Task Directory**: `.specs/docs/tasks/phase-N/`
- **Task File Pattern**: `N.NN-descriptive-name.md`

## Testing

`./run-tests` runs everything, and is the command named in every task file's **Verification:**
field. Keep it that way: a task marked Complete means that command ran and passed.
