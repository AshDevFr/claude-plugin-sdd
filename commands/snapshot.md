---
description: Record the practice metrics that are cheap to measure, as a dated file
argument-hint: "[--print]"
disable-model-invocation: true
---

# Snapshot

Take a reading of the practice metrics that can be measured from disk, and write it
into the spec repo as a dated file.

The value is in the pair, never in a single reading. Run it before a change you
expect to move a number, and again after.

## Run it

The script ships inside this plugin:

```sh
${CLAUDE_PLUGIN_ROOT}/scripts/sdd-snapshot
```

Pass `--print` to write nothing and only show the report. Pass `$ARGUMENTS`
straight through.

## Then read it back to the user

Lead with what moved, not with the table. A snapshot nobody compares is a file.

- If an earlier snapshot exists in the same directory, diff the two and say which
  numbers changed and by how much. Name the change that plausibly caused each one.
- If this is the first, say so plainly and say which number you expect to move
  next, so the next run has something to confirm or refute.

## What it deliberately does not do

It reports three metrics as **not measured** rather than estimating them: the
prompt-cache hit rate, eval pass^3, and the wall-clock comparison between subagent
fan-out and a single session. Each needs an interactive session, a grading run, or
an experiment.

Do not fill those in from memory or from an older file. The whole point of the
section is that a snapshot which quietly drops its expensive half reads as
complete when it is not. If the user wants one of them, run the real thing:
`/usage` for the cache rate, `./evals/run.sh` for pass^3.

## Committing

The file lands in the spec repo, so the commit policy applies: commit and push it
in the same turn, with `-C .specs`.
