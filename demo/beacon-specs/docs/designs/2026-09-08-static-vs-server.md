# Decision: the page is rendered ahead of time and served from object storage

**Status:** Accepted 2026-09-08
**Date:** 2026-09-08
**Phase:** 2

## Question

Render on request from a small service, or render ahead of time to a file?

## Decision

Ahead of time. `beacon render` writes one self-contained HTML file, which is uploaded to object
storage on a different provider from everything else we run.

## Why

**The page is read exactly when our infrastructure is broken.** A status page served by the
cluster that is down is a page that says nothing at the only moment it was built for. Every
argument for a service, and there are real ones, has to survive that sentence, and none did.

Self-contained follows immediately: a page that fetches a stylesheet from our CDN has the same
problem one layer down. `test_page_makes_no_external_requests` enforces this, checking for
`src="http`, `href="http` and `@import`.

## What this costs

- No per-viewer anything. No timezone localisation, no "subscribe" button that talks to us, no
  live-updating clock. Phase 3 has to solve notifications without a server, which is genuinely
  harder, and this decision is why.
- The page is stale between renders. Accepted: the render is one command in the same pull request
  that edits the incident, so the staleness window is a CI run.
- Every byte is inline, so the page grows with the incident history. At 60 incidents it is about
  90 KB, which is fine; at 600 it would not be, and paginating is a known future task.

## What was rejected

A small Flask service on the same cluster, which is what the first sketch assumed. Rejected on the
first sentence above, once someone said it out loud.
