---
argument-hint: [what changed]
description: Record a fast-lane change in the spec repo, with no phase spec or task file
---

Record a small change that does not earn a phase spec or a task file: `$ARGUMENTS`

This is the off-ramp. Use it when the fitness rubric says fast lane: the change is
describable in one sentence, fits one session, and you already know what done looks like.

## Step 1: check the lane is right

If the change cannot be described in one sentence, or will span sessions, stop and say so.
The right answer then is `/sdd:plan` or `/sdd:generate-specs`, not a quick entry that will
be wrong by tomorrow.

## Step 2: resolve where the log lives

Use the **`sdd:resolve-task-paths`** skill to confirm this project has a spec repo. If it
has none, say so and stop: there is nowhere durable to record this, and writing into the
main repo is forbidden.

The log is `<spec repo>/docs/quick-log.md`. Create it if absent, with the heading
`# Quick log` and one line saying entries are newest first.

## Step 3: establish the verification command

Ask for one runnable command that shows the change works, unless `$ARGUMENTS` already names
one. The same standard as a task file's Verification field: a command someone can paste.

`cargo test -p parser`, `make lint`, `./scripts/smoke.sh`. Not "ran it locally", not "looks
fine". If there genuinely is no way to check it, say that in the entry rather than inventing
a command.

## Step 4: run the verification

Run it. Report what it printed. If it fails, fix the change or record the entry as not
working, but do not write an entry claiming a passing check that did not pass.

## Step 5: append one entry

Newest first, directly under the heading:

```md
## YYYY-MM-DD — <one-line summary>

**Why:** the constraint, bug or request that prompted it, in a sentence or two.
**Verification:** `<command>` — <what it printed>
**Touched:** `path/one`, `path/two`
```

Nothing else. No status field, no progress table, no checklist. If an entry starts wanting
those, the change was full-pipeline work and the rubric was applied wrongly.

## Step 6: commit the spec repo

Per the spec-repo commit policy, in the same turn:

```sh
git -C .specs add -A && git -C .specs commit -m "Quick: <summary>" && git -C .specs push
```

Leave the main repo alone. Its commit is the user's to make.

## Step 7: report

The entry you wrote, the verification output, and the spec-repo commit. One short paragraph.
