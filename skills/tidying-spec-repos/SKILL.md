---
name: tidying-spec-repos
description: Use when a project's nested spec repo (the gitignored `.specs/docs` tree) has drifted: finished plans still sitting in plans/ or planned/, status headers that lag the code, a stale INDEX.md, or link rot after files were renamed. Also for "clean up the specs", "move implemented plans", "archive finished plans".
---

# Tidying Spec Repos

**Script paths below are relative to this skill's own directory**, which the
harness reports when the skill loads. `cd` there, or prefix them with it.

## Overview

A `.<project>/` spec repo accumulates plans faster than anyone retires them. The failure mode is
always the same: a plan ships, nobody moves the file, and six months later `plans/` is a mix of
live work and archaeology that no one trusts. Tidying restores one property — **location encodes
state**. If a doc is in `plans/`, work is outstanding. If it is in `implemented/`, it shipped.

**A document's own status header is a claim, not evidence.** Headers lag reality in both
directions. Verify before moving.

## Repo Shape

These repos are nested, gitignored by the parent, and have their own remote. Always operate with
`-C` so the parent repo's index is never touched:

```sh
git -C .specs status --short
git -C .specs mv docs/plans/foo.md docs/implemented/2026-07-14-foo.md
git -C .specs add -A && git -C .specs commit -m "..." && git -C .specs push
```

Canonical layout — six directories, each answering a different question:

| Directory | Holds | Why it is separate |
| --- | --- | --- |
| `plans/` | committed work not yet shipped: PRDs, plans, drafts | the queue |
| `specs/` | `phase-N_<title>.md` for multi-phase initiatives | the task-workflow commands resolve this path |
| `tasks/phase-N/` | `N.NN-<name>.md` task files | same |
| `implemented/` | shipped work, `YYYY-MM-DD-<slug>.md` | the archive of record |
| `ideas/` | concepts not committed to, and dropped proposals | keeps `plans/` trustworthy as a queue |
| `analysis/` | investigations and audits | no lifecycle — they never ship |
| `archives/` | pre-existing historical dumps | frozen; never rewritten |

**The taxonomy conflates two axes, and that is deliberate.** Location encodes *lifecycle*
(shipped or not). The `**Status:**` header encodes *maturity* (Draft, Planning, Complete,
DROPPED). Adding a directory per status is how these trees rot.

Consolidate anything that duplicates the lifecycle axis. A `planned/` next to a `plans/` is the
common one: both mean "not shipped", the split is arbitrary, and nobody can say which a new plan
belongs in. Fold it. Keep `ideas/` — "not committed to" is genuinely different from "queued", and
without it a dropped proposal sits in `plans/` looking like work.

Do not collapse `specs/` or `tasks/` into `plans/` even when empty. `/sdd:generate-specs`,
`/sdd:generate-tasks`, `/sdd:next-task`, and `/sdd:implement-next-task` resolve those paths out of the
project's `CLAUDE.md`; removing the directories breaks the commands for no gain. Leave a
`.gitkeep`.

## Workflow

### 1. Inventory

```sh
python3 scripts/spec-inventory.py .specs/docs
```

One row per doc with a verdict:

| Verdict | Meaning | Action |
| --- | --- | --- |
| `SHIPPED` | header and phase table both say complete | verify, then move |
| `SHIPPED-STALE-HEADER` | every phase complete, header still says Planning | verify, fix header, move |
| `MIXED-VERIFY` | header says complete, phases disagree | read it — usually a deferred optional tail |
| `ACTIVE` | outstanding work | leave |
| `FILED-STALE-HEADER` | already in `implemented/` but reads unfinished | fix the header or move it back |
| `FILED` | in `implemented/`, consistent | leave |

### 2. Verify against the code, not the doc

For each `SHIPPED` candidate, check one or two of its own success criteria against the repo — a
file that was supposed to be deleted, a crate that was supposed to exist, a released version. A
plan that says COMPLETE while its headline artifact is missing is not done.

When the code confirms a doc whose header lags, fix the header **and** record why in one line, so
the next reader is not re-litigating it:

```markdown
**Completion note:** shipped in v2.0.0. The per-task sections below were never re-stamped and
still read "Not Started"; the summary table is authoritative. Outstanding: `serial_test` is still
a dev-dependency.
```

### 3. Move with a date prefix

Every doc moved into `implemented/` gets the date it shipped as its filename prefix:
`YYYY-MM-DD-<slug>.md`. The date comes, in order of preference, from:

1. the doc's own `**Last Updated:**` once its status is complete,
2. the date of the last commit that touched it (`git -C <repo> log -1 --format=%ad --date=short -- <path>`).

Numbered files already carry an ordering handle, so they keep it instead of being renamed. Put a
multi-phase initiative in one dated directory and leave the phase names intact:

```
implemented/2026-08-15-config-figment-migration/
├── phase-1_config-env-advisory.md
└── phase-2_figment-config-migration.md
```

This is what stops `phase-1_...` from two unrelated initiatives colliding in a flat directory.

A design doc and the plan that implemented it both belong in `implemented/`, distinguished by a
`-design` suffix, each pointing at the other.

**Backfilling a tree that predates the convention**, or folding one directory into another:

```sh
python3 scripts/backfill-dates.py .specs/docs --fold planned:plans
# review the dry run, then
python3 scripts/backfill-dates.py .specs/docs --fold planned:plans --apply
```

It dates each doc from its own header, falls back to git, and rewrites every reference the
renames would break. Two things to read in the dry run before applying:

- **Dates it took from git.** A spec repo imported wholesale carries the import commit date on
  every old file. If a batch all share one date, they are wrong — recover the real ones from the
  *main* repo's history (`git log --grep` for the feature) and hardcode them.
- **Docs with no date at all.** Same treatment; the script refuses to guess.

### 4. Repair the links the move just broke

Moving a file breaks every reference to it. Before committing:

```sh
grep -rn "<old-basename>" --include='*.md' .specs/docs | grep -v '/archives/'
```

Fix each hit. While you are there, rewrite paths from any previous relocation of the tree itself
(e.g. `tmp/implementation/` → `.specs/docs/`) — those are dead pointers for every reader. Leave
`archives/` untouched; it is a historical record, and rewriting it is a lie about what was there.

### 5. Refresh the index

Regenerate the index from what is actually on disk rather than editing it by hand — a hand-edited
index is how it went stale in the first place. Keep the repo's existing section structure. Verify
the counts in the file match `ls | wc -l`.

### 6. Commit and push

One commit for the tidy, in the spec repo only:

```sh
git -C .specs add -A && git -C .specs commit -m "Retire shipped plans and refresh the index" && git -C .specs push
```

Never `git add` in the parent repo. The two repos do not mix.

## Common Mistakes

| Mistake | Why it bites |
| --- | --- |
| Adding a directory per status | `planned/` vs `plans/`, `done/` vs `implemented/`. Status is a header field. |
| Renaming by basename with sed | The same filename can live in two directories. Retarget by resolved path. |
| Trusting `**Status:** 🟢 Complete` | Headers are copy-pasted. Check the code. |
| Moving analysis docs to `implemented/` | An investigation never ships. It belongs in `analysis/`. |
| Renaming numbered specs to a date | Loses the phase ordering. Use a dated parent directory. |
| Moving files, then committing | The links are broken. Grep for the old basename first. |
| "Fixing" stale paths inside `archives/` | Archives record what was true then. |
| Running `git mv` from the parent repo | Stages the change in the wrong index. Use `-C`. |
| Deleting a plan that was abandoned | Move it to `ideas/` with a `⏸️ DROPPED` status and the reason. |

## Converging Task Status With the Code

`spec-inventory.py` reads a doc's own bookkeeping. It cannot tell you whether the work happened.
`task-converge.py` answers the harder question by diffing each task file's **File Plan** against
the repo:

```sh
python3 scripts/task-converge.py .specs/docs/tasks --phase 3
```

| Verdict | Meaning |
| --- | --- |
| `CONFIRMED` | marked done, every File Plan entry satisfied |
| `CLAIMED-UNBUILT` | marked done, entries genuinely absent |
| `STALE-FILE-PLAN` | marked done, every gap is a file that moved elsewhere |
| `DONE-UNCLAIMED` | not marked done, but everything is present |
| `NO-FILE-PLAN` | nothing checkable — cannot be reconciled by any tool |

It also reports **untracked work**: files *added* to the repo that no File Plan names.

Two things to hold onto when reading it. A missing path in a long-lived project usually means the
file was renamed, not that the work never happened — that is what `STALE-FILE-PLAN` separates out,
but only when the basename is unique. And the tool is read-only on purpose: flipping a status
because a file exists would replace a stale claim with a confident one. The `/sdd:converge` command
wraps this with the verification and the edits.

## Quick Reference

```sh
# inventory (doc bookkeeping only)
python3 scripts/spec-inventory.py .<project>/docs

# converge task status against the code
python3 scripts/task-converge.py .specs/docs/tasks
python3 scripts/task-converge.py --json /tmp/c.json --quiet
python3 -m unittest discover -s scripts -p 'test_*.py'

# shipped date for a doc
git -C .<project> log -1 --format=%ad --date=short -- docs/plans/foo.md

# move
git -C .<project> mv docs/plans/foo.md docs/implemented/2026-07-14-foo.md

# backfill dates / fold a directory (dry run, then --apply)
python3 scripts/backfill-dates.py .<project>/docs --fold planned:plans

# regenerate the index
python3 scripts/build-index.py .<project>/docs <Project>

# find the link rot
grep -rn "foo.md" --include='*.md' .<project>/docs | grep -v '/archives/'
```
