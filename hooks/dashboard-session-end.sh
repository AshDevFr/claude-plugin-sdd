#!/usr/bin/env bash
# SessionEnd hook: stop the project dashboard when the session exits, unless it was started with
# --keep-running.
#
# A dashboard server is detached, so it outlives the terminal that started it. Left to itself it
# would keep a project readable on the LAN long after anyone remembered it, which is the more
# common mistake than an owner finding the page down. So the session ending stops it by default,
# and `sdd-dashboard stop --if-session-bound` returns at once for a server started to outlive it.
#
# /clear and resume also end a session as far as this event is concerned, while the person is
# plainly still working, so both are skipped. Stopping the page someone is reading because they
# cleared the context would be the worst possible moment. hooks.json already matches only the
# other reasons; the check here stays so the script is safe wired any other way.
#
# SessionEnd hooks share a 1.5-second budget unless a timeout raises it. Stopping takes well under
# that, and the timeout in hooks.json covers a slow git lookup on a large repository.
#
# Known limit: the server belongs to the project, not to a session. With two sessions open in the
# same project, whichever ends first stops it for both.
#
# Never fails and prints nothing. Needs bash, jq and python3; without either it does nothing.
set -uo pipefail

input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

reason=$(jq -r '.reason // empty' <<<"$input" 2>/dev/null)
case "$reason" in clear|resume) exit 0 ;; esac

cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

here=$(cd "$(dirname "$0")" && pwd)
python3 "$here/../scripts/sdd-dashboard" stop --if-session-bound --project "$cwd" >/dev/null 2>&1 </dev/null
exit 0
