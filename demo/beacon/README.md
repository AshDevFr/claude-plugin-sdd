# Beacon

A static incident status page, rendered from one TOML file.

> **This repository is a teaching artifact.** It exists to show what a project looks like when it
> is run through the `sdd` plugin suite: a PRD, phase
> specs, designs, task files and a live dashboard, all in a nested spec repo beside the code.
> **The commit dates are synthetic**, written to make the history read as three weeks of work
> rather than one evening. Everything else is real: the code runs, the tests pass, and every number
> on the dashboard came from running something.

## Try it

No dependencies, no build. Python 3.11 or newer.

```sh
./beacon-cli check examples/incidents.toml     # validate; exits 1 while an incident is open
./beacon-cli render examples/incidents.toml -o status.html --title "Acme Status"
./run-tests                                    # 36 tests
```

Open `status.html`. It is self-contained: no stylesheet, font or script is fetched, because the
page is served from object storage during an outage, when whatever would have served them is
often the thing that is down.

## The incidents file

```toml
[[incident]]
id = "2026-09-14-checkout-latency"
title = "Elevated checkout latency in eu-west"
severity = "monitoring"          # resolved | monitoring | partial | major
started = 2026-09-14T08:12:00Z
components = ["Checkout", "Payments"]

  [[incident.updates]]
  at = 2026-09-14T08:41:00Z
  body = "Traced to a connection pool exhausted by a slow downstream."
```

Four severities, not five. Open incidents sort above resolved ones, and the newest update in an
incident is shown first, because a reader arriving mid-outage wants the thing that is broken now.
The reasoning behind each of those is a file in `.specs/docs/designs/`.

## What to look at if you are here for the workflow

The code is the smaller half. The interesting half is the spec repo, which is a **separate git
repository nested at `.specs/` and ignored by this one**, so planning artifacts never touch the
product's history:

| Where | What |
| --- | --- |
| `.specs/docs/PRD.md` | What Beacon is for and the four phases it is built in |
| `.specs/docs/specs/` | One spec per phase, each with a status the dashboard reads |
| `.specs/docs/designs/` | Decision records, including one still open |
| `.specs/docs/designs/mockups/` | A mockup set, two of whose pages ask the reader to choose |
| `.specs/docs/tasks/phase-N/` | Task files, each with a **Verification:** command that really runs |
| `.specs/docs/plans/` | Implementation plans, one in flight |
| `.specs/docs/quick-log.md` | The fast lane, for changes too small to earn a task file |

Then start the dashboard and read it the way the project owner would:

```sh
/sdd:dashboard
```

## Layout

```
beacon/          the package: model, render, cli
tests/           36 tests, stdlib unittest
examples/        the incidents file used by the tests and the demo
run-tests        the verification command named by every task file
```
