# The demo project

**Beacon**, a static incident status page rendered from one TOML file by a small CLI. It is here
to be read and to be run, not to be depended on.

```sh
sdd-demo ~/tmp/beacon      # materialise it, no network needed
cd ~/tmp/beacon && claude
/sdd:next-task
```

## What is in this directory, and which copy is real

| | |
|---|---|
| `beacon/` | the code, as plain files. **For reading and diffing.** Browsable on a forge |
| `beacon-specs/` | the spec tree, as plain files, for the same reason |
| `beacon.bundle` | the code repository's real history, 19 commits |
| `beacon-specs.bundle` | the spec repository's real history, 8 commits |

**`sdd-demo` uses the bundles, not the directories.** Editing `beacon/` changes what a reader sees
on the forge and changes nothing about what the command produces. `scripts/test-demo.sh` compares
the two and fails when they disagree, which is the price of carrying both.

To change the demo: clone a bundle, commit there, and regenerate both the bundle and the
directory from that clone.

From this directory:

```sh
demo=$PWD
git clone "$demo/beacon.bundle" /tmp/beacon-work
# ...edit and commit in /tmp/beacon-work...
git -C /tmp/beacon-work bundle create "$demo/beacon.bundle" --all
rm -rf "$demo/beacon" && mkdir "$demo/beacon"
git -C /tmp/beacon-work archive HEAD | tar -x -C "$demo/beacon"
```

## Why two bundles rather than one repository

The thing this demo exists to show is that `.specs` is a **separate git repository**, nested inside
the code repository and ignored by it, so planning artifacts never enter the product's history. A
git repository cannot be committed inside another git repository, so the shape cannot travel as
files. It travels as two histories that `sdd-demo` reassembles.

The histories matter and are not decoration. `sdd-report` renders a "Latest commits" card, and the
spec repository's own eight commits are the clearest evidence for the rule that `.specs` is
committed in the same turn it is edited. Collapsing either to a single commit would leave the demo
unable to show two of the things it is for.

## What is honest about it, and what is not

Its commit **dates are synthetic**, written so the history reads as three weeks of work rather
than one evening. Everything else is real: the code runs, `./run-tests` passes 36 tests, and every
status in the spec tree describes the state the files are actually in.

The project is deliberately **unfinished**, and that is the point rather than an oversight:

- Phase 1 complete, phase 2 in progress at 4 of 6 tasks.
- One task blocked, waiting on a decision from the owner.
- Phase 3 not started, blocked on a design decision that is written down and still open.
- Phase 4 marked as likely to be cut.

A demo where everything is green teaches nothing about a workflow whose whole job is tracking what
is not.

## Three things it was fixed to be able to teach

Found while packaging it, each a real defect rather than a hypothetical:

1. **`CLAUDE.md` was never committed.** It existed on the author's disk and a global ignore file
   excluded it, so every clone got a project with no `## Task Workflow` section and a pipeline that
   resolved nothing. Its `.gitignore` now re-includes it explicitly.
2. **It named a private git host twice**, in a project meant to be cloned by people who cannot
   reach it. A remote nobody can fetch reads as a broken project rather than an irrelevant line.
3. **Its README claimed 35 tests in one place and 36 in another.** The suite runs 36.
4. **It committed `.superpowers/`**, one agent's working notes, re-included on purpose so the
   dashboard could draw a phase 2 progress bar from the ledger. Removed from the history, and
   named explicitly in `.gitignore` so the rule holds on a machine with no global ignore. **The
   dashboard's phase 2 plan therefore shows no progress bar here**, which is the cost and is
   worth it: agent scratch state does not belong in a repository other people read.
