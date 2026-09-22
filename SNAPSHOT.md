# This is a snapshot

This repository is **generated**, not developed. It is a copy of the `sdd` plugin from the
marketplace it is maintained in, published so that it can be installed without reaching a private
host.

| | |
|---|---|
| Plugin version | `0.41.0` |
| Source commit | `92cc8c02814f4b24d930f160a97d27366a3ceaef` |
| Taken on | 2026-09-22 |

**Do not send changes here.** They would be overwritten by the next snapshot, silently, because
the snapshot replaces this tree wholesale rather than merging into it. Raise them against the
source repository instead.

**It will go stale between snapshots and nothing detects that.** The commit above is the only way
to tell how old this copy is. That was a deliberate choice over developing here directly and over
a release-time mirror: development stays in one tree, and republishing is one command.

## Re-taking it

From a clean checkout of the source repository:

```sh
scripts/snapshot-sdd.sh <path-to-this-checkout>
git -C <path-to-this-checkout> add -A
git -C <path-to-this-checkout> commit -m "snapshot: sdd 0.41.0"
```

It refuses a dirty source tree, because a recorded commit that does not contain what was published
is worse than none.

## Checking this copy

```sh
tools/test-hooks.sh          tools/test-preflight.sh
tools/test-worktree-modes.sh tools/test-snapshot.sh
tools/test-dashboard.sh      tools/test-demo.sh
tools/check-prompt-hygiene.sh
tools/check-prompt-contracts.sh
tools/check-neutrality.sh
tools/check-readme-coverage.sh
```

The `check-*` scripts are silent when they find nothing. They build their fixtures from nothing,
so they test this copy rather than the machine it was built on.
