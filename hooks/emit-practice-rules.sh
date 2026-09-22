#!/usr/bin/env bash
# SessionStart hook: deliver the practice rules as session context.
#
# A plugin cannot carry a CLAUDE.md, so standing rules reach a session only by being
# emitted here. Whatever is emitted is paid for on every message of every session, so
# the spec-repo rules, which are the bulk of the text and apply only where a nested
# spec repo exists, are emitted conditionally. On a project without one they are pure
# tax.
#
# Deliberately does NOT read stdin. An earlier version parsed the hook's JSON for a
# cwd, which hangs forever when stdin is an open pipe with no data: a hook that can
# hang is worse than one that is slightly less precise about its working directory.
# The process runs in the session's directory, so $PWD is the same answer without the
# hazard, and it keeps the dependency budget at bash, git and jq.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
universal="$here/practice-rules.md"
specrepo="$here/spec-repo-rules.md"

parts=()
[ -r "$universal" ] && parts+=("$universal")

# Same detection the Stop hook uses: the nested repo's .git, which resolves through a
# symlink and is true for a worktree's pointer file.
if root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null); then
  [ -e "$root/.specs/.git" ] && [ -r "$specrepo" ] && parts+=("$specrepo")
fi

[ ${#parts[@]} -gt 0 ] || exit 0

# @PLUGIN_ROOT@ is substituted here rather than left for the reader. A literal
# ${CLAUDE_PLUGIN_ROOT} is expanded in hooks.json but not in text a model reads, so a rules
# file carrying one would show the variable instead of a usable path.
plugin_root=$(cd "$here/.." && pwd)
jq -n --rawfile ctx <(cat "${parts[@]}" | sed "s|@PLUGIN_ROOT@|$plugin_root|g") \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
