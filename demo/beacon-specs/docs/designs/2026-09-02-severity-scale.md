# Decision: four severities, not five

**Status:** Accepted 2026-09-02
**Date:** 2026-09-02
**Phase:** 2

## Question

The scale every status page starts with is five levels: operational, degraded, partial outage,
major outage, maintenance. Do we use it?

## Decision

Four: `resolved`, `monitoring`, `partial`, `major`. "Operational" is the absence of an open
incident rather than a severity anyone writes, and "degraded" is gone.

## Why

We read eighteen months of the incident spreadsheet and asked, for each entry, which level the
author would have chosen. **"Degraded" and "partial outage" were used interchangeably**, by the
same people, for incidents of the same shape. A distinction nobody applies consistently is not
information, and it costs a decision at the worst possible moment: the on-call engineer writing
the first update, who should be spending that attention on the incident.

`monitoring` replaces it, and answers a question customers actually ask: is someone still on this?

Maintenance is not a severity. Planned work is a different kind of entry, and phase 3 or later can
add it as one if it earns the place.

## Consequences

`SEVERITY_RANK` is a four-entry ordering used for the headline, so adding a fifth level later
means revisiting the headline rule as well as the palette. That is the intended friction. Anyone
proposing a fifth should be asked for the same evidence: entries from the log that two people
would classify differently without it.
