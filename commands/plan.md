---
argument-hint: [plan-filename]
description: Create a new structured implementation plan (interactive)
---

Create an implementation plan at the path given in `$ARGUMENTS`.

## Arguments

The arguments arrive as one string in `$ARGUMENTS`. Read them from there:

- **the plan path** — where the plan file should be written

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1`
binds to the **second** token, and typed as a slash command it arrives as the literal text
`$1`. Neither is the first argument. `$ARGUMENTS` is correct on both paths.

Here are my initial specifications:

$ARGUMENTS

## Your Task - Part 1: Information Gathering

**If the conversation already covered this, skip to Part 2 and write the plan.** Re-asking what was
just settled is the most common way this command wastes a session.

Otherwise, scan the request against the same taxonomy `/sdd:clarify` uses, and rate each category
Clear, Partial or Missing. Keep the ratings to yourself; they order the questions.

1. **Scope**, and what is explicitly out of it
2. **Data and state**: entities, identity, lifecycle, volume
3. **Error and empty states**: what happens when there is nothing, or when it fails
4. **Non-functional targets**: latency, throughput, availability, retention, limits
5. **Integrations**, and what each one does when it is down or slow
6. **Edge cases**: concurrency, conflicts, boundaries, rate limits
7. **Terminology**: one name per thing, used consistently
8. **Testability of the criteria**: could two people disagree about whether one is met
9. **Open markers**: every `[NEEDS CLARIFICATION: ...]` already written down

**Ask at most five questions, one at a time, each with a recommended answer and one sentence on why
it matters.** Prefer the `AskUserQuestion` tool. Ask only where the answer would change what gets
built or how anyone would check it.

This replaced a fixed question bank that asked about stakeholders, timelines, priority levels and
rollback strategy on every invocation. Those questions have an answer for every project, which is
exactly why they were worthless: a question whose answer you could have guessed buys nothing, and
five of them spend the attention budget before reaching the one thing that was genuinely undecided.
**Do not reintroduce a standing list of questions.** What to ask comes from what this request left
open.

Where something stays unresolved, write `[NEEDS CLARIFICATION: <the question>]` into the plan
rather than guessing, and say in your summary that `/sdd:clarify` resolves them.

## Your Task - Part 2: Plan Creation

Once you have sufficient information (either from our prior discussion or from my answers), create a comprehensive implementation plan using the **`sdd:plan-template`** skill.

The **`sdd:plan-template`** skill owns the canonical template and tells you where to read it from. Read it for the structure, substitute placeholders with real content, and follow the skill's usage guidance (when to skip sections, how to adapt to scope, etc.).

**Adapt the template to the scope of the work.** Small bug fixes or simple features don't need every section. Use your judgment to include only the sections that add value. Skip or collapse sections that would otherwise be empty or trivially short. The goal is a self-contained plan that gives a developer full context at a glance, not a rigid form to fill in.

**The skill's Quick Reference names six sections that judgment does not reach**, the Progress Summary phase table among them. Later commands read and write those sections, so a plan missing one loses status tracking without saying so. Adapt everything else; write those six even on a plan that takes an afternoon.

If the file at that path already exists with meaningful content (e.g., user-written requirements or context), **preserve that content**. Incorporate it into the plan rather than overwriting it. You can restructure it under the plan's sections, but don't lose information.

## Your Task - Part 3: Commit the Spec Repo

If the plan path lives inside a nested spec repo, commit and push it in this same turn, per the spec-repo commit policy, before reporting:

```sh
git -C .specs add -A && git -C .specs commit -m "<concise description>" && git -C .specs push
```

Skip the push if the repo has no `origin` remote. Never touch the main repo's index.

## Your Task - Part 4: Confirmation

After writing the plan, briefly report to the user:

- Path to the plan file
- Number of phases defined and their names
- Any open questions or assumptions you made that the user should validate
- Suggest using `/sdd:implement <plan-path> [section-or-phase]` to start working on it, or `/sdd:generate-specs <plan-path> <specs-dir>` if you want to promote each phase into its own standalone spec file
