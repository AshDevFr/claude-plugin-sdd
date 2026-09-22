#!/usr/bin/env bash
# Stop hook: refuse to end the turn while the nested .specs/ repo has
# uncommitted or unpushed work.
#
# The spec-repo commit policy asks the model to commit and push .specs/ in the
# same turn it edits it. This makes that structural rather than a paragraph the
# model has to remember. No-ops in every repo that has no .specs/.git, so it is
# safe to leave enabled globally.
# On a repeated Stop it re-checks and blocks again while the work is still uncommitted, up to a
# cap, then says so visibly and gets out of the way. Exiting silently on stop_hook_active made
# this a one-shot nudge: a second Stop always succeeded, whatever the turn did in between.
set -euo pipefail

MAX_BLOCKS=3

input=$(cat)
active=$(jq -r '.stop_hook_active // false' <<<"$input")
session=$(jq -r '.session_id // empty' <<<"$input")

cwd=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cwd" ] || exit 0
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

spec="$root/.specs"
[ -e "$spec/.git" ] || exit 0

dirty=$(git -C "$spec" status --porcelain 2>/dev/null || true)

# Unpushed only counts when a remote actually exists.
ahead=""
push_hint=""
if git -C "$spec" remote get-url origin >/dev/null 2>&1; then
  ahead=$(git -C "$spec" log --branches --not --remotes --oneline 2>/dev/null || true)
  push_hint=" && git -C .specs push"
fi

[ -z "$dirty$ahead" ] && exit 0

# Keyed by the outstanding work as well as the session, so a turn that commits one thing and
# leaves another gets a fresh allowance rather than inheriting a count already spent.
if [ "$active" = "true" ]; then
  key=$(printf '%s' "$session$dirty$ahead" | cksum | tr -d ' ')
  state="${TMPDIR:-/tmp}/sdd-specguard-${session:-nosession}.$key"
  n=$(cat "$state" 2>/dev/null || echo 0)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n+1))
  printf '%s' "$n" > "$state" 2>/dev/null
  if [ "$n" -ge "$MAX_BLOCKS" ]; then
    jq -n --arg dirty "${dirty:-(none)}" --arg ahead "${ahead:-(none)}" '{
      systemMessage: ("The spec-repo guard is giving up after repeated blocks. Still outstanding:\n" +
        "Uncommitted:\n" + $dirty + "\n\nUnpushed commits:\n" + $ahead +
        "\n\nNothing is stopping the turn now. The spec repo is being left in that state.")
    }'
    exit 0
  fi
fi

jq -n \
  --arg dirty "${dirty:-(none)}" \
  --arg ahead "${ahead:-(none)}" \
  --arg push "$push_hint" \
  '{
     decision: "block",
     reason: (
       "The .specs/ spec repo has uncommitted or unpushed work. Per the spec-repo commit policy, finish it before ending the turn:\n\n" +
       "  git -C .specs add -A && git -C .specs commit -m \"<concise description>\"" + $push + "\n\n" +
       "Use a real description of what changed. No Claude/Anthropic trailer or footer.\n\n" +
       "Uncommitted:\n" + $dirty + "\n\nUnpushed commits:\n" + $ahead
     )
   }'
