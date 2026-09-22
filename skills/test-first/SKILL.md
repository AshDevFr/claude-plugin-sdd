---
name: test-first
description: The failing-test-first loop in the detail the practice rules have no room for: the order, what each step proves, the expected failure at every stage, and the two ways the loop silently becomes worthless. Use when implementing a feature or a fix, before writing implementation code, and when deciding whether a test that passes actually proves anything.
---

# Test First

The practice rules say it in one sentence, because they are always-on text paid for in every
session: *"Failing test first where the behaviour or bug can be captured."* That is the rule. This
is the loop.

## Why the order is the whole thing

A test written after the code it tests is shaped by that code. It passes, it looks like evidence,
and it is indistinguishable afterwards from a test that would have caught the bug. The order is
what makes the difference, and the order is the only part that cannot be recovered later.

This is the same idea the verification gate enforces one layer up. A task's `**Verification:**`
command has to actually run before a status may say Complete, and `/sdd:analyze` reports
verification commands that **cannot fail**. A test that could never have failed is that defect in
miniature: it satisfies the process and proves nothing.

## The loop

### 1. Write the test, and make it fail

Write the smallest test that captures the behaviour you want or the bug you are fixing. Run it.

**It must fail, and it must fail for the right reason.** This is the step that gets skipped, and
skipping it is what makes the rest theatre.

| What you see | What it means |
|---|---|
| The assertion fails, with your expected value against the actual one | Correct. Continue |
| `ImportError`, `ModuleNotFoundError`, a name error, a syntax error | The test is broken, not the code. Fix the test |
| A path or fixture error | The harness is wrong. Fix that first |
| **It passes** | **Stop.** Either the behaviour already exists, or the test asserts nothing. Find out which before writing a line of implementation |

The last row is the one worth stopping on. A test that passes before the code exists will pass
after it too, whatever you write.

### 2. Write the smallest change that makes it pass

Not the design you have in mind. The smallest thing that turns this test green. If that feels
insultingly small, that is the step working: the design pressure arrives in step 3, where the
tests are there to catch you.

Run the test. It passes. Run the related tests too, which is what the practice rules mean by
running only the related tests during development.

### 3. Tidy, with the tests still green

Now improve it. Rename, extract, collapse the duplication you just created. Run the tests after
each change. Green the whole way.

If a tidy turns something red, the tidy was a behaviour change wearing a refactor's clothes. Undo
it and decide whether you meant it.

### 4. Repeat, and run the suite at the end

One behaviour at a time. The full suite runs at the end of the phase, not after every green, which
is the practice rules' distinction between the related tests and the whole thing.

## The two ways this becomes worthless

**Writing the test after the code.** The test then describes what the code does rather than what
it should do, including its bugs. Nothing downstream can tell the difference: it is green either
way, and it will stay green through the exact regression it was supposed to catch.

**Never watching it fail.** A test that was never seen red might be asserting nothing at all: a
wrong path, a mock that swallows the call, an assertion on a value that is always true. It reports
success forever and costs the same to run as a real one.

Both produce a suite that is large, green, and evidence of nothing.

## Where the loop does not apply

The rule says *where the behaviour or bug can be captured*, and that qualifier is doing real work.

- **A bug with no reproduction is not ready for this loop.** `/sdd:bug assess` exists to get one
  first, and it refuses to proceed without it for the same reason.
- **Prose, configuration and documentation** have no failing test to write. They have checkers,
  which this repository uses instead; a pinned phrase is the same idea in a different medium.
- **A spike whose output is an answer** does not need a test, because the code is being thrown
  away. Say it is a spike rather than quietly skipping the loop.

Where it does not apply, say which of these it is. "Hard to test" is not on the list, and is
usually a statement about the design rather than about testing.

---

The loop follows `superpowers:test-driven-development` (MIT, Copyright (c) 2025 Jesse Vincent).
This is a reimplementation, not a copy. It differs in being written to sit beside a verification
gate that enforces the same idea mechanically: the table of expected failures and the link to
`/sdd:analyze` reporting commands that cannot fail are this suite's own, because here a test that
could never fail is a defect a hook will eventually be asked to judge.
