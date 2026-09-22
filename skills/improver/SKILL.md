---
name: improver
description: Propose one small, evidence-backed edit to a command, skill or rules file, drawn from the central learnings stream and this project's own log, and gated on the eval suite. Use when either has entries worth acting on, or when asked to improve the workflow itself rather than a project.
---

# Improver

You propose **one** change to **one** artefact, with its reasoning, as something a human
reviews. You never apply a change silently and you never propose a rewrite.

The problem this exists for: guidance gets re-derived by hand, repeatedly, and the reasoning
survives only in scrollback. A learnings log captures the reasoning; this turns it into a
reviewable edit.

## Step 1: read the evidence

There are two sources, and the second is usually the larger one.

```sh
cat "${XDG_STATE_HOME:-$HOME/.local/state}/sdd/learnings.jsonl"   # every project
cat <spec repo>/docs/learnings.md                                 # this project only
```

The **central stream** is one JSON object per line: `date`, `project`, `session`, `text`. It is
the only place a learning captured in another project can reach you, because you edit skills and
commands in the plugin marketplace and every other project's log lives in its own spec repo. That
asymmetry is why the marketplace log once held six entries, all from a single day, while the
workflow was in daily use elsewhere.

The **per-project log** is `<spec repo>/docs/learnings.md`; use the **`sdd:resolve-task-paths`**
skill to find the spec repo. It may not exist, and that is not an error.

If both are absent or empty, **say so and stop.** Do not invent an improvement: a proposal with
no evidence behind it is a guess wearing a citation.

Read all of it. Look for a pattern across entries rather than reacting to the newest one. A single
entry is an anecdote; three entries about the same artefact are a signal. `project` is worth
grouping by: the same complaint from three different projects is a much stronger signal than
three from one, which may only describe one codebase's shape.

## Step 2: pick one artefact, and say why that one

Rank candidates by how often the evidence implicates them, not by how easy they are to edit.
The most-invoked artefacts are where a small improvement compounds; a rarely used skill with
one complaint against it is not the place to start.

State the ranking. If the evidence does not clearly implicate one artefact, say that and
stop rather than picking arbitrarily.

## Step 3: propose the smallest edit that addresses the evidence

Smallest means: one rule, one paragraph, one example. Not a restructure.

A proposal that rewrites an artefact is unreviewable, and an unreviewable proposal is either
rejected or waved through unread. Both outcomes are worse than no proposal.

**Write principles with their reasoning attached, not rule lists.** A rule covers the case
someone enumerated; a principle with its reasoning generalises to the case nobody did. If you
cannot state why a rule exists, you do not yet understand the evidence well enough to propose
it.

Show the edit as a diff, or as before-and-after text. Name the artefact, the evidence entries
it comes from, and what you expect to change about the artefact's behaviour.

**Check each cited entry against the artefact as it reads now, before using it.** A learning
records what someone hit at the time; the artefact may have been fixed since, by a later session
or by a different edit entirely. For every entry you cite, open the artefact and confirm the
problem is still there in its current text. Discard the ones that are not, and say which you
discarded and why: an entry that has already been addressed is evidence about the past, and acting
on it re-fixes something or, worse, undoes the fix.

## Step 4: gate it on the eval suite

**This is the step that makes the loop a loop rather than a drift.**

**First, check you are somewhere the gate can work.** The suite lives in the plugin marketplace
checkout, and until 2026-09-16 it ran without `--plugin-dir`, so every run graded whatever was
installed under `~/.claude/plugins/` rather than the tree being edited. "Apply the edit, re-run
the case" ran the same copy twice, and the result was always "pass^3 unchanged", which this skill
read as admissible. Every improvement gated that way was gated on nothing.

So, before measuring anything:

```sh
cd "${SDD_MARKETPLACE:-.}" && test -x ./evals/run.sh || echo "no eval suite here: stop"
```

The suite lives in the plugin marketplace checkout and nowhere else: it needs the cases, the
fixtures and the `claude` CLI, and it tests this marketplace's own plugins. Set `SDD_MARKETPLACE`
to that checkout if you work from elsewhere. If the runner is still not there, **stop**. You
cannot measure an edit to a plugin artefact from a project that does not contain the plugin. Say
that rather than proposing an ungated edit.

Then:

```sh
FILTER=<case> ./evals/run.sh          # before, 3 runs, pass^3
# apply the proposed edit
FILTER=<case> ./evals/run.sh          # after
```

**Check that the two runs actually tested different code**, which is the failure this step
exists to catch:

```sh
jq -r '{stamp, head, trees: .plugin_trees}' evals/results/<before>/meta.json evals/results/<after>/meta.json
```

The `after` run must differ from the `before` run in something. If both name the same commit and
both report the plugin tree `clean`, the edit was not in the tree when the second run happened:
that is **an invalid measurement, not an unchanged score**, and reporting it as "unchanged" is
the exact mistake that made this gate ornamental. Re-run it properly or say it could not be
measured.

Report both. Then:

- **pass^3 drops**: reject your own proposal. Say so plainly and explain what it broke. A
  sensible-reading edit that lowers the score is still a regression.
- **pass^3 unchanged**: the proposal is admissible but unproven. Say that. An edit that
  changes nothing measurable may still be right, and the honest framing is that the suite
  cannot tell.
- **pass^3 rises**: the proposal is supported. This is the only case where the evidence is
  more than plausible.
- **No case covers the artefact**: say so, and propose the case first. An improver without a
  test is the random walk this gate exists to prevent.

Before proposing a new case, run `python3 evals/grade.py --lint evals/cases/*.json` on it. A
grader whose `must_match` already appears in the case's own prompt passes whatever the model does,
and is then counted as coverage forever. Nine graders were in that state when the lint was first
written.

**And beware the opposite failure, which is commoner in practice.** A pattern narrow enough to
avoid the prompt is easily narrow enough to miss a correct answer. Four graders were rewritten in
one afternoon for demanding a form of words: runs that wrote "never rewritten, only added to",
"passes even if nothing was built" and `WIDGETD` all failed patterns that wanted "append-only",
"cannot fail" and `widgetd/`. Check a replacement against real recorded output before trusting it,
and prefer matching the idea to matching the phrasing.

Revert the edit after measuring unless the reviewer has accepted it. Leaving an unaccepted
edit in the tree is applying it silently by another route.

## Step 5: hand it over

Report, briefly:

- The artefact, and why the evidence points there rather than elsewhere.
- The edit, small enough to read in full.
- The evidence entries, quoted.
- The before and after pass^3, and which of the four outcomes above applies.
- Your recommendation, and the case against it if there is one.

Then stop. The decision is the reviewer's.

## What not to do

- Do not propose more than one edit per run, however many the evidence supports. The second
  one is next time's proposal.
- Do not touch the templates' structure. The status header, summary tables and dated progress
  logs are the thing those documents are for.
- Do not edit a frontmatter `description` to improve wording. It decides whether a skill
  fires, so a reworded description is a behaviour change disguised as tidying.
- Do not propose anything whose justification is that it reads better.
