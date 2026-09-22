#!/usr/bin/env bash
# Assert sdd-snapshot against a fabricated HOME and a fabricated project.
#
# The assertions that matter are the negative ones. This script reads a lot of places that may not
# exist, and its whole claim is that a missing source becomes a stated gap rather than a silent
# omission or a crash. A snapshot that drops a section quietly reads as complete when it is not,
# which is the failure it was written to prevent, so it is the failure most worth testing.
#
# HOME is redirected for every case, so no run reads the developer's real transcripts or config.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/plugin-root.sh
. "$here/plugin-root.sh"
snap="$SDD_PLUGIN/scripts/sdd-snapshot"
[ -x "$snap" ] || { echo "FAIL: $snap is not executable"; exit 1; }

lab=$(mktemp -d); trap 'rm -rf "$lab"' EXIT
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); return 0; }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); return 0; }
chk() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$2', got '$1')"; fi; }
has() { if printf '%s' "$1" | grep -q -- "$2"; then ok "$3"; else bad "$3 (no match for '$2')"; fi; }
hasnt(){ if printf '%s' "$1" | grep -q -- "$2"; then bad "$3 (unexpected '$2')"; else ok "$3"; fi; }

# A home with transcripts and tool counts, and a bin/ for stubbing the claude CLI.
mkhome() {
  h="$lab/$1"; mkdir -p "$h/bin" "$h/.claude/projects/proj-a" "$h/.claude/projects/proj-b"
  head -c 200000 /dev/zero > "$h/.claude/projects/proj-a/one.jsonl"
  head -c 100000 /dev/zero > "$h/.claude/projects/proj-b/two.jsonl"
  printf '{"projects":{"x":{"toolUsage":{"Task":{"usageCount":7},"Read":{"usageCount":70}}}}}\n' \
    > "$h/.claude.json"
  printf '%s' "$h"
}
run() { local h="$1"; shift; ( cd "${2:-$lab}" >/dev/null 2>&1 || true
        HOME="$h" PATH="$h/bin:$PATH" "$snap" "$1" 2>&1 ); }

echo "sdd-snapshot"

# --- A. a bare home still produces a report ---------------------------------
h=$(mkhome a)
out=$(HOME="$h" PATH="$h/bin:$PATH" "$snap" --print 2>&1); rc=$?
chk "$rc" 0 "exit 0 with nothing installed"
has "$out" "Practice snapshot" "still produces a report"
has "$out" "Task\` dispatches" "reads the tool counts from a fabricated config"
has "$out" "7 : 70" "reports the ratio it was given"
has "$out" "10.0%" "computes the percentage"

# --- B. every absent source is named, never skipped --------------------------
# Prepending a lab bin/ does not hide the real claude, which sits further down the inherited PATH,
# so the absent-CLI branch would never run. The only honest way to simulate a missing command is a
# PATH built without it. The jq control matters as much as the claude one: this script exits early
# without jq, and a carelessly built PATH would pass this assertion for entirely the wrong reason.
cdir=$(dirname "$(command -v claude 2>/dev/null || echo /nonexistent/claude)")
noclaude=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$cdir" | paste -sd: -)
if PATH="$noclaude" command -v jq >/dev/null 2>&1 && ! PATH="$noclaude" command -v claude >/dev/null 2>&1; then
  ok "the no-claude PATH still has jq, so an absent section means what it says"
else
  bad "the no-claude PATH is not a valid control (jq missing, or claude still reachable)"
fi
nc=$(HOME="$h" PATH="$noclaude" "$snap" --print 2>&1)
has "$nc" "## Always-loaded context" "keeps the prefix heading with no claude CLI"
has "$nc" "Not measured" "says a source was not measured"
has "$nc" "not on PATH" "names the reason"

# --- C. transcripts are counted, not guessed ---------------------------------
has "$out" "| Transcripts | 2 |" "counts the transcripts it can see"
has "$out" "| Projects | 2 |" "counts the project directories"

# --- D. the three it cannot reach are listed every time -----------------------
# Silently omitting these is the failure mode this whole section exists to prevent.
has "$out" "Prompt-cache hit rate" "lists the cache rate as out of reach"
has "$out" "pass\^3" "lists pass^3 as out of reach"
has "$out" "Wall-clock" "lists the fan-out comparison as out of reach"
has "$out" "read as complete" "says why the omission is stated rather than silent"

# --- E. it never invents the numbers it cannot read ---------------------------
# A snapshot that filled these in from a stale file would be worse than one that refuses.
hasnt "$out" "cache hit rate: [0-9]" "does not invent a cache hit rate"

# --- F. --print writes nothing, checked where it would actually write --------
# The first version of this looked for stray files only under the lab, and ran from the developer's
# own checkout. A --print that wrote anyway would have written into the REAL spec repo and this
# assertion would have passed. Found by breaking the flag deliberately and watching a file appear
# in a place the test was not looking. So the case now builds its own repo with a spec tree, runs
# from inside it, and asserts nothing appeared there.
proj="$lab/proj"; mkdir -p "$proj/.specs/docs"
git -C "$proj" init -q 2>/dev/null
git -C "$proj" -c user.name=lab -c user.email=lab@example.com commit -q --allow-empty -m init 2>/dev/null
( cd "$proj" && HOME="$h" PATH="$h/bin:$PATH" "$snap" --print >/dev/null 2>&1 )
stray=$(find "$proj" -name 'practice-snapshot-*.md' 2>/dev/null | wc -l | tr -d ' ')
chk "$stray" "0" "--print writes no file, even where it would have written one"

# And the converse, so the location itself is asserted rather than assumed.
( cd "$proj" && HOME="$h" PATH="$h/bin:$PATH" "$snap" >/dev/null 2>&1 )
landed=$(find "$proj/.specs/docs/analysis" -name 'practice-snapshot-*.md' 2>/dev/null | wc -l | tr -d ' ')
chk "$landed" "1" "without --print it lands in the spec repo's analysis directory"

# --- G. --out writes exactly one dated file ----------------------------------
o="$lab/out"
HOME="$h" PATH="$h/bin:$PATH" "$snap" "--out=$o" >/dev/null 2>&1
n=$(find "$o" -name 'practice-snapshot-*.md' 2>/dev/null | wc -l | tr -d ' ')
chk "$n" "1" "--out writes one dated file"
f=$(find "$o" -name 'practice-snapshot-*.md' | head -1)
has "$(cat "$f")" "Practice snapshot" "the written file holds the report"

# A second run the same day replaces rather than accumulating, so a day's directory does not fill
# up with near-identical files nobody compares.
HOME="$h" PATH="$h/bin:$PATH" "$snap" "--out=$o" >/dev/null 2>&1
n=$(find "$o" -name 'practice-snapshot-*.md' | wc -l | tr -d ' ')
chk "$n" "1" "a second run the same day does not accumulate files"

# --- H. the prefix section reads a stubbed CLI --------------------------------
cat > "$h/bin/claude" <<'STUB'
#!/bin/sh
case "$*" in
  *"plugin list"*) printf '[{"id":"alpha@m","enabled":true},{"id":"beta@m","enabled":false}]\n' ;;
  *"plugin details alpha"*) printf '  Always-on:   ~1,234 tok   added to every session\n' ;;
  *) printf '\n' ;;
esac
STUB
chmod +x "$h/bin/claude"
out=$(HOME="$h" PATH="$h/bin:$PATH" "$snap" --print 2>&1)
has "$out" "alpha" "reports an enabled plugin's prefix cost"
hasnt "$out" "| \`beta\`" "skips a disabled plugin"
has "$out" "1234" "strips the thousands separator so the total can be summed"
has "$out" "total" "totals the prefix"

# --- I. a malformed CLI response is reported, not turned into a zero ----------
# Reporting 0 tokens because a format changed would be a confident wrong number, which is worse
# than an admitted gap.
cat > "$h/bin/claude" <<'STUB'
#!/bin/sh
case "$*" in
  *"plugin list"*) printf '[{"id":"alpha@m","enabled":true}]\n' ;;
  *) printf 'something else entirely\n' ;;
esac
STUB
out=$(HOME="$h" PATH="$h/bin:$PATH" "$snap" --print 2>&1)
has "$out" "no token line\|Format may have changed" "an unparseable CLI response is reported"
hasnt "$out" "| \*\*total\*\* | \*\*0\*\* |" "does not report a total of zero"

# --- J. outside a git repo it says so and still reports ----------------------
out=$(cd "$lab" && HOME="$h" PATH="$h/bin:$PATH" "$snap" --print 2>&1)
has "$out" "## Spec drift" "keeps the drift heading outside a repository"
has "$out" "Not measured\|Not applicable" "explains why drift was not measured"

# --- K. a bad argument is refused rather than ignored ------------------------
out=$(HOME="$h" "$snap" --nonsense 2>&1); rc=$?
chk "$rc" "2" "an unknown flag exits 2"
has "$out" "unexpected argument" "and says which"

echo "learnings captured"

# A count of captures, because a marker nobody reaches for looks exactly like a workflow with
# nothing to learn. Pointed at a lab state dir, or this reads the developer's own.
ldir="$lab/lstate/sdd"; mkdir -p "$ldir"
printf '%s\n' \
  '{"date":"2026-09-15","project":"alpha","session":"aaaa1111","text":"one"}' \
  '{"date":"2026-09-16","project":"alpha","session":"bbbb2222","text":"two"}' \
  '{"date":"2026-09-16","project":"beta","session":"cccc3333","text":"three"}' \
  > "$ldir/learnings.jsonl"

out=$(cd "$lab" && XDG_STATE_HOME="$lab/lstate" "$snap" --print 2>&1)
has "$out" "## Learnings captured" "the snapshot reports captured learnings"
has "$out" "3\*\* entries" "it counts every entry"
has "$out" 'alpha. | 2 |' "it breaks the count down by project"
has "$out" 'beta. | 1 |' "and lists every project that contributed"

out=$(cd "$lab" && XDG_STATE_HOME="$lab/empty-state" "$snap" --print 2>&1)
has "$out" "nothing has been captured" "it says so plainly when there is no stream at all"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
