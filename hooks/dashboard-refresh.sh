#!/usr/bin/env bash
# PostToolUse hook: regenerate the project dashboard after a git commit.
#
# The commit list on the dashboard is the part the owner checks first, and a hand-maintained one
# went stale within a day. Tying regeneration to the commit itself, rather than to the agent
# remembering, is what keeps it current.
#
# Hard rules, because this runs after every Bash call in every session:
#   - Never change, delay or fail the tool call. Always exit 0, print nothing.
#   - Decide "not a commit" without spawning anything.
#   - Do nothing at all in a project with no dashboard report.
#
# Matches commits to the spec repo too (`git -C .specs commit`), since those move plan progress.
# A false positive costs one regeneration, which is harmless; a false negative leaves the page
# stale, so the match leans wide.
#
# Needs bash, jq and python3. Without either tool it does nothing.
set -uo pipefail

input=$(cat)

case "$input" in *commit*) ;; *) exit 0 ;; esac

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

cmd=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || exit 0
printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_-])git([[:space:]]+[^;&|]*)?[[:space:]]commit([[:space:]]|$)' || exit 0

cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

here=$(cd "$(dirname "$0")" && pwd)
python3 "$here/../scripts/sdd-report" --project "$cwd" --if-exists --quiet >/dev/null 2>&1 </dev/null
exit 0
