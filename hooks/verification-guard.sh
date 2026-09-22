#!/usr/bin/env bash
# Stop hook: refuse to end a turn when a task file became Complete this session and its
# Verification command did not actually run.
#
# A Status field is otherwise a claim. Acceptance Criteria and a Testing Strategy are prose;
# nothing makes them runnable and nothing checks them.
#
# Three things this gets right that the first version did not, each measured rather than assumed:
#
#   1. WHAT COUNTS AS AN EDIT. The first version looked for Edit/Write/MultiEdit/NotebookEdit
#      tool calls naming a task file. `sed -i` and `printf >` flip a status without any of them,
#      and a subagent's edits are not in this transcript at all. Scope now comes from the spec
#      repo: a task that is Complete now and was not Complete at the last commit before this
#      session started is in scope, whatever wrote it. A task completed in an earlier session and
#      untouched since stays out, which is the property the old narrow scope existed for.
#
#   2. WHAT COUNTS AS HAVING RUN. The first version flattened every successful Bash command into
#      one string and asked grep -F whether the Verification command appeared anywhere in it, so
#      `echo "run ./check.sh later"`, `./check.sh | tail -5` and `# ./check.sh` all passed. The
#      command must now be the leading command of a Bash call, optionally after one `cd <path> &&`,
#      with nothing after it but redirections. A pipe hands the exit status to another program;
#      `|| true`, `|| :` and `; true` discard it; `&&` chains a command whose status wins.
#      Ambiguity is refused rather than accepted: a false block costs one re-run, a false pass is
#      the whole defect.
#
#   3. WHERE THE COMMANDS ARE. Measured 2026-09-16: a subagent's Bash tool_use does not appear in
#      the parent transcript, only the Agent call and its final report. Subagent transcripts live
#      at <transcript_path minus .jsonl>/subagents/agent-*.jsonl. A task verified by a subagent
#      was previously indistinguishable from one never verified at all.
#
# On a repeated Stop it re-checks and blocks again while the violation stands, up to a cap, then
# says so visibly and gets out of the way. Exiting silently on stop_hook_active, as the first
# version did, made the gate a one-shot nudge: a second Stop always succeeded.
#
# Needs bash, git and jq.
set -uo pipefail

MAX_BLOCKS=3

input=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$input"); [ -n "$cwd" ] || exit 0
tp=$(jq -r '.transcript_path // empty' <<<"$input"); [ -n "$tp" ] || exit 0
[ -r "$tp" ] || exit 0
active=$(jq -r '.stop_hook_active // false' <<<"$input")
session=$(jq -r '.session_id // empty' <<<"$input")

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
specs="$root/.specs"
[ -e "$specs/.git" ] || exit 0
[ -d "$specs/docs/tasks" ] || exit 0

# ---- which tasks became Complete this session ------------------------------------------------
# The session's start, taken from the transcript's first timestamped line. Without one, fall back
# to the file's own mtime, which is later than the start but still excludes older history.
started=$(head -n 40 "$tp" | jq -rs '[ .[] | .timestamp? // empty ] | .[0] // empty' 2>/dev/null)
if [ -z "$started" ]; then
  started=$(date -u -r "$tp" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
fi

base=""
if [ -n "$started" ]; then
  base=$(git -C "$specs" rev-list -1 --before="$started" HEAD 2>/dev/null || true)
fi
[ -n "$base" ] || base=$(git -C "$specs" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)

COMPLETE_RX='^\*\*Status:\*\*[[:space:]]*(Complete|✅|🟢)'

# Two greps rather than one git call per file. This runs at the end of every turn, and the
# per-file loop it replaces cost 91 ms of a measured 248 ms on a tree of 38 task files, growing
# with the tree. `git grep` at a commit reads that commit's tree directly.
complete_now=$(grep -rlE "$COMPLETE_RX" "$specs/docs/tasks" 2>/dev/null | sed "s|^$specs/||" | sort)
[ -n "$complete_now" ] || exit 0

complete_before=""
if [ -n "$base" ]; then
  complete_before=$(git -C "$specs" grep -lE "$COMPLETE_RX" "$base" -- docs/tasks 2>/dev/null |
    sed "s|^$base:||" | sort)
fi

in_scope=()
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  in_scope+=("$specs/$rel")
done < <(comm -23 <(printf '%s\n' "$complete_now") <(printf '%s\n' "$complete_before"))

[ ${#in_scope[@]} -gt 0 ] || exit 0

# ---- every command that ran and succeeded, here and in any subagent ----------------------------
# One base64 record per command, because a command may contain newlines: a heredoc's body line
# read as a command of its own is indistinguishable from the command having been run.
collect() { # collect <transcript>
  local t=$1
  grep -a '"tool_use"\|"tool_result"' "$t" 2>/dev/null | jq -c . 2>/dev/null | jq -rs '
    ( [ .[] | (.message? // empty) | (.content? // empty) | arrays | .[]
        | select(type == "object" and .type == "tool_result" and (.is_error == true))
        | .tool_use_id // empty ] ) as $bad
    | [ .[] | (.message? // empty) | (.content? // empty) | arrays | .[]
        | select(type == "object" and .type == "tool_use" and .name == "Bash")
        | select((.id // "") as $i | ($bad | index($i)) == null)
        | .input.command // empty ] | .[] | @base64
  ' 2>/dev/null
}

commands=$(collect "$tp")
subdir="${tp%.jsonl}/subagents"
if [ -d "$subdir" ]; then
  while IFS= read -r sub; do
    commands+=$'\n'$(collect "$sub")
  done < <(find "$subdir" -maxdepth 1 -type f -name '*.jsonl' 2>/dev/null)
fi

# ---- did a command run as itself? --------------------------------------------------------------
ran_as_itself() { # ran_as_itself <verification-command> <bash-command>
  local cmd="$1" line="$2" rest
  line="${line#"${line%%[![:space:]]*}"}"
  if [[ "$line" =~ ^cd[[:space:]]+[^\&\|\;]+\&\&[[:space:]]*(.*)$ ]]; then
    line="${BASH_REMATCH[1]}"
    line="${line#"${line%%[![:space:]]*}"}"
  fi
  [ "${line:0:${#cmd}}" = "$cmd" ] || return 1
  rest="${line:${#cmd}}"
  [[ "$rest" =~ ^([[:space:]]*(2\>\&1|1\>\&2|\>\>?[[:space:]]*[^[:space:]\|\&\;]+|2\>[[:space:]]*[^[:space:]\|\&\;]+))*[[:space:]]*$ ]]
}

verified() { # verified <command>
  local cmd=$1 enc
  while IFS= read -r enc; do
    [ -n "$enc" ] || continue
    ran_as_itself "$cmd" "$(printf '%s' "$enc" | base64 -d 2>/dev/null)" && return 0
  done <<< "$commands"
  return 1
}

missing=""
for f in "${in_scope[@]}"; do
  cmd=$(sed -n 's/^\*\*Verification:\*\*[[:space:]]*`\(.*\)`[[:space:]]*$/\1/p' "$f" | head -1)
  name=$(basename "$f")
  if [ -z "$cmd" ]; then
    missing="$missing
  $name: marked Complete with no Verification command"
    continue
  fi
  case "$cmd" in \[*\]*) missing="$missing
  $name: Verification is still the template placeholder"; continue ;; esac
  verified "$cmd" || missing="$missing
  $name: Complete, but \`$cmd\` did not run as its own command this session"
done

[ -n "$missing" ] || exit 0

# ---- repeated stops: block again, then give up visibly ------------------------------------------
# Keyed by session and by the violation itself, so a session that fixes one task and breaks another
# gets a fresh allowance rather than inheriting the previous one's count.
if [ "$active" = "true" ]; then
  key=$(printf '%s' "$session$missing" | cksum | tr -d ' ')
  state="${TMPDIR:-/tmp}/sdd-vguard-${session:-nosession}.$key"
  n=$(cat "$state" 2>/dev/null || echo 0)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n+1))
  printf '%s' "$n" > "$state" 2>/dev/null
  if [ "$n" -ge "$MAX_BLOCKS" ]; then
    jq -n --arg m "$missing" '{
      systemMessage: ("The verification gate is giving up after repeated blocks. Still unverified:" + $m +
        "\n\nNothing is stopping the turn now. The Complete status is on record without its command having run.")
    }'
    exit 0
  fi
fi

jq -n --arg m "$missing" '{
  decision: "block",
  reason: ("A task was marked Complete without its verification running:\n" + $m +
    "\n\nRun the command on its own, with no pipe and no `|| true`: its exit status is the point. Or set Status back to In Progress. A Complete status is supposed to mean the command passed, not that it was mentioned.")
}'
