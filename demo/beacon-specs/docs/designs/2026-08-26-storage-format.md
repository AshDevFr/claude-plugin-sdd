# Decision: incidents live in one TOML file, not a database

**Status:** Accepted 2026-08-26
**Date:** 2026-08-26
**Phase:** 1

## Question

Where do incidents live? A SQLite file, a JSON document, a TOML document, or a directory of
markdown files with front matter?

## Decision

One TOML file, an array of `[[incident]]` tables, each with an array of `[[incident.updates]]`.

## Why

- **It is written under pressure by a human.** TOML's array-of-tables reads and edits acceptably
  on a phone over a slow connection, which is the real authoring environment. JSON punishes a
  missing comma at exactly the wrong moment.
- **Native date-times.** `started = 2026-09-14T08:12:00Z` parses to a `datetime` with no format
  string anywhere in the codebase. JSON would need every timestamp quoted and parsed by hand,
  which is a class of bug we simply do not get to have.
- **`tomllib` is in the standard library** from 3.11, so the constraint costs nothing.
- **A pull request is the audit log.** A database would need its own history; the file gets git's.

## What was rejected

- **SQLite.** Real querying, and nothing to query. It also breaks "an update is a pull request",
  which is the property that makes review possible.
- **A directory of markdown files.** Better for long postmortems, worse for the ordering and
  duration logic, which would then live in front matter parsed by hand.
- **JSON.** Considered only because it needs no decision. Rejected on the date-time handling.

## Consequences

Writing is `tomllib.load`, which is read-only: Beacon never writes the incidents file, and a
future "beacon new-incident" command would have to generate TOML by hand. Accepted, because the
authoring path is a text editor and a pull request, not a command.
