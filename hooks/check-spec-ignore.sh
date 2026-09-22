#!/usr/bin/env bash
# SessionStart hook: warn when a nested spec repo exists but git does not ignore it.
#
# The whole nested-spec-repo design assumes `.specs` is invisible to the code repo's git. That is
# normally true because a global ignore says so, which makes it ambient state nobody checks.
#
# Measured on a fresh machine: `core.excludesFile` unset, no ~/.gitignore_global and no
# ~/.config/git/ignore. Every project there showed `.specs/` as untracked, which means one
# `git add -A` in the main repo commits the entire spec repo into it. The spec repo is where the
# PRD, every phase spec and every task file live, so that is not an untidy commit, it is the
# planning history of a project landing in a repository that deliberately excludes it, plus
# whatever the spec repo's own history contains.
#
# The audience is the session, not the user. The model is what runs `git add -A`, so telling the
# model is what prevents the damage.
#
# Silent unless something is wrong, like the grant check beside it: a warning that fires everywhere
# is how a real warning gets ignored. The opt-in signal is the one the rest of the suite uses,
# `.specs/.git` existing.
#
# Deliberately does NOT read stdin: an earlier hook in this suite hung forever parsing JSON from an
# open pipe with no data. $PWD is the same answer without the hazard.
#
# Needs bash, git and jq.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -e "$root/.specs/.git" ] || exit 0

# `git check-ignore` consults core.excludesFile, .git/info/exclude and every .gitignore, so this
# answers "is it ignored by anything" rather than testing one mechanism. Which one is doing the
# ignoring does not matter; that something is, does.
git -C "$root" check-ignore -q .specs 2>/dev/null && exit 0

excludes=$(git config --get core.excludesfile 2>/dev/null || true)

jq -n --arg ex "${excludes:-<unset>}" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: (
  "# WARNING: `.specs` is NOT ignored by this repository\n\n" +
  "This project has a nested spec repo and git can see it. `git status` lists `.specs/` as " +
  "untracked, so **`git add -A` in the main repo will commit the whole spec repo into it**: the " +
  "PRD, every phase spec, every task file.\n\n" +
  "**Until it is fixed: never `git add -A` or `git add .` in the main repo.** Add paths explicitly. " +
  "The `-C .specs` commit policy is unaffected and still applies.\n\n" +
  "`core.excludesFile` is currently " + $ex + ". Fix it with:\n\n" +
  "```sh\necho .specs >> ~/.gitignore_global\ngit config --global core.excludesFile ~/.gitignore_global\n```\n\n" +
  "Then `git check-ignore -q .specs` in this repo exits 0 and this warning stops.\n"
)}}'
