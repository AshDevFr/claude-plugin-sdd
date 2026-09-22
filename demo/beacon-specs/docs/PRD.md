# Beacon - Product Requirements

**Status:** 🟡 In progress, phase 2 of 4
**Created:** 2026-08-24
**Last Updated:** 2026-09-14

## The problem

When something breaks, the people who need to know are the ones least able to ask. Support gets
the same question forty times, engineers get interrupted mid-incident to write an update, and the
status page, if there is one, is a page in the same cluster that is currently down.

We have no status page. We have a Slack channel, a spreadsheet of past incidents that nobody
updates, and a habit of telling customers individually.

## What Beacon is

A command that turns one file of incidents into one self-contained HTML page, which is uploaded to
object storage. No server, no database, no dashboard to log into. The incidents file lives in a
git repository, so writing an update is a pull request, and the page's history is the file's
history.

## Who it is for

- **The engineer on call**, who must be able to publish an update in under two minutes, from a
  phone, at four in the morning, without learning anything.
- **The customer**, who wants one sentence: is it broken, is it being worked on, when did it start.
- **Support**, who need a link to send instead of typing the same sentence forty times.

## What it is not

- Not a monitoring system. Beacon does not detect anything; a human writes the incident.
- Not a subscription service in phase 1 or 2. Notifications come later, if at all.
- Not multi-tenant. One organisation, one page.

## Success criteria

- [x] An incident can be published by editing one file and running one command.
- [x] The rendered page fetches nothing over the network.
- [ ] The page is legible on a phone at 360 px without horizontal scrolling.
- [ ] A customer can subscribe to updates without an account.
- [ ] Time from "we have an incident" to "the page is live" is under two minutes, measured.

## Phases

| Phase | Name | State |
| --- | --- | --- |
| 1 | Incident model and renderer | Complete |
| 2 | The public page | In progress |
| 3 | Subscriptions and notifications | Not started |
| 4 | Embeddable widget | Not started |

**Phase 1** gets the data model and a page that renders correctly. **Phase 2** makes that page
something you would put in front of a customer: severity that reads at a glance, a timeline that
survives a long incident, and a phone layout. **Phase 3** is the first phase that needs anything
stateful, and is deliberately last but one for that reason. **Phase 4** is a script other teams
embed in their own docs, and is the phase most likely to be cut.

## Constraints

- **Python 3.11+, standard library only.** Every dependency is another thing that can be
  unavailable when it is needed most.
- **The page is static.** It is served from object storage precisely because our own
  infrastructure is the thing likely to be down. This constraint is the reason phase 3 is hard,
  and is not up for negotiation to make phase 3 easier.
- **One file is the source of truth.** Not a database, not an API. Reviewable, revertable,
  diffable.

## Open questions

- How do subscribers get notified without us running a server? The subject of an open design
  record; the owner has not yet chosen a transport.
- Does the embeddable widget earn its phase, or is a link enough?
