# Phase 4: Embeddable widget - Spec

**Status:** ⚪ Not started, likely to be cut
**Created:** 2026-09-14
**Last Updated:** 2026-09-14
**PRD:** `docs/PRD.md`
**Estimated Completion:** unscheduled

## Quick Links

- PRD: `docs/PRD.md`
- Dependencies (other phases): phases 2 and 3
- Blocked By: not blocked, unjustified

## Tasks Summary

| Task | Status | Description |
| ---- | ------ | ----------- |
| 4.01 | 🔵 NOT STARTED | Render a one-line status fragment |
| 4.02 | 🔵 NOT STARTED | An embed snippet other teams paste into their docs |

## Phase Objective

Let another team show "API: operational" in their own documentation without linking away.

## Why this is written down as doubtful

The PRD says this phase is the most likely to be cut, and the spec should say so rather than
having the dashboard imply four phases of committed work. The honest summary:

- Nobody has asked for it. It came from one conversation about the docs site.
- It reintroduces the problem phase 2 spent its effort avoiding: an embed is a request from
  someone else's page to an asset of ours, which is a dependency in exactly the place we removed
  one. A pre-rendered fragment is still a fetch.
- **A link is probably enough.** That is the alternative, and it costs nothing.

## Success Criteria

- [ ] Someone other than its author asks for it.

That criterion is deliberate. Until it is met, this phase should not start, and the spec exists to
record why rather than to be worked from.

## Verification

None. Nothing to verify until the phase is justified.
