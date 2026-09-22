---
argument-hint: [--with-agy]
description: Prepare the current project to work with this suite: Task Workflow keys and the grants it needs
disable-model-invocation: true
---

Prepare this project: `$ARGUMENTS`

This is the project contract. `/sdd:preflight` covers the machine; this covers one repository, and
it is needed once per project rather than once per machine.

## Step 1: check you are somewhere it applies

The script requires a git repository. If the working directory is not inside one, say so and stop
rather than running it: there is no project to prepare, and the error it returns is less useful
than the explanation.

## Step 2: show what it would change, before changing it

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/sdd-bootstrap" --help
```

Read the help and tell the user what the run will touch for *this* project: whether a `CLAUDE.md`
already exists, and whether `.claude/settings.json` already carries the grants. A user who knows
both will be present is being told nothing will change, which is the useful answer.

Pass `--with-agy` only when the user has the Antigravity CLI and wants the delegation adapter. It
adds an allow rule for `agy` and a deny rule for its escape flag; without the CLI both are inert
clutter in a config someone will later read and wonder about.

## Step 3: run it

```sh
"${CLAUDE_PLUGIN_ROOT}/scripts/sdd-bootstrap"
```

It adds what is missing and reports what it left alone. Run it twice and the second run changes
nothing, so re-running on a configured project is safe and is the way to check.

## Step 4: report the two things it cannot do

Both are in its output, and both are the difference between a configured project and a reader
wondering why the rules they can see are not applying:

- **The workspace still has to be trusted.** Until Claude Code has been run interactively here and
  the trust dialog accepted, the permissions it just wrote are ignored rather than applied.
- **Nothing was granted at user scope**, deliberately. Editing `~/.claude/settings.json` would
  change every project on the machine, which is not a side effect a per-project script should have.

If it created a `CLAUDE.md` and the global gitignore excludes `CLAUDE.md`, that file is untracked
and anyone cloning gets none of it. Say so, and offer `!CLAUDE.md` in the repository's own
`.gitignore`. Do not add it silently: it puts a new tracked file into someone's repository.
