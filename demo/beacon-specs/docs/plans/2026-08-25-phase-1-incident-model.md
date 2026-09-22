# Phase 1: Incident model and renderer - Implementation Plan

**Status:** 🟢 Complete 2026-09-01
**Created:** 2026-08-25
**Last Updated:** 2026-09-01
**Spec:** `docs/specs/phase-1_incident-model-and-renderer.md`

## Executive Summary

### Purpose

Build the model, the ordering rules and a correct renderer, so that later phases have something
true to make presentable.

### Success Criteria

- [x] A malformed file names the incident and the field that is wrong.
- [x] Open incidents sort above resolved ones.
- [x] The page fetches nothing over the network.
- [x] `check` exits non-zero while an incident is open.

### Key Technical Decisions

- **TOML, not JSON or SQLite.** `docs/designs/2026-08-26-storage-format.md`.
- **One-way dependencies.** `model` knows nothing about HTML; `render` knows nothing about files.
  This is why the renderer tests need no temp directory.

## Tasks

### Task 1: Incident and Update model with validation

Parse one incident table into an object, raising an error that names the incident and the field.
`__slots__` on both classes so an attribute typo fails loudly.

### Task 2: Load and order incidents from TOML

`load()` reads the file, refuses duplicate ids, and sorts open before resolved, newest first.

### Task 3: Overall state from the open incidents

The headline is the worst severity still open, and `operational` when nothing is.

### Task 4: Render incidents to self-contained HTML

Inline CSS, escaped text, timeline newest first, durations in words.

### Task 5: The check and render commands

`argparse`, two verbs, exit codes that mean something to a pipeline.

## Closing note

Closed 2026-09-01 with 27 tests passing. The ordering rules took longer than the parsing and were
the right thing to spend the time on: the first version sorted purely by date and buried an open
outage under a week of resolved ones.
