---
name: receiving-review
description: What to do with code review feedback, including feedback that is wrong: verify each finding against the code before acting, separate a defect from a preference, and say plainly when a finding does not hold. Use when receiving a review from a person, from a review agent, or from a tool, before implementing any of its suggestions.
---

# Receiving a Review

A review is evidence, not instructions. The default response to criticism is to agree and comply,
and a session that does that turns a review into a mechanism for **introducing** defects that the
reviewer only suggested.

The rule is simple and almost never followed: **check the finding against the code before you
touch anything.**

## Why this needs saying

A finding arrives with the authority of having been written by a reviewer. It usually names a
line, a value or a behaviour, which means it can be checked in seconds. Almost nothing checks it.

What happens instead is that the code is changed to match the finding, the reviewer is thanked,
and nobody ever learns that the finding was about a branch that cannot be reached, or an argument
that is already validated upstream, or a race that the lock above it prevents. The change is a net
loss and looks like collaboration.

## Three verdicts, not two

Sort every finding into one of these, and say which:

| Verdict | What it means | What to do |
|---|---|---|
| **Wrong** | The finding does not hold against the code | Say so, cite the line or the behaviour that shows it, and change nothing |
| **Right** | It is a real defect | Fix it |
| **Right, but a preference** | Not a defect. A different way of doing it | Say that it is a preference, then follow it unless it conflicts with the project's conventions |

The third row is where the friction actually lives. Collapsing it into "right" produces silent
churn; collapsing it into "wrong" produces an argument about taste. Naming it as a preference and
following it anyway is usually correct and costs nothing, but say which it was.

## Verify first, and verify specifically

For each finding, before changing anything:

1. **Read the code it names.** Not the diff, the code, with enough context to see what reaches it.
2. **Decide whether the claim holds**, on that reading.
3. **If it does not hold, say why, with the evidence.** Naming the line that refutes it is the
   whole answer.

A finding you cannot evaluate is not a finding to implement: **ask.** "I do not understand what
this is asking" is a complete and useful response. Guessing at an unclear finding and implementing
the guess is the worst available outcome, because it is then attributed to the reviewer.

## Disagreeing is the expected outcome, not a failure to cooperate

If a review has ten findings and all ten are right, that is possible. If a session reports all ten
as right on every review it ever receives, that is not a run of good reviews, it is a session that
is not checking.

Reporting a finding as incorrect, with the evidence, is a normal result. Say it plainly, once,
without hedging and without a paragraph of apology. If the reviewer comes back with something new,
re-evaluate on the new information; repetition of the same claim is not new information.

## Where this sits

- **`/sdd:bug`** is the lane for a defect a review uncovers that is bigger than the review.
- **A finding that contradicts the task's acceptance criteria** is a question for the task, not a
  change to make quietly. Raise it.
- **Nothing here is enforced.** There is no hook for this, unlike the commit policy and the
  verification gate. It is a discipline, which is exactly why it has to be written down: the
  behaviour it corrects is the comfortable one.

---

The three-verdict split and the verify-before-acting rule follow `superpowers:receiving-code-review` (MIT, Copyright (c) 2025 Jesse Vincent).
This is a reimplementation, not a copy, and it differs in naming the preference verdict explicitly
as a third outcome rather than folding it into agreement, because most real friction sits there
and collapsing it is what produces silent churn.
