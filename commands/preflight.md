---
argument-hint: [--fix]
description: Check what this machine must provide for the suite to work, and repair what is safe
disable-model-invocation: true
---

Check the machine contract: `$ARGUMENTS`

This is step 3 of getting a machine from nothing to working. Steps 1 and 2 are
`/plugin marketplace add` and `/plugin install`, which are already done if you can read this.

## Step 1: run the check

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/sdd-preflight"
```

Run it **without `--fix` first**, even when the user asked for a repair. The output is the
argument for the repair, and a user who has not seen the gaps cannot judge whether the fix is
one they want.

Pass `--with-agy` as well if the project or the user has mentioned Antigravity, and
`--otel-endpoint <url>` only when the user supplies a collector address. Never invent one: the
endpoint is site-specific and a wrong value fails silently.

## Step 2: read the result honestly

Exit 0 means nothing this script owns is outstanding. Exit 1 means something is. Exit 2 is a
usage error in the command you just ran, not a finding about the machine.

Three kinds of line, and they mean different things:

- `GAP` — a contract violation. Some are repairable here, some need a package manager.
- `REFUSED` — the script declined to write a file another tool manages. Report which tool and
  leave it alone.
- `info` — not a problem. A plugin not yet enabled or telemetry not configured is expected on a
  machine mid-setup, and reporting it as a failure trains the user to ignore the output.

Do not summarise a clean run as "all good" if there are `info` lines the user would want to act
on, and do not describe an `info` line as a failure.

## Step 3: repair, once the user has seen what will change

`--fix` repairs only what the script owns: the global gitignore entries, and a starter
`~/.claude/CLAUDE.md` when there is none. It never edits an existing personal file and never
touches a settings file another tool manages.

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/sdd-preflight" --fix
```

Then re-run without `--fix` and show the result. A repair that is not verified by a second read
is a claim, not evidence.

## What this does not cover

The machine contract, not the project contract. Once the machine is in order, each project still
needs `/sdd:bootstrap` for its `## Task Workflow` keys and its `.specs` git grants.

If `~/.claude/CLAUDE.md` already exists, the script reports how it differs from the starter and
stops there. Offer the user the `diff` command it prints; do not apply it. Sections the plugins
already deliver are the interesting part of that diff, because a copy in a personal file is
duplicated always-loaded context that will drift.
