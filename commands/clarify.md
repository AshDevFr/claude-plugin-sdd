---
argument-hint: "<document path>"
description: Work an ambiguous document down to decisions, and record them where the next reader looks
---

Resolve what is unclear in the document at `$ARGUMENTS`, by asking, and write the answers back.

Works on a PRD, a phase spec, a plan or a task file.

## Arguments

The arguments arrive as one string in `$ARGUMENTS`. Read them from there: the path of the document
to clarify, and nothing else.

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1` binds to
the **second** token, and typed as a slash command it arrives as the literal text `$1`.

## Why this command exists

A document can already say it does not know something: `/sdd:generate-tasks` and `/sdd:plan` write
`[NEEDS CLARIFICATION: ...]` rather than guessing, and `/sdd:implement` refuses to start a section
that still carries one. That is a complete mechanism for *not* guessing and no mechanism at all for
*deciding*. The markers accumulate, and the decision gets made eventually by whoever is in a hurry.

This is the other half. It reads the document, works out what is genuinely undecided, asks, and
puts the answer back into the document so the next reader inherits a decision instead of a
question.

## Step 1: Read the document, and scan it

Read the whole document. Then rate each category below **Clear**, **Partial** or **Missing**. Keep
the ratings to yourself: they order the questions, they are not a report.

**The taxonomy:**

1. **Scope**, and what is explicitly out of it
2. **Data and state**: entities, identity, lifecycle, volume
3. **Error and empty states**: what happens when there is nothing, or when it fails
4. **Non-functional targets**: latency, throughput, availability, retention, limits
5. **Integrations**, and what each one does when it is down or slow
6. **Edge cases**: concurrency, conflicts, boundaries, rate limits
7. **Terminology**: one name per thing, used consistently
8. **Testability of the criteria**: could two people disagree about whether one is met
9. **Open markers**: every `[NEEDS CLARIFICATION: ...]` in the document

**Category 9 outranks the rest.** A marker is a question someone already decided was worth asking
and declined to answer. Everything else on this list is a question you are proposing; that one is
already accepted.

An adjective with no number behind it belongs in whichever category it sits in: "fast", "robust",
"intuitive" and "scalable" are Missing, not Partial, until something says what they mean.

## Step 2: Choose at most five questions

Five is the whole session, not five per category.

Ask a question only if the answer would **change what gets built, or change how anyone would check
it**. That test excludes most of what is tempting to ask:

- Implementation method and tech-stack preference, unless the document's criteria depend on it
- Task breakdown and sequencing, which is `/sdd:plan`'s job
- Anything already answered elsewhere in the document, or earlier in this conversation
- Stylistic preference

Where more than five survive that test, take the five with the highest impact times uncertainty,
and spread them across categories rather than spending three on one. Say at the end which ones you
dropped and why, so the owner can pull one back.

If none survive, say so and stop. A run that asks nothing and reports a clean scan is a good
outcome, not a failed one.

## Step 3: Ask them one at a time

**One question per turn. Never show the queue.** Showing five questions at once gets five answers
optimised against each other in one breath; asking one gets an answer to that question, and the
answer often changes what the next question should be.

Prefer the **`AskUserQuestion`** tool. Each question carries:

- The question itself, as a full sentence ending in `?`, that makes sense to someone who has not
  read the document. A heading, a label or a criterion ID is not a question: `Retention policy
  (SC-03)` is invalid, `How long are audit records kept before deletion?` is the question.
- **One sentence on why it matters**: what goes wrong, or what cannot be checked, if it stays open.
- **A recommended answer**, with the reason it is the recommendation. You have read the document
  and the codebase; the owner is asking you partly for that judgement. An answer set with no
  recommendation pushes the work back.

Answer length is the owner's business. **Do not constrain them to a few words**, and do not reject
a prose answer for being long: a sentence of reasoning attached to a decision is worth more in the
document than the decision alone.

If an answer is ambiguous, ask again about that same question rather than moving on. It does not
count twice.

Stop early when the remaining questions have been made unnecessary by answers already given, or
when the owner says to stop.

## Step 4: Write each answer back, as you get it

Do this **after each answer**, not in a batch at the end. A context loss halfway through should
leave three decisions recorded, not none.

1. **Record it.** Ensure the document has a `## Clarifications` section, with a
   `### Session YYYY-MM-DD` subheading for today. Put it after the document's header block and
   Quick Links, before its first substantive section, so a reader meets the decisions before the
   text they changed. Append one line:

   ```md
   - Q: <the question as asked> -> A: <the answer as given>
   ```

2. **Apply it where it belongs.** The log is the record; it is not the specification. Edit the
   section the answer actually affects: a scope answer edits Scope, a latency answer edits the
   success criteria and makes them measurable, an error-state answer edits the criteria or adds
   one. Where a criterion gains an ID under the `sdd:task-template` or `sdd:spec-template` scheme,
   cite it in the log line so the two can be matched later.

3. **Delete what the answer contradicts.** This is the step that gets skipped. If the document
   offered two possibilities and the owner picked one, the other goes. Leaving it makes the
   document say both things and the next reader has to hold this conversation again.

4. **Replace the marker it resolves.** A `[NEEDS CLARIFICATION: ...]` whose question was just
   answered is replaced by the answer, in place. Do not leave it beside the answer.

Preserve everything else: heading order, structure, and any section this conversation did not
touch.

## Step 5: Commit the spec repo

If the document lives inside a nested spec repo, commit and push in this same turn, per the
spec-repo commit policy:

```sh
git -C .specs add -A && git -C .specs commit -m "Clarify <document>: <what was decided>" && git -C .specs push
```

Skip the push if the repo has no `origin` remote. Never touch the main repo's index.

## Step 6: Report

- What was decided, one line each
- Which sections changed
- **What is still open**: markers you did not get to, questions you dropped, and categories rated
  Missing that did not earn a question. Name them. A clarify run that reports only what it fixed
  reads as "this document is now clear", which is a stronger claim than five questions can support.

## Not in scope

Deciding on the owner's behalf. If an answer does not arrive, the marker stays and the document
stays unclear, which is the honest state. Writing code, generating tasks, or restructuring the
document into a different template: those are other commands.
