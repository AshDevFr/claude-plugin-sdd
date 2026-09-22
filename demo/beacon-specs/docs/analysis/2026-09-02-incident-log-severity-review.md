# Analysis: how the old incident log actually used severity

**Date:** 2026-09-02
**Feeds:** `docs/designs/2026-09-02-severity-scale.md`

## Method

Read every entry in the incident spreadsheet from 2025-03 to 2026-08 (61 entries). For each, two
of us independently wrote down which of the five sketch levels we would have chosen, without
seeing the other's answer or the level the author originally used.

## Findings

| Level | Entries | Independent agreement |
| --- | --- | --- |
| Operational | n/a | never written as an entry |
| Degraded | 14 | 6 of 14 |
| Partial outage | 19 | 8 of 19 |
| Major outage | 21 | 20 of 21 |
| Maintenance | 7 | 7 of 7 |

**Degraded and partial outage are one level.** Agreement inside each is barely better than chance,
and nearly every disagreement was between those two specifically. Major outage is unambiguous.
Maintenance is unambiguous and is not the same kind of thing as the others.

## What we did with it

- Collapsed degraded and partial into one level, named `partial`.
- Added `monitoring`, which is not a severity at all in the old scale but is the state 11 of the
  61 entries were actually describing in their last update.
- Left maintenance out entirely rather than keeping a level that means something different from
  its neighbours. If planned work earns a place, it is a different kind of entry.

## Caveat worth recording

Two readers is a small sample and we are both engineers. A support reader might have separated
degraded and partial consistently on a dimension we did not see. We accepted that risk because the
cost of being wrong is one more design record, and the cost of the extra level is paid by the
on-call engineer during every incident.
