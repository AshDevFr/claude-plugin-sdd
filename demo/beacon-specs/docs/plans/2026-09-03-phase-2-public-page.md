# Phase 2: The public page - Implementation Plan

**Status:** 🟡 In progress, 4 of 6 tasks complete
**Created:** 2026-09-03
**Last Updated:** 2026-09-14
**Spec:** `docs/specs/phase-2_the-public-page.md`

## Executive Summary

### Purpose

Make the page readable by a worried person at four in the morning, on whatever device is to hand.

### Success Criteria

- [x] Four severities, distinguishable in both colour schemes.
- [x] No external requests, enforced by a test.
- [x] Durations in words.
- [x] Newest update first within an incident.
- [ ] No horizontal scrolling at 360 px.
- [ ] A palette legible with the common colour vision deficiencies.

### Key Technical Decisions

- **Four severities, not five.** `docs/designs/2026-09-02-severity-scale.md`.
- **Rendered ahead of time, served from object storage.**
  `docs/designs/2026-09-08-static-vs-server.md`.
- **No build step.** A build is a thing that can fail between an incident being written and the
  page going up.

## Tasks

### Task 1: Four-level severity scale

Replace the five-level sketch with `resolved`, `monitoring`, `partial`, `major`. `SEVERITY_RANK`
orders them for the headline. Errors list the allowed values when one is wrong.

### Task 2: Inline the stylesheet and prove the page fetches nothing

Move the CSS into the document and add `test_page_makes_no_external_requests`, checking for
`src="http`, `href="http` and `@import`.

### Task 3: Human-readable incident durations

`human_duration` renders minutes, hours with padded minutes, and days. A whole number of hours
drops the minutes: "3 h", not "3 h 00 min".

### Task 4: Timeline with newest update first

Updates are stored oldest first, because that is the order they are written in, and rendered
newest first, because that is the order they are read in.

### Task 5: Phone layout down to 360 px

In progress. Padding, the timeline's left rule, and stopping the badge from pushing the timestamp
off the edge when it wraps.

### Task 6: Severity palette

Blocked. Four candidates are on the mockup; the owner has not picked one. Writing a palette in the
meantime would mean doing it twice.

## Progress Notes

### 2026-09-14

Tasks 1 to 4 are done and verified by `./run-tests` (36 tests). Task 5 is underway. Task 6 is
blocked on the owner's pick and is not being worked around: the whole point of asking was to avoid
choosing a palette twice.
