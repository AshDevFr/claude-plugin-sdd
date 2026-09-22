#!/usr/bin/env bash
# UserPromptSubmit hook: append a marked line to the spec repo's learnings log.
#
# The improver loop needs raw material, and a hook cannot tell a correction from an
# ordinary request. Capturing everything produces a file nobody reads; judging it at
# capture time is the hard problem moved rather than solved. So capture is explicit: a
# line beginning with the marker is kept, and nothing else is.
#
# The cost of that choice is that it only works when remembered. The mitigation is that
# the marker is two characters longer than nothing and the entry needs no formatting.
#
# Two destinations, for two different readers.
#
# The per-project log under .specs/docs/learnings.md is for whoever works on that project. It
# needs a spec repo, because writing into the main repo is forbidden.
#
# The central stream under $XDG_STATE_HOME/sdd/learnings.jsonl is for the improver, which edits
# skills and commands in the plugin marketplace and so can never see a note captured in someone
# else's spec repo. That is why the log had six entries, all from one day: every learning from
# every other project was landing somewhere the improver cannot read. The central file is written
# whether or not the project has a spec repo, since a project without one otherwise has nowhere
# durable at all.
#
# It sits outside every repository, so nothing reviews it and no diff shows it growing. That was
# a deliberate decision by the owner rather than an oversight; CLAUDE.md's threat model names it.
# What it holds is the marked line and nothing else: not the prompt it came from, not the rest of
# the turn.
#
# Needs bash, git and jq.
set -uo pipefail

MARKER='TIL:'

input=$(cat)
prompt=$(jq -r '.prompt // empty' <<<"$input")
[ -n "$prompt" ] || exit 0

# Only lines that begin with the marker, leading whitespace allowed.
lines=$(printf '%s\n' "$prompt" | grep -E "^[[:space:]]*${MARKER}" || true)
[ -n "$lines" ] || exit 0

cwd=$(jq -r '.cwd // empty' <<<"$input"); [ -n "$cwd" ] || exit 0
sid=$(jq -r '.session_id // "unknown"' <<<"$input")
stamp=$(date +%Y-%m-%d)

# The project name, from the repo root where there is one, otherwise from the directory. A
# learning is worth keeping even when it happens somewhere that is not a git repository.
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
project=$(basename "${root:-$cwd}")

# The central stream first, because it is the one that works everywhere.
central="${XDG_STATE_HOME:-$HOME/.local/state}/sdd/learnings.jsonl"
if mkdir -p "$(dirname "$central")" 2>/dev/null; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    jq -cn --arg d "$stamp" --arg p "$project" --arg s "${sid:0:8}" --arg t "$line" \
      '{date: $d, project: $p, session: $s, text: $t}' >> "$central" 2>/dev/null || true
  done < <(printf '%s\n' "$lines" | sed -E "s/^[[:space:]]*${MARKER}[[:space:]]*//")
fi

[ -n "$root" ] || exit 0
[ -e "$root/.specs/.git" ] || exit 0

log="$root/.specs/docs/learnings.md"
if [ ! -f "$log" ]; then
  mkdir -p "$(dirname "$log")"
  {
    echo "# Learnings"
    echo
    echo "Raw material for the improver. Each entry is a line you marked with \`$MARKER\`,"
    echo "captured verbatim with the session and directory it came from. Newest last."
    echo
    echo "Nothing here is acted on automatically. The improver reads this file, proposes one"
    echo "edit to one skill, and that proposal is gated on the eval suite."
  } > "$log"
fi

{
  echo
  echo "## $stamp"
  printf '%s\n' "$lines" | sed -E "s/^[[:space:]]*${MARKER}[[:space:]]*//" | sed 's/^/- /'
  echo "  <sub>session \`${sid:0:8}\`, in \`$(basename "$root")\`</sub>"
} >> "$log"

exit 0
