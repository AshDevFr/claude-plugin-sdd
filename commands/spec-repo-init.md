---
argument-hint: [project-name]
description: Create the nested .specs/ spec repo for this project
disable-model-invocation: true
---

Set up the nested `.specs/` spec repo for the current project, following the
spec-repo convention from your practice rules.

## Arguments

The arguments arrive as one string in `$ARGUMENTS`. Read them from there:

- **the project name** — all of `$ARGUMENTS`, or empty

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1`
binds to the **second** token, and typed as a slash command it arrives as the literal text
`$1`. Neither is the first argument. `$ARGUMENTS` is correct on both paths.

**Project name**: from `$ARGUMENTS` (if empty, default to the basename of the main repo root)

## Step 0: Preflight

Run these and stop if anything is wrong:

- Confirm the working directory is inside a git repo, and resolve its root with
  `git rev-parse --show-toplevel`. All paths below are relative to that root.
- If `.specs/.git` already exists, **stop**. Report the existing remote
  (`git -C .specs remote -v`) and the current layout. Do not re-init.
- If a legacy spec directory exists (a `.<project-name>/` dir, or
  a tool's own docs directory, `tmp/implementation/`, `docs/plans/`), **stop and report
  it**. Offer to migrate it rather than creating a second parallel tree.

## Step 1: Confirm the plan with the user

Present, and wait for confirmation:

- The project name to use
- **The remote it will get**, resolved in this order and reported with which rule applied:

  ```sh
  git config --get sdd.specsRemote        # a template, {project} is substituted
  git remote get-url origin               # otherwise derive from the main repo
  ```

  1. If `sdd.specsRemote` is set, substitute `{project}` into it. A user or organisation sets
     this once, globally, and every project after that needs no decision.
  2. Otherwise derive it from the main repo's `origin` by stripping a trailing `.git` and
     appending `-specs.git`. The rule is textual, so it holds whatever the transport is:
     `https://example.com/team/app.git` gives `https://example.com/team/app-specs.git`, and
     `git@example.com:team/app.git` gives `git@example.com:team/app-specs.git`. The spec repo
     then lives beside the code it describes, which is almost always what is wanted. Do not
     convert between transports; whatever `origin` uses is what the user can already reach.
  3. Otherwise, if there is no `origin`, **ask**. Do not invent a host. Offer to set
     `sdd.specsRemote` at the same time so the question is asked once rather than per project.

- Whether that remote already exists on the server, or needs creating first (this command does
  not create remote repositories, the user does)
- Whether to seed a `PRD.md` stub or leave `docs/` empty

## Step 2: Create the layout

```sh
mkdir -p .specs/docs/{specs,tasks,plans,designs,analysis}
```

Do not create empty directories that will stay empty. `specs/` and `tasks/` are
always useful; add `designs/` and `analysis/` only if the user wants them now.

## Step 3: Initialise the repo

```sh
git -C .specs init -b main
git -C .specs remote add origin <the remote resolved in Step 1>
```

Write a short `.specs/README.md` naming the project this belongs to and linking
the main repo, so the spec repo is self-describing when cloned on its own.

## Step 4: Verify it is invisible to the main repo

Ask git rather than assume, and do not assume which mechanism answers:

```sh
git check-ignore -v .specs
```

Anything that makes this exit 0 is a complete answer: the repo's own `.gitignore`, a global
ignore file, or `.git/info/exclude`. **Prefer the repo's own `.gitignore`** when nothing already
covers it, because that rule travels to everyone who clones and a global one does not.

If it returns nothing, add `.specs/` to the repo's own `.gitignore` and tell the user why.

Also confirm `git status` in the main repo is unchanged by this command. If
`.specs` shows up as untracked, stop and fix the ignore before continuing.

## Step 5: First commit

```sh
git -C .specs add -A && git -C .specs commit -m "Initialise spec repo"
```

Push only if the remote exists. If `git -C .specs push -u origin main` fails
because the remote is missing, say so plainly and tell the user to create
`<project>-specs` on Gitea, then push. Do not silently skip the push.

## Step 6: Wire up the project CLAUDE.md

Append (or update) a `## Task Workflow` section in the project's `CLAUDE.md`,
using exactly these keys so `sdd:resolve-task-paths` can parse it:

```markdown
## Task Workflow

- **Spec Repo**: `.specs/` (remote `<the remote resolved in Step 1>`)
- **PRD**: `.specs/docs/PRD.md`
- **Phase Specs**: `.specs/docs/specs/phase-N_<title>.md`
- **Task Directory**: `.specs/docs/tasks/phase-N/`
- **Task File Pattern**: `N.NN-descriptive-name.md`
- **Spec Model**: `flow-back`
```

**Write the Spec Model key even though `flow-back` is also the default.** It says what happens to
a document when the requirement behind it changes: `flow-back` lets any document be edited and
reconciled afterwards, `flow-forward` treats a Complete document as a record and answers a changed
requirement with a new one, `living` makes the spec the contract and derives tasks from it.
Declaring it costs a line and makes a question every command already answers silently into one the
project answered on purpose. Say in your report which one was written and that it can be changed.

Do **not** restate the commit policy, the no-plan-IDs rule, or the layout. Those
come from your practice rules and apply automatically. This section carries only
the parameters that differ per project.

If the project uses a different unit than `phase-N` (for example `feature-N`),
substitute it consistently across all three path keys.

## Step 7: Report

Tell the user:

- The spec repo path and its remote
- Whether the initial push succeeded, or what they need to do on Gitea first
- The `## Task Workflow` block that was added to `CLAUDE.md`
- Suggest `/sdd:plan` or `/sdd:generate-specs` as the next step
