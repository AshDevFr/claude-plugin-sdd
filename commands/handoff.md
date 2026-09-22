---
argument-hint: "[what matters most, in a few words]"
description: Capture what dies with this session, so the next one resumes instead of rediscovering
---

Write the handoff for whoever picks this up next, then print the prompt to paste.

`$ARGUMENTS`, if present, says what matters most. Use it to choose what goes in, not to change the
shape of the document.

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1` binds to
the **second** token, and typed as a slash command it arrives as the literal text `$1`.

## Why this command exists

A session ends for reasons that have nothing to do with the work: a restart, an update, a context
limit. What the spec repo holds survives that. What was decided in conversation does not, and
neither does what was tried and abandoned, which is the most expensive thing to lose because the
next session will try it again.

## What goes in, and what must not

**Capture only what dies with the session.** The successor can read `.specs/` and `git log`.

**Never restate task statuses, commit subjects or plan content.** A copy of them drifts from the
moment it is written, and then two documents disagree about the same work. That is the drift
`/sdd:converge` exists to detect, and writing a second source of truth to save one lookup is a bad
trade.

**Never record as done anything the verification gate has not seen.** A handoff is an easy place
to launder a claim, because the successor has no way to tell. If the command has not run, say it
has not run.

**Write it from the transcript, not from memory of what the plan was.** A decision that was not
actually taken does not go in, however sensible it sounds.

## Step 1: Find what is in flight

Do this first. It is the only time-critical part, and the only part that can make restarting
*right now* the wrong move.

```sh
sdd-dashboard status                 # is a dashboard serving?
git -C .specs status --short         # uncommitted spec work?
git status --short                   # uncommitted code?
```

For each, record what it writes, what invalidates it, and how to check on it later.

**Subagents are the part nothing mechanical can find.** A dispatch made twenty turns ago is
invisible to every check above; only this session knows it happened. Go through the transcript and
list every subagent still running or whose result never arrived.

**A subagent does not survive a restart.** It dies mid-work, leaves no partial result, and sends
no notification. So for each one, copy **the dispatch brief verbatim** into the appendix, and say
plainly that it was lost. The successor then re-dispatches exactly, instead of reconstructing a
brief from a summary of a brief.

**Background commands are different, and worse.** They are children of the session's process, so a
restart either kills them or orphans them to keep running with nobody watching. Say which you do
not know, because both are possible and they need opposite responses. Record the resume command
where one exists.

## Step 2: If something is in flight, ask before assuming

**Do not write the handoff and move on.** Stop and ask, once, in one question:

> `<what is running>`, `<how far along, if knowable>`. Stop now and lose it, or wait for it to
> finish first?

Name the thing and its cost concretely. "A subagent is running" is not enough to decide on;
"a reviewer dispatched four minutes ago, and an eval run 30 of 32 cases in at about $28" is.

This is the same reason `/sdd:plan` and `/sdd:generate-tasks` stop before writing: the answer
changes what happens next, and guessing it wastes either the work or the user's time.

### If they choose to wait

1. **Write the handoff now anyway**, per step 3. The session may still end for a reason nobody
   chose, and a handoff that exists and is slightly stale beats one that was never written.
2. **Stop starting new work.** No new dispatches, no new background commands, and no edit that
   could invalidate what is running. This is the part that gets skipped: waiting productively by
   starting something else recreates the exact problem being waited out, and the new thing is
   then in flight at the moment the session ends.
3. **Wait**, and say what is being waited for.
4. **When it finishes, amend the handoff.** Replace each item in `## In flight` with what actually
   happened: completed and what it produced, or failed and how. An `In flight` section describing
   work that has since finished is worse than none, because the successor acts on it.

### If they choose to stop now

Write it, with `## In flight` recording each item as of this moment: what it was, what it wrote,
what state it leaves behind, and how to resume or re-dispatch it. A subagent is marked **LOST**,
because it is.

### If nothing is in flight

Say so in one line and carry on. Do not ask a question with no consequence.

## Step 3: Write the document

`.specs/docs/handoffs/YYYY-MM-DD-<slug>.md`, in this order:

```markdown
# Handoff: <what this session was doing>

**Session ended:** <date> — <why, if it matters>

## In flight — read before you restart
<Each item: what it writes, what invalidates it, how to check, how to resume.
 Subagents marked LOST, with a pointer to the appendix. Omit the section if empty.>

## Where I am
<One paragraph. The task in hand and how far into it.>

## Decided this session, not yet in any file
<The decisions the next session would otherwise re-litigate, with the reason. Not what was
 decided and then written down, which is in the files.>

## Tried and abandoned
<With why. This is the section that saves the most time and gets written last when tired.>

## Next action
<One concrete step. Not a list.>

## Read these
<Paths, each with what it answers. Confirm each exists before writing it.>

## Appendix: briefs for lost subagents
<Verbatim. Not summarised.>
```

**Keep the narrative under 60 lines: `Where I am`, `Decided`, `Tried and abandoned`,
`Next action` and `Read these`.** A handoff nobody reads is worse than none, and the failure here
is dumping the session rather than choosing from it.

**`In flight` and the appendix do not count**, and the reason is not generosity. Those two are
bounded by what is actually running: nobody has forty things in flight, and a brief is as long as
it is. The narrative is the part that can absorb an entire session if nothing stops it, so it is
the part worth capping. A cap on the total punishes the sections that cannot bloat in order to
discipline the one that can, and what it squeezes first is the *reasons* — which are the whole
point, because a decision recorded without its reason gets re-litigated at the same cost as not
recording it.

The first real use of this command measured 39 lines of narrative for a session spanning most of a
day and three phases, with nothing in flight. Treat 60 as roughly half again as much headroom as a
busy session needs, and as a number one run is weak evidence for.

Omit any section that would be empty. An empty heading reads as a gap in the record rather than an
absence of the thing.

## Step 4: Commit it

The spec-repo commit policy applies to this like anything else, and a handoff left uncommitted is
the exact failure it exists to prevent:

```sh
git -C .specs add -A && git -C .specs commit -m "docs: handoff, <what was in hand>"
```

Push if the spec repo has a remote.

**If the project has no `.specs/`**, print the handoff instead and say it was not saved anywhere.
Do not create a spec repo to hold it; that is `/sdd:spec-repo-init`'s decision and not one to make
on the way out of a session.

## Step 5: Print the prompt

Print a short prompt and nothing else. **Not the document**: the point is that the successor reads
the file, and pasting the whole thing into a new session spends the context this was meant to save.

```
Resume work on <project>.
Read <path to the handoff> first — it has what is not in any file.
Then: <the next action>.
```

Where something is in flight, add one line above that, because it decides whether to start at all:

```
Before anything: <what is running>. <How to check it.> <What must not be touched until it finishes.>
```

---

Treat the handoff as an artifact of this session and not a summary of the project. If it reads like
something `/sdd:project-overview` would produce, it is the wrong document.
