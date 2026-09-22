---
description: Generate a PR title and description from an implementation plan file
---

Please help me create a PR title and description from an implementation plan file.

## Resolve the plan file

1. If an argument was provided after `/sdd:pr-msg`, treat it as the plan file path (resolve relative paths from the repo root).
2. Otherwise, fall back to the file the user currently has open in the IDE (see the `ide_opened_file` context). Use it only if it looks like a plan file (typically under `.specs/docs/plans/`, `.specs/docs/tasks/`, or a legacy `tmp/implementation/` or `docs/plans/`, or contains a "Progress Summary" / "Phases" section).
3. If neither is available or the candidate doesn't look like a plan, stop and ask the user which plan file to use. Do NOT guess.

Read the entire plan file before writing anything.

## What the PR message must cover

- Cover the **whole plan, every phase**, regardless of each phase's status (not started, in progress, complete). The PR ships the plan as a single unit, so the description describes the end state, not the current progress.
- Do **not** mention phase numbers, "Phase X of Y", in-progress status, percentages, or progress tables in the output.
- Do **not** include test plans, acceptance criteria, "how to verify", or QA checklists **unless the user explicitly asked for them** in their `/sdd:pr-msg` invocation (e.g. `/sdd:pr-msg path/to/plan.md include tests`).
- Do not reference the plan file path, plan doc, "implementation plan", or any internal planning identifiers in the output. The PR description must stand on its own for a reader who has never seen the plan.
- Strip plan-only language: no "Phase 4 will...", no "as described in the plan", no task IDs like `T1.2`.

## Level of detail (important)

The description must read as a behavioral / capability summary, NOT a diff walkthrough. Scope can still shift during implementation, so any internal specifics in the message are a liability if a phase is cut or reshaped.

**Stay at this level:**

- User-visible behavior changes ("expired sessions now refresh transparently instead of logging the user out").
- Public contracts the PR introduces or alters: HTTP endpoints, CLI flags, config keys, environment variables, request/response field names that other code or operators rely on.
- Migrations that operators must know about (a new table exists; a column became NOT NULL; defaults changed), described in one short sentence — not column-by-column.
- Defaults, feature flags, and rollout-affecting toggles.

**Do NOT include in the description:**

- Names of internal services, structs, modules, repositories, hooks, stores, interceptors, helper functions, or private fields. If a reader can't import it or call it, don't name it.
- Internal database column lists, index names, FK on-delete behaviors, transaction boundaries.
- Cryptographic or encoding specifics ("SHA-256", "32 random bytes", "base64url", token lengths) unless the value is part of a public contract.
- Algorithmic mechanics: single-flight semantics, retry counters, in-flight Promise sharing, locking strategies, queue mechanics, etc.
- Per-file or per-module breakdowns. Group by user-visible capability, never by code layout.
- Anything phrased as "we now do X internally so that Y" — collapse to just "Y".

If you find yourself writing a bullet that would only mean something to a developer reading this exact codebase, delete it or raise it to the behavior level.

**Bullet budget.** Aim for 3–8 bullets total across the `## Changes` section, grouped by user-visible area (e.g. "API", "Web UI", "Operators / config"). Never group by phase. Prefer one tight sentence per bullet over nested sub-bullets.

## Generate the output

Produce exactly two artifacts:

### 1. PR title

- One line, conventional-commit format (`feat:`, `fix:`, `refactor:`, `chore:`, `perf:`, `docs:`, etc.).
- Infer the type from the plan's nature: new capability => `feat`, bug regression => `fix`, internal cleanup => `refactor`, etc.
- Keep it under ~72 characters. Imperative mood. No trailing period.

### 2. PR description

Use exactly these sections, in this order, with these headings (Markdown `##`):

```
## Summary

<2-4 sentences. What this PR delivers end-to-end, in plain terms. No phase language.>

## Motivation

<Why this work is needed. Pull from the plan's Problem Statement / Motivation / Purpose sections. Mention the user-visible symptom or business reason, not the implementation.>

## Changes

<Grouped by user-visible area (API, Web UI, Operators / config, Docs, etc.), not by phase and not by code layout. Use bullet points. Each bullet describes an observable change: a new or altered endpoint, a new config key, a behavior users will notice, a migration operators need to know about. Do NOT name internal modules, classes, columns, or algorithms — see the "Level of detail" rules above. Merge related work into one bullet when it makes sense. Target 3–8 bullets total.>

## Notes

<Optional. Use for: breaking changes, feature flags / config defaults, migration considerations, rollout caveats, follow-ups intentionally left out of scope. Keep each note to one or two sentences and stay at the behavioral level — no internal naming. Omit the section entirely if there's nothing to say.>
```

If the user passed `include tests` (or similar) in the invocation, append a final `## Test plan` section with a brief bulleted list derived from the plan's success criteria / acceptance criteria. Otherwise omit it.

## Rules

- Do NOT include `Co-Authored-By:`.
- Do NOT include line counts, file counts, or test counts.
- Do NOT offer to push, open the PR, or run `gh pr create`. Just print the title and description.
- Do NOT include emojis unless the user explicitly asked for them.
- Do NOT wrap the output in extra commentary; print the title, then the description, then stop.

## Output format

Present the result as two separate fenced markdown code blocks so each can be copied independently. Use the language tag `markdown` on both fences.

First, a heading and a fenced block for the title:

````
## Title

```markdown
<the title line>
```
````

Then, a heading and a fenced block for the description:

````
## Description

```markdown
<the rendered markdown description, starting with ## Summary>
```
````

Do not print anything else before, between, or after these two blocks.
