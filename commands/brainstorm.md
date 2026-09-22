---
argument-hint: "<what you want to build, in your own words>"
description: Turn an idea into a design you have approved, then hand it to the command that owns the document
---

Work the idea in `$ARGUMENTS` into a design, by asking, and hand the result to whichever command
owns the durable document.

## Arguments

The arguments arrive as one string in `$ARGUMENTS`. Read them from there: the idea, in the user's
own words, and nothing else. If `$ARGUMENTS` is empty, ask what they want to build and stop.

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1` binds to
the **second** token, and typed as a slash command it arrives as the literal text `$1`.

## Why this command exists

The lane rubric routes work three ways and stops at the edge of the fourth: if you do not yet know
what done looks like, neither lane applies. Every other lane has a command behind it. That one had
a sentence.

This is that command. It is the front of the pipeline, where a wrong answer is cheapest to fix and
most expensive to carry, and it exists to end with a design the user has said yes to.

**It never writes the planning document.** `/sdd:plan`, `/sdd:generate-specs` and
`sdd:plan-template` own those formats, and they carry status headers, dates and progress tables so
the document still tells a human where things stand weeks later. A dialogue that emits its own
format produces a one-shot briefing with none of that, and then two documents disagree.

## Step 1: Classify, and say so

Decide how much process the request earns, **state the classification and the reason in one
sentence, and continue**. Saying it out loud is what lets the user overrule it; deciding silently
is how a one-line fix acquires a design document and a new subsystem acquires none.

| Level | What it is | What it ends with |
|---|---|---|
| **Question** | A feasibility or "is this possible" ask. Output is an answer, not code you keep | A recommendation. Anything built is labelled throwaway |
| **Bounded** | A change to a flow that already exists in this repository, readable now | A short design in the conversation, then implementation |
| **New ground** | A new subsystem, a new project, or a change to how components fit together | A design recorded in `.specs/docs/designs/`, then `/sdd:plan` or `/sdd:generate-specs` |

**Bounded measures the repository, not your familiarity.** If the flow being changed is not already
here to read, it is not bounded. When two levels both fit, take the heavier one.

**The ratchet is one way.** Complexity found mid-dialogue raises the level: say so and continue at
the higher one. Nothing lowers it.

## Step 2: Ask, one question per turn

Ask **at most five questions**, and **one per turn**.

One at a time is not politeness. Asked together, five questions get five answers optimised against
each other in a single breath; asked one at a time, an answer routinely changes what the next
question should be, and the questions you would have wasted are the ones you never ask. Do not show
the queue: it invites answering ahead and defeats the ordering.

Prefer a question with two or three named options and a recommendation over an open one. An open
question is right when the options are the thing you do not know yet.

**Ask about what changes the design.** Purpose, the constraint that is real, what "done" looks like,
and what is explicitly out of scope. Do not ask about stakeholders, timelines, priority or rollback
as a matter of routine: those have an answer for every project, which is why they are worthless
here, and they spend the budget before reaching whatever this request actually left open.

Stop asking when the next question would not change what gets built.

## Step 3: Propose, then stop

Present the design. Scale it to the level: a few sentences for **Bounded**, sections for **New
ground**, two or three sentences for a **Question**'s recommendation.

Cover what it does, what it touches, what it deliberately does not do, and how anyone will know it
works. Name the approach you recommend and say what you give up by taking it. Where you chose a
default because the input was silent, say that you did.

**Then stop and wait for an explicit yes.** Presenting a design and starting work in the same turn
is skipping the gate, and the gate is the whole point: a session that treats its own design as
settled because it was the one that wrote it has removed the only review the design was going to
get. A design may be two sentences; the approval never scales down with it.

If the answer is no, revise and present again. Do not implement a design the user has not approved.

## Step 4: Hand it off

| Level | Where it goes |
|---|---|
| **Question** | Report the recommendation. Nothing is recorded unless the user asks |
| **Bounded** | Implement it directly, following the practice rules. No planning document |
| **New ground** | Record the design at `.specs/docs/designs/YYYY-MM-DD-<topic>.md`, then invoke `/sdd:plan`, or `/sdd:generate-specs` if a PRD already exists |

**Write no plan, no phase spec and no task file yourself.** Hand the approved design to the command
that owns that format and let it produce the document. A design record is the one artifact this
command may write, and only at **New ground**, and only after approval.

If the project has no `.specs/` at all there is nowhere to record a design: say so, and either
offer `/sdd:spec-repo-init` or carry the design in the conversation.

## What this command is not

- **Not `/sdd:clarify`.** That works on a document that already exists and resolves its open
  markers. This works on a request that has no document yet.
- **Not a planner.** See step 4.
- **Not a gate on small work.** A one-line fix classified as a **Question** or **Bounded** should
  leave this command in two turns. If it routinely takes longer, the classification is wrong.

---

The three-level classification and the approval gate follow the `superpowers:brainstorming` skill (MIT, Copyright (c) 2025 Jesse Vincent).
This is a reimplementation, not a copy, and it differs in
the part that matters here: it writes no document of its own and ends by handing the approved
design to the commands that own the templates, because a durable planning document needs a status
header, dates and a progress log that a one-shot briefing does not have.
