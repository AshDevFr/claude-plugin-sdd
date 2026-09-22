---
description: Check the spec tree against itself and report what disagrees, without editing anything
argument-hint: "[docs-dir]"
---

# Analyze

Read the spec tree and report where it contradicts itself. **Nothing is edited.** An inconsistency
between two documents is a question for the owner, not something to resolve by picking one.

`/sdd:converge` asks whether the code matches the documents. This asks whether the documents agree
with **each other**, which is cheaper and worth asking first: an implementer dispatched against a
spec whose task files do not exist spends a session finding that out.

## Step 1: Run it

The `sdd:tidying-spec-repos` skill owns the script. Invoke that skill to learn its base directory,
then:

```sh
out=$(mktemp -t analyze.XXXXXX.json)
python3 <skill-dir>/scripts/spec-analyze.py $ARGUMENTS --json "$out"
```

Needs `python3` and nothing else. Read-only by construction.

## Step 2: Report what it found, in the order it costs

| Finding | What it means | What it usually needs |
| --- | --- | --- |
| `NO-SPEC` | a PRD phase with no spec file | write the spec, or drop the phase from the PRD |
| `MISSING-TASK` | a Tasks Summary row with no task file | `/sdd:generate-tasks`, or remove the row |
| `ORPHAN-TASK` | a task file no summary mentions | add it to the summary, or say why it is standalone |
| `STATUS-DISAGREE` | a row and its task file disagree | the task file is the record; the summary is a copy |
| `DEP-MISSING` | `Depends On` names a task that does not exist | fix the reference or create the task |
| `DEP-INCOMPLETE` | work claimed underway depends on unfinished work | usually a status that was flipped early |
| `NO-VERIFICATION` | a task with no `**Verification:**` | add one, or it cannot be marked Complete honestly |
| `PLACEHOLDER-VERIF` | still the template's bracketed text | the field was never filled in |
| `WEAK-VERIF` | `echo`, `true`, `:`, a bare `cd` | it passes whether or not the work was done |
| `CLARIFICATION` | an unresolved `[NEEDS CLARIFICATION: ...]` | ask the owner; do not guess |
| `UNCOVERED-CRITERION` | a spec success criterion no task claims to cover | a missing task, or a `(covers SC-NN)` nobody wrote |
| `UNKNOWN-CRITERION-REF` | a `covers` naming a criterion that does not exist | a typo, or a criterion that was renumbered |
| `DUPLICATE-CRITERION-ID` | one number used twice in a document | renumber the later one to the next free number |
| `ASSUMPTION-CONTRADICTED` | an assumption and a clarification name the same criterion | check whether the answer overtook the default, and delete the stale one |

Group by finding, not by file. A reader wants to know "do my verifications prove anything",
not "what is wrong with task 2.04".

## Step 3: Propose, and stop

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


Say what you would do about each group and **wait**. Do not edit a document. The one exception is
that you may offer to run `/sdd:generate-tasks` for `MISSING-TASK`, because that is the command
whose job it is.

Two findings deserve saying out loud rather than listing:

- **`WEAK-VERIF` and `PLACEHOLDER-VERIF` mean the gate is decorative for those tasks.** The Stop
  hook proves a command ran; it cannot tell whether the command could have failed. These are the
  tasks where a Complete status means nothing, and only this check finds them.
- **`STATUS-DISAGREE` is usually the summary lagging**, because a summary row is a copy of a fact
  that lives in the task file. Say which you believe and why, rather than reporting the pair.
- **`UNCOVERED-CRITERION` says nobody wrote the annotation, not that the work is missing.** The
  check reads `(covers SC-NN)` references and never infers coverage from prose, deliberately: a
  task whose wording happens to match a criterion is not evidence that it was built. So the two
  repairs are different work. Either a task exists and should say what it covers, or no task
  covers the criterion and one is missing. Say which you believe, from reading the tasks.

- **`ASSUMPTION-CONTRADICTED` is a co-citation, not a proven contradiction.** The script sees that
  a default was recorded for a criterion and that a decision was later recorded about the same
  criterion; it cannot read the two lines and tell you they disagree. Often they agree and the
  assumption is simply now redundant, which is still worth deleting. Read both lines before saying
  which.

Criterion IDs are optional per document, so a tree that has none produces none of the last three
findings. That is why silence about coverage is not the same as full coverage: ask whether the
documents are annotated before reading it as good news.

## Not in scope

Whether the code matches the documents: `/sdd:converge`. Whether the tree is tidy, indexed and
free of finished plans in the wrong directory: `sdd:tidying-spec-repos`.
