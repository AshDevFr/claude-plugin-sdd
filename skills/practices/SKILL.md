---
name: practices
description: The full spec-repo conventions: layout, the commit policy, where planning artifacts go, the fitness rubric deciding whether a change earns a spec and a task file, and the three worktree modes for giving an agent access to the spec tree. Use when setting up or reorganising a spec repo, when deciding whether a change needs the full pipeline, or when putting an agent in a worktree that needs the spec tree.
---

# Spec-Driven Practices

The session rules carry only what must apply everywhere. This is the detail behind them.

Read the section you need rather than the whole file.

This project has a nested spec repo (`.specs/.git` exists), so these apply. They are
emitted only for such projects; elsewhere they would be noise.

## Spec Repos (`.specs/`)

Most of my projects keep planning artifacts in a nested spec repo: a `.specs/`
directory at the repo root, gitignored globally (`~/.gitignore_global`) and
version-controlled separately at its own remote, conventionally `<main remote>-specs.git`,
branch `main`. Detect it by checking for `.specs/.git` at the repo root. If it
is absent, this project has no spec repo and none of the rules below apply.

**Layout.** `.specs/docs/` holds `PRD.md`, `specs/phase-N_<title>.md`,
`tasks/phase-N/N.NN-slug.md`, `plans/YYYY-MM-DD-<title>.md`, `designs/`,
`analysis/`, and `<project>-overview.md`. Superseded specs move to
`specs/archive/`. Screenshots and branding live at `.specs/screenshots/` and
`.specs/branding/`. Per-project overrides live in that project's `## Task
Workflow` section and always win over these defaults.

**Commit policy, scoped to `.specs/` only.** The spec repo is committed and
pushed in the same turn it is edited. This is the one place where committing
without being asked is not only allowed but required:

- Whenever you create or modify any file under `.specs/`, commit and push it in
  the same turn. Always operate on the nested repo with `-C .specs` so the main
  repo's index is never touched:
  ```sh
  git -C .specs add -A && git -C .specs commit -m "<description>" && git -C .specs push
  ```
  If `git -C .specs status` is clean there is nothing to do, skip it. If the
  repo has no `origin` remote, commit but do not push.
- Concise descriptive message (`Generate phase-4 task files`, `Archive the
  webhooks spec`). No Claude/Anthropic trailer or footer.
- **The main repo stays manual.** Never `git add`/`commit`/`push` there unless I
  explicitly ask. The exception above is for `.specs/` and nothing else.

### Giving a worktree access to the spec tree

A worktree never contains `.specs`: it is gitignored, so `git worktree add` does not carry it.
An agent dispatched into one cannot read a brief that lives there, and the failure is quiet
because the directory is simply absent. Three modes, created by
`@PLUGIN_ROOT@/scripts/sdd-worktree`:

| `--specs=` | What it does | Concurrency |
|---|---|---|
| **`none`** (default) | No spec tree in the worktree. The parent session owns every spec write and passes briefs inline. | Safe. Nothing is shared. |
| **`link`** | Symlinks the main repo's `.specs` into the worktree. One tree, one copy. | **Unsafe for two writers.** They race. **Needs `--add-dir`** (below) or the agent cannot read through the link at all. |
| **`worktree`** | A worktree of the spec repo on its own branch, so the spec tree is independent. | Safe for concurrent writers. Needs a merge back, which the script does not do for you. |

```sh
@PLUGIN_ROOT@/scripts/sdd-worktree <branch> [path] [--specs=none|link|worktree]
```

`none` is the default because it is the only mode with no concurrency hazard.

**For an agent that must read its brief from the spec tree, reach for `worktree`, not `link`.**
A session is confined to its working directory, and the permission check resolves a symlink
before testing it, so a `link` worktree's `.specs` is refused as being outside the session:

```
grep in '/…/plugin-marketplace/.specs/docs/…' was blocked. For security, Claude Code may only
search for patterns in files from the allowed working directories for this session:
'/…/plugin-marketplace-probe404'.
```

Measured in use, not inferred. The shell sees the file perfectly well; only the agent is
refused, which is why the filesystem checks in the harness pass while the mode fails. A
`worktree` mode spec tree is a real directory inside the worktree, so it is read with no extra
flags. `link` is still usable, but only if the session is launched with the target allowed:

```sh
claude --add-dir "$(git rev-parse --show-toplevel)/.specs"
```

So: `worktree` when an agent reads or writes specs; `link` only for a single writer where you
control the launch and can pass `--add-dir`; `none` the rest of the time.

At least the failure is loud. The agent is told it was refused rather than finding an absent
directory, so it reports the refusal instead of improvising a plausible brief, which is the
failure `--specs=none` with an inline brief exists to avoid.

The script refuses rather than improvising: no spec repo, a spec directory that is not a
repository, or a target path that already exists all stop it, and it will not leave a symlink
that does not resolve.

### Which lane a change takes

**The project-level decision is already made, by this file being here at all.** These rules are
emitted only where `.specs/.git` exists, so a project without a nested spec repo gets no
pipeline and needs no rubric: research notes, scratch pages and one-off scripts simply live
outside it. Creating a spec repo is the act of opting a project in.

What remains is the per-change decision *within* such a project. Not every change earns a phase
spec and a task file. The questions are asked in order, and the first one that decides, decides:

0. **Is existing behaviour broken, against a report that reproduces?** Then the **bug lane**:
   `/sdd:bug`. This question comes first because a bug answers the other three misleadingly. It is
   describable in one sentence, it fits one session, and "done" looks obvious, so the rubric sends
   it to the fast lane, where nothing records what was actually wrong. A fix whose diagnosis is
   unwritten is a fix nobody can review and nobody can tell from a coincidence.
1. **Can you describe the change in one sentence?** If not, it is full-pipeline work.
2. **Will it span more than one session?** If yes, full pipeline. The status header and the
   dated progress log exist precisely so a document survives the gap between sessions.
3. **Do you already know what "done" looks like?** If not, neither lane yet. Brainstorm
   first, then ask again. An unclear domain is the case spec-driven work is worst at.
4. Otherwise: **fast lane.** Use `/sdd:quick`.

**"Reproduces" is doing the work in question 0**, and it is the whole of what separates this lane
from the others. A report you cannot reproduce is not yet a bug: it is a question, and the lane
refuses it rather than guessing at a cause. New behaviour that does not work yet is not a bug
either, however much it feels like one; nothing is broken, it was never built.

What each lane guarantees:

| Lane | Artefacts | Guarantees |
|---|---|---|
| **Full pipeline** | PRD, phase spec, task files | A human can tell where the work stands weeks later without reading the diff. Status is enforced: a Complete task's verification command must have run. |
| **Bug lane** (`/sdd:bug`) | `bugs/YYYY-MM-DD-<slug>/` with `assessment.md`, `fix.md`, `test.md` | The diagnosis is written before the repair, and the verdict says whether the original reproduction was exercised or only the tests. |
| **Fast lane** (`/sdd:quick`) | one dated entry in the spec repo | The change and its verification command are recorded and committed. Nothing about sequencing, dependencies or progress. |
| **Neither** | none | Nothing is claimed. Appropriate for exploration whose output is understanding rather than a change. |

Hotfixes, spikes, one-file scripts, dependency bumps and config changes are fast-lane work.
Multi-phase product work is not. If you find yourself writing a twenty-phase plan for
something you would not staff for a month, the rubric is telling you something.

## What happens to a document when the requirement changes

Declare it in `## Task Workflow` as `**Spec Model**`. Three answers, and the project picks one:

| Model | A changed requirement means | Suits |
|---|---|---|
| `flow-back` | edit whichever document is wrong, reconcile the rest afterwards | one person, or a few who notice drift quickly; discovery during implementation is expected to reshape the plan |
| `flow-forward` | the Complete document stays as it is, and a new task or spec references it | auditability; a clear sequence of how the requirements moved |
| `living` | the spec is the contract, and the tasks under it are revised from it | a spec that is genuinely the source and not a summary |

**`flow-back` is the default, because it describes what projects here already do.** This repo's own
remediation plan has a "Deviations from the plan as written" section; that is flow-back with no
name on it. Naming it changes nothing about the behaviour and makes a question every command
answers silently into one the project answered deliberately.

The cost of each is worth knowing before picking. `flow-back` risks silent divergence: a decision
changed in a task file and never reflected upward leaves a future reader unsure which document to
trust. `flow-forward` risks duplication: related decisions spread across several documents, so it
needs a linking habit to stay followable. `living` needs a spec detailed enough to derive from,
which most are not.

`/sdd:converge` and `/sdd:analyze` read the model and word their proposals by it. Under
`flow-forward` they will not propose editing a Complete task's criteria, though they still propose
correcting a status or a File Plan path: those are facts about the document rather than the
decision it records.

**The directory must be called `.specs`.** Every hook in this suite tests for `.specs/.git`:
the commit guard, the verification gate, these rules, and the learnings capture. A project whose
spec repo has another name still resolves its paths correctly, because that is read from the
declared keys, but none of the enforcement fires and nothing says so at the time. Rename it to
`.specs` rather than relying on the commands alone.

**The nested spec repo is the convention, and the earlier shapes are not supported.** Two older
layouts exist in the tree and neither is a target: a container directory holding the code repo
and a spec directory as siblings, which was tried and abandoned, and spec documents committed
inside the code repo itself. Path resolution still reads whatever keys such a project declares,
so the commands work there, but these rules are not emitted and that is deliberate rather than an
oversight. Every project still using an earlier shape is superseded or abandoned.

**This rubric is guidance and nothing enforces it.** Unlike the commit policy and the
verification gate, no hook checks which lane you took. Over-applying the fast lane loses the
record; over-applying the full pipeline is the cost this rubric exists to avoid. The failure
is quiet in both directions.

**Keep the task file and the code in sync, in the right direction.** A behaviour change
updates the task file first, then gets implemented; a pure refactor goes code-first and the
task file is updated afterwards. Mixing the two directions is how a Status field ends up
describing work that was never done.

**A Complete status means the verification command ran.** Every task file carries a
`**Verification:**` field holding one runnable command. A `Stop` hook refuses to end a turn when a
task became Complete this session and that command did not run **as its own command**: not piped,
not behind `|| true`, not merely echoed or commented. Scope comes from the spec repo's own git
state rather than from which tool did the writing, so a `sed -i` flip and a subagent's edit count
the same as an `Edit` call, and subagent transcripts are read alongside the session's own.

Set the status back to In Progress rather than working around it. On a repeated Stop the gate
blocks again while the violation stands, up to three times, then says so and gets out of the way.

**What it still cannot tell you** is whether the command is a real check. It proves the command
ran and exited zero, not that it would have failed had the work not been done. `echo ok` passes
forever. Only review catches a Verification that has drifted away from its task.

**Never reference spec-repo identifiers from the main repo.** Phase numbers,
task IDs, spec filenames, and plan paths are dead pointers to anyone who only
has the main checkout. This covers source, comments, migration filenames,
commit messages, and PR descriptions. Write the actual constraint, invariant,
or bug instead.

**Cross-project changes.** When project A needs a change in project B, do not
edit B's product code. Write a plan into B's own spec repo at
`<path-to-B>/.specs/docs/plans/`, following B's conventions and its commit
policy, then let the change be made there.

### Planning artifacts always land in the spec repo

Any skill or plugin that writes a planning document writes it into `.specs/`,
never into the main repo. **This overrides the default path that skill
documents**, whatever it is: a design goes to `.specs/docs/designs/`, a plan to
`.specs/docs/plans/`, and anything reading plans reads them from there.

Never create a tool's own docs directory, or a top-level `docs/plans/`, in the
main repo. If one already exists, stop and tell me rather than adding to it.

A scratch ledger some other tool keeps outside `.specs/` is disposable, and
some are self-ignoring and hardcoded with no override. Leave those alone rather
than fighting them. The durable record of progress is the Status field in
`.specs/docs/tasks/phase-N/*.md`, which must be kept current; nothing else is.

**Use whatever process tooling you like; the artifacts are mine.** Another
plugin's brainstorming dialogue, TDD loop or debugging discipline may well be
better than working without one, and nothing here competes with them. What they
must not do is produce the durable document. Their formats are one-shot agent
briefings: checkboxes, no status field, no dates, and instructions addressed to
whoever executes them.

Any plan that will be worked across more than one session uses the templates
owned by the `sdd:plan-template`, `sdd:spec-template` and `sdd:task-template`
skills: status header, Tasks Summary table, per-task Progress Summary table,
dated Progress Tracking log. Those exist so the document tells a human where the
work stands weeks later without re-reading the diff. Never put agent
instructions inside my planning documents.

Concretely: explore however you like, then hand the result to `/sdd:plan` or
`/sdd:generate-specs` and let it produce the document that survives.

### Older projects, whose plans are not in `.specs` at all

The rule against naming planning identifiers in committed code is not really
about `.specs`. It is about the reader who has only the checkout. Any plan
location the main repo does not track has the same problem, and older projects
keep them in `tmp/`, `docs/plans/`, `plans/`, `.plans/`, `scratch/` or a
gitignored `notes/`.

**Treat every plan as local-only until you have verified it is checked in.** To
tell: look in `.gitignore` and the global excludes file, run `git ls-files` on
the path, or ask. If the path is ignored or untracked, nothing in it may be
named from source, comments, migration filenames, commit messages or PR
descriptions.

This lives here rather than in the always-loaded rules for a reason of cost, not
of space. There is no truncation cap: measured on 2026-09-16 by quote-back, a
marker at byte 12,060 of a 12,080-character emission came back verbatim, and so
did one at the end of a 6,581-byte plugin emission. The "roughly 2KB ceiling"
this paragraph used to cite was almost certainly the transcript UI's preview,
mistaken for the context, and it had been written into a test whose passing was
then read as confirming it.

What is real is the price. The ambient emission is paid for on every session in
every project that has a spec repo, and sdd's always-on cost was measured at
1,237 tokens. So the one-line rule is in the ambient text where it is needed on
every edit, and the detection method is here, where it costs nothing until asked
for. That split is still right; the ceiling was not the reason.
