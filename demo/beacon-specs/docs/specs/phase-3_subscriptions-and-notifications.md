# Phase 3: Subscriptions and notifications - Spec

**Status:** ⚪ Not started, blocked on an open design decision
**Created:** 2026-09-14
**Last Updated:** 2026-09-14
**PRD:** `docs/PRD.md`
**Estimated Completion:** unscheduled

## Quick Links

- PRD: `docs/PRD.md`
- Design: `docs/designs/2026-09-14-notification-transport.md` (Proposed, not accepted)
- Blocked By: that design record

## Tasks Summary

| Task | Status | Description |
| ---- | ------ | ----------- |
| 3.01 | 🔵 NOT STARTED | Emit an Atom feed beside the page |
| 3.02 | 🔵 NOT STARTED | Stable entry ids so a reader is not re-notified |
| 3.03 | 🔵 NOT STARTED | Link the feed from the page and document subscribing |
| 3.04 | 🔵 NOT STARTED | Measure subscriber count for a quarter |

## Phase Objective

Make the PRD's "a customer can subscribe to updates without an account" true, without acquiring a
server, because the static-render decision means we do not have one and do not want one.

## Success Criteria

- [ ] A reader can subscribe without giving us anything, including an email address.
- [ ] A corrected update does not re-notify everyone who already read it.
- [ ] The notification path adds nothing that can be down during an incident.
- [ ] After a quarter, we know how many people actually subscribed.

## Context & Background

### Current State

Nothing exists. The phase is written up so the shape of the decision is visible, not because work
is about to start.

### Motivation

It is the one PRD success criterion with no path to being met, and pretending otherwise on the
dashboard would be the exact dishonesty this project is trying to avoid.

### The blocking decision

`docs/designs/2026-09-14-notification-transport.md` lays out three options. The recommendation is
the feed, with a hosted list later if the numbers justify it. **The owner has not answered**, and
the tasks below assume the recommendation. If the owner picks the hosted list instead, 3.01 to
3.03 are replaced rather than amended.

## Technical Approach

Atom rather than RSS, for required stable ids and unambiguous dates. The feed is written by the
same `beacon render` invocation, next to `status.html`, so there is no second command anyone can
forget during an incident.

### Entry identity

The hard part. An entry id is `<incident id>:<update timestamp>`, so editing the wording of an
existing update does not create a new entry. Correcting a *time* does, and that is accepted: the
alternative is a content hash, which makes every typo fix a new notification.

## Out of Scope

- Email of any kind, unless the owner chooses option A.
- Per-subscriber anything. There are no subscribers we know about, by design.

## Risks

| Risk | Mitigation |
| --- | --- |
| Nobody uses feeds and the phase is theatre | 3.04 exists to find that out; the phase is cheap enough to be worth the measurement |
| The owner picks the hosted list after these tasks are written | Tasks are replaced, not amended; they are cheap and this is written down |

## Verification

`./run-tests` once 3.01 exists. Nothing to verify while the phase is unstarted.
