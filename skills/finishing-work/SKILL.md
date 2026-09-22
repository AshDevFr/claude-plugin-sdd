---
name: finishing-work
description: What to do with a branch once the work on it is done: merge, propose, or throw it away, what must be true before any of them, and how to bring a spec-repo worktree branch back. Use when implementation is complete and tests pass, and when a sdd-worktree needs unwinding.
---

# Finishing Work

Work finishes and something has to happen to the branch. The failure here is quiet: branches and
worktrees accumulate, and spec-repo work is left on a branch nobody merges, so the planning record
diverges from the code it describes.

## Before any of the three

All of these must be true, and two of them are enforced by hooks that will stop the turn anyway:

- **The verification command ran and passed**, as its own command. The Stop hook refuses a Complete
  status otherwise, and this is the moment it fires.
- **The spec repo is committed and pushed.** `git -C .specs status` is clean and nothing is
  unpushed. The other Stop hook refuses otherwise.
- **Nothing is uncommitted in either repository.** Check both; the main one is easy to forget
  because this suite never commits there for you.
- **The full suite has run**, not just the related tests. The practice rules put the full run at
  the end of a phase, and this is the end.

If any of these is not true, that is the work, not the finishing.

## Three outcomes

### Merge

The work is yours to land and nothing needs review. Merge, then delete the branch. If the project
merges through a proposal by convention, this is not the option, however small the change.

### Propose

Open a pull or merge request. `/sdd:pr-msg` writes the title and description from the plan and the
diff; you open it. Leave the branch alone until it lands.

### Discard

**The one that gets left out, and often the right answer.** A spike that answered its question has
no reason to survive: keeping it costs review attention later and invites someone to build on code
that was never meant to be kept.

Discard deliberately rather than by neglect: delete the branch, and if the spike taught something
worth keeping, record that as a design in `.specs/docs/designs/` or a dated entry via `/sdd:quick`
before the branch goes. **The answer is the artifact, not the code.**

## The spec repo's half, which nothing else covers

`.specs` is a **second git repository**. A branch in the main repo does not carry spec work, and
`sdd-worktree --specs=worktree` deliberately puts the spec tree on its own branch. That branch has
to come back, and the script does not do it for you:

```sh
git -C .specs merge <branch>          # from the main checkout, when the work is done
git -C .specs worktree remove <path>  # then drop the spec worktree
```

Of the three worktree modes, only `worktree` creates something to bring back. `none` shares
nothing, and `link` shares the live tree, so there is no branch to merge in either.

**Check `git -C .specs status` after removing the worktree.** A spec worktree removed before its
branch is merged loses the planning record for the work you just finished, which is the one
artifact that cannot be reconstructed from the code.

## What this is not

- Not a merge strategy. Squash, rebase or merge commits are the project's own business.
- Not a release. Tagging and publishing are separate, and for a plugin here
  `claude plugin tag` has its own preconditions.

---

The three-outcome shape follows `superpowers:finishing-a-development-branch` (MIT, Copyright (c) 2025 Jesse Vincent).
This is a reimplementation, not a copy. The spec-repo half is this suite's own: no general version
has a second repository to bring back, and that is the part most likely to be forgotten.
