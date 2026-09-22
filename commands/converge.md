---
description: Diff the spec repo's task files against the code and reconcile the drift
argument-hint: "[tasks-dir] [--phase N] [--since REF|DATE] [--behaviour]"
---

# Converge

Reconcile a project's task files with what the code actually says. A task's
`**Status:**` is a claim; this command turns it into a measurement, then fixes
the bookkeeping with your confirmation.

Run this at the end of a phase, before writing the next phase's spec, or any
time the task tree has been running ahead of the specs for a while.

## 1. Resolve paths

Invoke the `sdd:resolve-task-paths` skill to get the tasks directory, the phase
specs directory, and whether the paths live in a nested spec repo. Arguments to
this command always win over CLAUDE.md.

If `$ARGUMENTS` contains a directory, use it as the tasks directory. Pass
`--phase N` and `--since` straight through to the script.

## 2. Gather evidence (mechanical, no judgement)

The `sdd:tidying-spec-repos` skill owns `task-converge.py`. Invoke that skill to
learn its base directory, then run the script from there:

```sh
out=$(mktemp -t converge.XXXXXX.json)
python3 <skill-dir>/scripts/task-converge.py \
  <tasks-dir> --json "$out" --quiet
```

`mktemp` rather than a fixed `/tmp/converge.json`: two sessions converging at once would
otherwise overwrite each other's evidence, and a run that died before writing would leave the
previous run's file to be read as if it were this one's. Remove it when you are done with it.

This step needs `python3`.

The script is read-only by design. It never edits a task file, because
automatically flipping a status would only manufacture a more confident claim.
Read that file. Each task carries a verdict:

| Verdict | Meaning | Your job |
| --- | --- | --- |
| `CONFIRMED` | marked done, every File Plan entry satisfied | nothing |
| `CLAIMED-UNBUILT` | marked done, entries genuinely absent | **verify by hand** |
| `STALE-FILE-PLAN` | marked done, every gap is a file that moved | propose path fixes |
| `DEVIATION-RECORDED` | marked done, every gap explained in the task's own `### Deviations` | leave alone; the departure is already written down |
| `DONE-UNCLAIMED` | not marked done, everything present | propose closing it |
| `PARTIAL` | some entries present | usually leave alone |
| `NOT-STARTED` | nothing present | leave alone |
| `NO-FILE-PLAN` | nothing checkable | consider backfilling a File Plan |
| `DROPPED` | explicitly dropped | leave alone |

Plus `untracked_work`: files **added** to the repo that appear in no File Plan.

## 3. Verify before you touch anything

**Do not trust the verdict as the finding.** It is evidence about paths, not
about behaviour. For each `CLAIMED-UNBUILT` task, spend a moment establishing
which of these it actually is:

- **Genuinely unbuilt.** The work never happened. The status is wrong.
- **Built differently.** The task shipped, but under different filenames than
  planned. Check the Acceptance Criteria against the code, not the File Plan.
- **Deliberately abandoned.** Some File Plans describe throwaway spikes and
  scaffolding that were never meant to survive. Read the task's own words.
- **Superseded.** A later task replaced this one's approach.

Delegate the "does this behaviour exist anywhere" searches to a read-only search
agent rather than reading files into this session one at a time.

For `untracked_work`, cluster the files into coherent units of work before
proposing anything. Forty files usually means three or four real tasks, not
forty. Ignore test files whose subject is already covered by an existing task.

## 3b. The behavioural pass (`--behaviour` only)

**Skip this entire section unless `$ARGUMENTS` contains `--behaviour`.** It is opt-in because it
is the most expensive thing in this suite: one read-only agent per task, against a check that
costs nothing. A run without the flag behaves exactly as it always has.

### What it is for

Everything above answers one question: are the files a task named actually there. That question has
a blind spot, and it is not a small one. **A task whose File Plan is complete and whose behaviour
is wrong reads as `CONFIRMED`.** Measured on a fixture built for it: a `list_widgets(limit=2)` that
accepts the argument and returns everything satisfies every path, passes its own suite, and the
path check calls it confirmed with the words "the code agrees". No amount of looking at filenames
reaches that, which is why this is a second pass and not a better first one.

### Scope

Tasks the script marked `CONFIRMED` or `DONE-UNCLAIMED`, in the phase named by `--phase`. Those are
the tasks making a claim the path check already accepted, so they are the ones where a second
opinion can still change something. **Require `--phase`**: without it this runs over every task in
the project, which is the version of this command nobody will run twice.

Tasks with no numbered acceptance criteria are skipped, and counted as skipped in the report. There
is nothing to check them against, and inventing criteria from the prose would produce findings
against a requirement nobody wrote.

### How to run it

One read-only search agent per task, not one for the phase. Each brief carries: the criterion's
full text, its ID, the task's File Plan, the phase's directories, **and the task's own
Implementation Notes and Progress Notes**. Ask for the code that implements the criterion, or the
absence of it, with file and line evidence either way.

**The notes are not optional context, and leaving them out manufactures findings.** Measured on
this repository's phase 7: a brief carrying only the criteria and the File Plan produced two
findings, and both were wrong. `Added latency on a non-agy Bash call is measured and recorded`
came back `missing`, because no code measures latency; the measurement was taken once by hand and
written into the task's Implementation Notes, which is what "recorded" meant. `An agy invocation
produces a metric the collector accepts, confirmed by its response` came back `unchecked`, because
the code discards the response; the collector's `{"partialSuccess":{}}` and its HTTP 200 are in the
same notes.

Both are the same shape, and it is a common one: **a criterion satisfied by evidence rather than by
code**. Measurements, live-run confirmations, decisions recorded after an experiment. An agent
given only the code will call every one of them missing, and the findings will look exactly like
real ones.

Delegating matters for a reason beyond cost. The evidence for a criterion is a handful of lines,
and reading whole files into this session to find them fills the context that the judgement at the
end needs.

### Classify each gap

| Gap | Meaning | Example |
| --- | --- | --- |
| `missing` | nothing in the code addresses the criterion | the criterion asks for pagination; there is none |
| `partial` | some of it is implemented, not all | the parameter is accepted and ignored |
| `contradicts` | the code does something incompatible with it | the criterion says at most N, the code returns all |
| `unrequested` | behaviour exists that no criterion asked for | an undocumented admin bypass |

**Every finding carries file and line evidence.** A finding with no evidence is this command
guessing, and it will be believed, because it arrives wearing the same format as the measured ones.
Where the agent could not reach a conclusion, that is a third outcome and it is reported as
`unchecked`, not folded into `missing`. "I could not tell" and "it is not there" are different
facts and only one of them is a defect.

### The outcome contract

**No findings:** change no file, and say `converged`, naming what was checked: which tasks, which
criteria by ID, and how many were skipped for having none. A bare "converged" is worth nothing,
because it does not distinguish a phase that was checked from one where nothing was checkable.

**Findings:** propose, and wait. Each proposal cites `<task>/<AC>` and its gap type, as in
`1.01/AC2 contradicts`. Propose reopening the task, or a new task for the shortfall, per the
project's Spec Model. Apply only what the user confirms, and append a dated line to the task's
Progress Notes for each applied change.

**Either way, write a dated report into `analysis/`** (`YYYY-MM-DD-converge-behaviour-phase-N.md`)
recording what was checked, what was found, and what it cost. A run that finds nothing is a
measurement and deserves a record as much as one that finds something: the question of whether this
pass is worth its price is answered by a series of those reports, and only by those.

**Never mark a task Complete on this evidence alone.** The pass reads code; it does not run
anything. The `**Verification:**` command remains the only executed check in the suite, and reading
code is weaker evidence than running it, not stronger.

## The Spec Model shapes what you may propose

Ask `sdd:resolve-task-paths` for the project's **Spec Model** before proposing anything. It says
what a project does to a document when the requirement behind it changes, and it changes the shape
of a proposal rather than its subject:

- **`flow-back`** (the default): propose editing whichever document is wrong, and reconcile the
  rest. This is what the suite has always done.
- **`flow-forward`**: a Complete document is a record of what was decided and shipped. **Never
  propose editing a Complete task's acceptance criteria.** Propose a new task or spec that
  references the old one by number and says what changed. Correcting a status or a File Plan path
  is still fine: those are facts about the document, not the decision it records.
- **`living`**: the spec is the contract. Propose the edit to the spec, and revise the tasks under
  it rather than the other way round.

Say which model you are working under when you report. A proposal that silently assumes the wrong
one is worse than a wrong proposal, because there is nothing in it to disagree with.

## 4. Report, then propose

Present a short summary first: counts per verdict, the headline percentage, and
the clusters you found in the untracked work. Then propose a concrete edit list,
grouped by kind:

- status corrections (with the evidence for each, one line)
- File Plan path fixes for moved files
- new task files for untracked work, numbered per the project's Task File Pattern
- tasks that need a File Plan backfilled

**Ask for confirmation before writing.** Let the user strike items from the list.
Never mark a task Complete on the strength of file existence alone.

## 5. Apply

For each confirmed correction:

- Update `**Status:**` and `**Last Updated:**`.
- Append a dated line to the task's **Progress Notes** saying what was
  reconciled and on what evidence. A silent status flip is how the next drift
  starts.
- When a status changes, update the parent phase spec's **Tasks Summary** table
  so the two agree.
- New task files use the `sdd:task-template` skill and the project's numbering.

Write the reconciliation itself into `analysis/` as a dated report
(`YYYY-MM-DD-converge-phase-N.md`) so the next reader can see what was
reconciled and why, rather than finding unexplained status changes in the diff.

## 6. Commit

The spec repo commits in the same turn, per the spec-repo commit policy:

```sh
git -C .specs add -A && git -C .specs commit -m "Converge phase N task status with the code" && git -C .specs push
```

Never touch the main repo's index. No product code changes as part of a
converge; if the reconciliation reveals missing work, that is a new task, not an
edit made here.

## Notes

- `NO-FILE-PLAN` being large is itself a finding: those tasks cannot be
  reconciled by anything, now or later. Backfilling File Plans on the open ones
  is usually worth more than arguing about a handful of statuses.
- A high `CLAIMED-UNBUILT` count on an old phase is normal and not alarming;
  paths rot as a codebase is refactored. The number to watch is the trend across
  runs, not its absolute value.
- `--strict` exits non-zero when anything is `CLAIMED-UNBUILT`, for use in a
  hook or CI gate once the tree is clean.
