# Decision: how subscribers get notified without a server

**Status:** ⚪ Proposed, waiting on the owner
**Date:** 2026-09-14
**Phase:** 3

## Question

Phase 3 promises that a customer can subscribe to updates without an account. The static-render
decision means we have nowhere to run a subscription list. So where does it run?

This is the open question in the PRD, written up so it can be answered rather than rediscovered.

## Options

### A. A managed email list, addressed by the render step

`beacon render` also emits a plain-text digest, and a CI step posts it to a hosted list provider.
Subscribers are that provider's problem, including unsubscribe, bounce handling and GDPR deletion.

- **For:** no state of ours, no server, and the compliance surface belongs to someone whose job it
  is. Shippable in phase 3 as scoped.
- **Against:** a third party in the incident path, with its own status page. Costs money per
  subscriber. We would be trusting a vendor's availability during exactly the events we are
  reporting on.

### B. RSS and Atom beside the page

The render step writes `feed.xml` next to `status.html`. No subscribers, no list, no personal data
at all.

- **For:** free, static, no vendor, no compliance surface, and it is the same self-contained
  artefact by the same command. Roughly a day of work.
- **Against:** most customers do not use a feed reader. It answers the letter of "subscribe
  without an account" and probably not its intent.

### C. Webhooks, subscriber-hosted

A customer registers a URL by pull request to the incidents repository; the render step POSTs to
each on change.

- **For:** no state of ours, and it is what our integration-minded customers would actually want.
- **Against:** "by pull request" means it serves five customers, not five thousand. Retries and
  failures need somewhere to live, which is the server we do not have.

## What I would do

**B now, A later if the evidence arrives.** B costs a day, adds nothing to the incident path, and
makes the phase-3 promise partly true immediately. Then count feed subscribers for a quarter: if
the number is as small as I expect, that is the evidence for paying a vendor in A, and if it is
not, we have saved the money and the dependency.

**This is the owner's call, not mine**, because A costs money per subscriber and puts a vendor in
the incident path. Both are decisions with a budget and a risk attached rather than a technical
preference, which is why this is sitting in *Waiting on you* rather than being decided here.
