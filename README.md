# sdd

A spec-driven development workflow for Claude Code: plans, phase specs and task files in a
repository of their own, and **two hooks that refuse to let a session lie about what it did.**

The workflow part is not the interesting part. Plenty of things will write you a plan. What this
adds is enforcement:

- A turn cannot end while the spec repo has uncommitted work, so a status nobody committed cannot
  outlive the session that invented it.
- A task cannot be marked Complete unless its verification command actually ran, as its own
  command. Piped, behind `|| true`, or merely quoted back at you all read as *not run*.

Everything else exists to make those two affordable.

**It works installed on its own.** Its rules describe delegation in general terms and never name a
specific agent, so nothing dangles if you install nothing else.

---

## Install

From a terminal, before you start a session:

```sh
claude plugin marketplace add AshDevFr/claude-plugin-sdd
claude plugin install sdd@sdd
```

Then, inside a session:

```
/sdd:preflight
```

`claude plugin marketplace add` takes a URL, a path, or a GitHub `owner/repo`, so this one needs
no key and no SSH agent. `sdd@sdd` reads as *the plugin `sdd`, from the marketplace `sdd`*: this
repository is a one-plugin marketplace, and the two carry the same name. If you installed it from
a different marketplace, put that marketplace's name after the `@`.

There is no clone step and nothing to put on your `PATH` by hand: the scripts ship inside the
plugin. **Where they are reachable from is worth being exact about**, because it is not your
terminal. Claude Code puts an installed plugin's `bin/` on the `PATH` of the shell *it* runs
commands in, so `sdd-demo` and `sdd-worktree` are bare commands inside a session and unknown
outside one. Prefix them with `!` to run one from the Claude Code prompt. Everything else the
plugin ships is reached through the `/sdd:*` command that wraps it.

**`sdd` assumes nothing about your git transport.** A marketplace is a git URL, and a spec repo
inherits whatever the code repo's `origin` already uses, so HTTPS, SSH and a local path are all
fine. If you want to be sure before you start, ask git rather than assume:

```sh
git ls-remote <the marketplace URL> >/dev/null && echo ok
```

Then, once per project:

```
/sdd:bootstrap
```

which writes that project's `## Task Workflow` keys into its `CLAUDE.md` and the one permission
the commit policy needs. And `/sdd:spec-repo-init` if the project should have a spec repo at all.

---

## See it work

Ten minutes, on a real project, before you commit to anything. `sdd-demo` materialises a complete
example with no network access at all: its two histories ship inside the plugin as git bundles.

It ships in the plugin's `bin/`, so run it **from a Claude Code session**, where that directory is
on the `PATH`. At the prompt, `!` runs the rest of the line as a shell command:

```
! sdd-demo ~/tmp/beacon
```

```
sdd-demo: /home/you/tmp/beacon
  code   18 commits
  specs  8 commits, in a separate repository at .specs
```

You now have **Beacon**, a static incident status page rendered from one TOML file, with a PRD,
four phase specs, fifteen task files, four design records, a mockup set, and `./run-tests` as the
verification command every task names. It is deliberately unfinished: phase 1 complete, phase 2 at
4 of 6, one task blocked waiting on its owner, phase 3 blocked on a design decision that is written
down and still open, phase 4 marked as likely to be cut. A demo where everything is green would
teach you nothing about a workflow whose job is tracking what is not.

### 1. Look at the shape before running anything

```sh
cd ~/tmp/beacon
ls -a                       # .specs is here
git status --short          # ...and it is invisible to this repo. That is the design
git -C .specs log --oneline  # it has its own history, eight commits of planning
```

The planning history and the product history never touch. That is the single idea the rest is
built on, and it is why `.specs` has to be ignored by the outer repo.

### 2. Pick up the work

```
claude
/sdd:next-task
```

It reads the phase specs and the task files and proposes what to pick up. In this project that is
phase 2, where `2.01` to `2.04` are Complete, `2.05-phone-layout` is In progress and
`2.06-severity-palette` is Blocked waiting on the owner. `/sdd:implement-next-task` goes further and
implements it; `/sdd:implement <file>` works on one you name.

### 3. Now try to cheat, because that is the part you cannot see from a README

**Mark a task Complete without running its verification.** Edit
`.specs/docs/tasks/phase-2/2.05-phone-layout.md` and set its status to Complete, then end the turn.
The Stop hook refuses, verbatim:

```
A task was marked Complete without its verification running:

  2.05-phone-layout.md: Complete, but `./run-tests` did not run as its own command this session

Run the command on its own, with no pipe and no `|| true`: its exit status is the point. Or set
Status back to In Progress. A Complete status is supposed to mean the command passed, not that it
was mentioned.
```

It proves the command ran and passed. Whether the command still tests the task is for review; no
hook can answer that.

**Edit the spec repo and try to end the turn.** Add a line to `.specs/docs/quick-log.md`:

```
The .specs/ spec repo has uncommitted or unpushed work. Per the spec-repo commit policy, finish it
before ending the turn:

  git -C .specs add -A && git -C .specs commit -m "<concise description>"

Use a real description of what changed. No Claude/Anthropic trailer or footer.

Uncommitted:
 M docs/quick-log.md
```

Note `-C .specs`: the main repo's index is never touched. **The main repo stays manual** — this
suite never commits there unless you ask.

### 4. Throw it away

```sh
rm -rf ~/tmp/beacon
```

Nothing outside that directory was written. [`demo/README.md`](demo/README.md) explains how the
demo is packaged and how to change it.

---

## Which lane a change takes

**First: does this project have a spec repo at all?** Check for `.specs/.git`. If there is none,
there is no pipeline and no lane: just make the change. `/sdd:quick` will refuse, because it
records a dated entry *in* the spec repo and there is nowhere to put one. Opt in with
`/sdd:spec-repo-init`, which is a deliberate act rather than a default.

Within a project that has one, four questions in order. The first "no" decides it:

1. **Can you describe the change in one sentence?** If not, full pipeline.
2. **Will it span more than one session?** If yes, full pipeline.
3. **Do you already know what "done" looks like?** If not, neither lane yet: `/sdd:brainstorm`
   first, which classifies how much process the request earns, asks at most five questions one at
   a time, stops for your approval, and hands the approved design to `/sdd:plan` or
   `/sdd:generate-specs` rather than writing a document of its own.
4. Otherwise, **fast lane**: `/sdd:quick`, one dated entry and no task file.

Hotfixes, spikes, one-file scripts, dependency bumps and config changes are fast-lane work.
Multi-phase product work is not. Broken behaviour with a reproduction is neither: that is
`/sdd:bug`.

**Nothing enforces this**, unlike the commit policy and the verification gate. That is exactly why
it matters. Over-applying the fast lane loses the record; over-applying the full pipeline is the
cost the rubric exists to avoid, and it is the failure that makes people abandon a workflow inside
a week. If you are writing a twenty-phase plan for something you would not staff for a month, the
rubric is telling you something.

---

## What will stop you, and how to satisfy it

Two hooks can block a turn. Both are deliberate, and a block is not a bug.

| Block | Why | To satisfy |
|---|---|---|
| The spec repo has uncommitted or unpushed work | A status field nobody committed is a claim that outlives the session | `git -C .specs add -A && git -C .specs commit -m "..."`, then push if it has a remote |
| A task is Complete but its verification command has not run | Otherwise Complete means "I believe so", which is what drift is made of | Run the task's `**Verification:**` command **as its own command**, then mark it. A pipe, `\|\| true` or an `echo` of the command all read as not run, because each hands the exit status to something else |

The rest only speak up. Session start warns when `.specs` is not ignored by git. It does not stop
you.

**Two commands will not finish unattended, deliberately.** `/sdd:plan` and `/sdd:generate-tasks`
both stop and ask before writing. Under `claude -p` they produce a proposal and no files, which
looks like a failure and is the correct behaviour: the alternative is a command that invents a task
breakdown with nobody watching. Run those two interactively.

**The enforcement keys off a directory named exactly `.specs`.** A spec repo under another name
still resolves its paths, because those come from the `## Task Workflow` section `/sdd:bootstrap`
writes, but **no hook fires and nothing says so at the time.** If the commands work and nothing is
ever enforced, check that name first.

---

## What it expects of a machine

This is `/sdd:preflight --list`, quoted rather than restated. The script is where the list is
maintained, and a test fails if this block falls behind it.

<!-- preflight:list -->
```text
The machine contract

required: a gap in any of these exits 1

  ignore-specs       git ignores .specs in this repo, by any mechanism: the repo's own .gitignore, a global ignore file, or .git/info/exclude
                     if absent: Nothing errors. .specs shows as untracked and the nested spec-repo model quietly stops holding. Outside a repository this is only a recommendation, since each project may answer it locally

  cmd-git            git is installed
                     if absent: Nothing in this suite works

  cmd-bash           bash is installed
                     if absent: Every hook here is a bash script, so hooks stop running

  cmd-jq             jq is installed
                     if absent: The Stop hook no-ops, so the spec-repo commit policy stops being enforced and looks fine

  settings-valid     ~/.claude/settings.json parses
                     if absent: Every rule in it is inactive, silently


recommended: reported, never fatal

  ignore-claude-md   a new repository would ignore CLAUDE.md
                     if absent: A project CLAUDE.md becomes committable by accident. Some teams want it committed, which is why this is a preference

  ignore-claude-dir  a new repository would ignore .claude
                     if absent: Project-local settings become committable by accident. /sdd:bootstrap writes one that is meant to travel, so this cuts both ways

  cmd-curl           curl is installed
                     if absent: Telemetry stops reporting. Telemetry is optional in the plugin that sends it

  plugins-enabled    sdd is installed and enabled
                     if absent: The commands and skills are simply absent

  personal-layer     ~/.claude/CLAUDE.md exists
                     if absent: No personal instruction layer; only the plugin-delivered practice rules apply

```
<!-- /preflight:list -->

**Only the required tier can fail you.** `--fix` writes the one required entry it owns and nothing
else; `--fix-recommended` also writes the preferences. They are separate flags because two of those
preferences pull against `/sdd:bootstrap`, which writes a project `.claude/settings.json` that is
meant to be committed and travel with the repo. Your layout is your business.

**`.specs` is checked by asking git about the repository you are standing in**, not by
inspecting one file. `git check-ignore` consults the repo's own `.gitignore`, `core.excludesFile`,
`$XDG_CONFIG_HOME/git/ignore` and `.git/info/exclude`, so **any** of them is a complete answer. A
`.specs` line in the project's own `.gitignore` is the one that travels to everyone who clones,
which no global file does.

`--fix` follows that: inside a repository it appends to that repository's `.gitignore`; outside
one it writes where git already reads globally, else `~/.config/git/ignore`, which git reads with
no configuration at all. It never changes a git setting on your behalf.

Outside a repository there is no project to be broken, so a missing ignore is reported as a
**recommendation** rather than a gap: per-project entries are a real arrangement, and this command
cannot see them from there.

The preflight writes exactly one thing into `~/.claude/settings.json`, the telemetry endpoint, and
only when you pass `--otel-endpoint`. It will not invent a model choice, an effort level or a
permission entry: those are preferences rather than prerequisites, and a setup script that guesses
them leaves you debugging a config you did not write. Where something else already manages that
file, it refuses to touch it and says so rather than becoming a second writer.

---

## The permissions it needs

`/sdd:bootstrap` writes these into the project's `.claude/settings.json`, because **a plugin cannot
carry permissions**: a settings file inside a plugin with `permissions.allow` is ignored entirely.

| Grant | Needed by | Absent |
|---|---|---|
| `Bash(git:*)` | the spec-repo commit policy | **A deadlock.** The session writes spec work, the Stop hook blocks the turn until `.specs` is committed, and the permission layer refuses the commit. The one action required is the one denied |

That deadlock is the failure worth recognising on sight, because it does not look like a
configuration problem. Someone meeting it concludes the plugin is broken rather than unconfigured.

**Writing the grant is not enough on its own.** Until Claude Code has run interactively in that
directory once and the trust dialog has been accepted, the permissions are ignored rather than
applied, and the only signal is a warning that is easy to miss. Nothing is granted at user scope,
deliberately: that would change every project on the machine.

---

## The pieces, by purpose

**Getting set up:** `/sdd:preflight` for the machine, `/sdd:bootstrap` for a project,
`/sdd:spec-repo-init` to create a spec repo, `sdd-demo` for a throwaway example project.

**Deciding what to build:** `/sdd:brainstorm` is the front of the pipeline, for a request with no
design yet. It is the one lane that previously had no command behind it.

**Ending a session on purpose:** `/sdd:handoff` captures what dies when a session does, which is
not the task statuses or the commits (those are in `.specs/` and `git log`) but the decisions taken
in conversation, what was tried and abandoned, and what is in flight. If something *is* in flight
it asks whether to stop now or wait, because a subagent does not survive a restart and a background
command either dies or keeps running with nobody watching.

**Producing and maintaining the record:** `/sdd:plan` is interactive and produces the plan;
`/sdd:generate-specs` turns a PRD into per-phase specs and `/sdd:generate-tasks` turns a phase spec
into task files, stopping to confirm the breakdown before writing anything. `/sdd:quick` records a
fast-lane change as one dated entry. `/sdd:project-overview` describes a codebase you have not
seen. Behind them sit the `plan-template`, `spec-template` and `task-template` skills, which hold
the canonical documents, and `tidying-spec-repos` for a tree that has drifted.

**Doing the work:** `/sdd:next-task` finds what is next, `/sdd:implement-next-task` implements it,
`/sdd:implement` works on one named thing, `/sdd:commit-msg` and `/sdd:pr-msg` write the messages.

**Checking it holds together:** `/sdd:analyze` reads the spec tree and reports where it contradicts
itself, before anyone implements from it: phases with no spec, summary rows with no task file,
statuses that disagree, dependencies on work that does not exist, criteria nothing covers, and
verification commands that cannot fail. Read-only. `/sdd:converge` asks the other question, whether
the code matches the documents, and `--phase N --behaviour` adds a second pass that reads each
numbered criterion against the code and classifies any gap as `missing`, `partial`, `contradicts`
or `unrequested`, with file evidence. That pass is opt-in and needs `--phase`, because it dispatches
one read-only agent per task and a whole-project run is the version nobody runs twice.

**Repairing what is broken:** `/sdd:bug` is a third lane beside the pipeline and the fast lane, for
existing behaviour that is broken against a report that reproduces. Three stages: `assess` writes a
diagnosis and edits no source, `fix` is the only stage that touches source, and `test` runs the
reproduction and the verification as separate commands and returns `verified`, `partial` or
`failed`. A fix whose tests pass while the reproduction went unexercised is `partial`, and says
which command was not run.

**Deciding what a document left open:** `/sdd:clarify` works on a PRD, phase spec, plan or task
file. It asks at most five questions one at a time with a recommended answer, and after each one
writes the answer into a `## Clarifications` log, edits the section it affects, deletes what it
contradicts, and resolves the `[NEEDS CLARIFICATION]` marker. The generators write those markers
rather than guessing, and `/sdd:implement` refuses to start a section still carrying one, so
without this command they only accumulate.

**Showing it:** `/sdd:dashboard` starts a page on the LAN (`sdd-dashboard` serves it, detached) and
fills it with `sdd-report`: progress over every phase spec, plan, design and task file, plus the
latest commits. Those regions regenerate after every `git commit`; the status cards, decisions and
known issues around them are written by the agent following the `dashboard-upkeep` skill. It binds
every interface over plain HTTP behind a key by default, so treat what goes on the page as readable
by the network it is served on. `/sdd:snapshot` (`sdd-snapshot`) records where the practice stands,
before and after a change.

**Running something in isolation:** `sdd-worktree <branch> [path] [--specs=none|link|worktree]`.
Use `worktree` for an agent that must read its brief; `link` is the mode that sounds right and is
not, because the permission check resolves the symlink and refuses the target for being outside the
worktree.

**Doing it well:** `test-first` carries the failing-test-first loop in the detail the always-on
rules have no room for: the order, what each step proves, the expected failure at every stage, and
the two ways a green suite comes to mean nothing. `receiving-review` is what to do with review
feedback, including the case nothing else covers, feedback that is wrong: verify each finding
against the code first, and report one that does not hold rather than implementing it out of
politeness. `finishing-work` is the end: merge, propose or discard, what must be true before any of
them, and how to bring a `--specs=worktree` branch back.

**Behind the scenes:** `resolve-task-paths` finds a project's spec paths, `practices` holds the
conventions in full, `improver` proposes evidence-backed edits to the workflow itself, and
`project-overview` backs the command of the same name.

---

## Working on the plugin

```sh
test-hooks.sh          test-preflight.sh
test-worktree-modes.sh test-snapshot.sh
test-dashboard.sh      test-demo.sh
test-standalone.sh
check-prompt-hygiene.sh
check-prompt-contracts.sh
check-neutrality.sh
check-readme-coverage.sh
```

They live in `tools/` in a published copy of this plugin, and in `scripts/` in the marketplace it
is maintained in. Each resolves which layout it is in at runtime, so the same file works in both.

The `check-*` scripts are silent when they find nothing, so no output and exit 0 is the pass. They
build their fixtures from nothing, so claims about git behaviour stay true as git changes
underneath them.

`check-prompt-contracts.sh` is the free layer beneath the paid eval suite. Everything this plugin
does, it does by telling a model to do it, so a sentence trimmed out of a command is a behaviour
change that no diff reads as one. `scripts/prompt-contracts.json` pins the phrases whose absence
was a defect, each with the reason it is pinned.

`check-readme-coverage.sh` guards this file: every command, skill and script the plugin ships has
to be named here or in the marketplace README, or it fails.

`evals/` holds the graded suite, which needs the `claude` CLI and costs real money, so it is run by
hand. `python3 evals/grade.py --lint evals/cases/*.json` reports graders that cannot fail and costs
nothing.
