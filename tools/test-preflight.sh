#!/usr/bin/env bash
# Assert sdd-preflight against a throwaway HOME built from nothing.
#
# Every case runs with HOME and GIT_CONFIG_GLOBAL pointed into the lab, so a run can never read
# or write the developer's real global gitignore or git config. Verified before this suite was
# written: `GIT_CONFIG_GLOBAL=<lab> git config --global ...` leaves the real value untouched.
#
# PATH is prefixed with a lab bin/ so a case can stub a command the script consults, which is the
# only way to exercise the chezmoi-managed branch without chezmoi managing anything real.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/plugin-root.sh
. "$here/plugin-root.sh"
pf="$SDD_PLUGIN/scripts/sdd-preflight"
[ -x "$pf" ] || { echo "FAIL: $pf is not executable"; exit 1; }

lab=$(mktemp -d)
trap 'rm -rf "$lab"' EXIT
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); return 0; }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); return 0; }
chk() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$2', got '$1')"; fi; }
has() { if printf '%s' "$1" | grep -q -- "$2"; then ok "$3"; else bad "$3 (no match for '$2')"; fi; }
hasnt(){ if printf '%s' "$1" | grep -q -- "$2"; then bad "$3 (unexpected '$2')"; else ok "$3"; fi; }

newhome() { h="$lab/$1"; mkdir -p "$h/bin"; printf '%s' "$h"; }
# XDG_CONFIG_HOME is in the lab for a reason that is not hygiene: --fix now writes
# $XDG_CONFIG_HOME/git/ignore when nothing else is configured, so a case run without this override
# appends to the developer's real global ignore file. Verified by running one case without it.
# cwd matters now: the .specs check asks the repository you are standing in. Without pinning it,
# every case would inherit whatever repository the harness happened to be run from, and this one is
# a repository that ignores .specs, so every case would pass for the wrong reason.
run() { local h="$1"; shift; (cd "$h" && HOME="$h" XDG_CONFIG_HOME="$h/.config" GIT_CONFIG_GLOBAL="$h/.gitconfig" PATH="$h/bin:$PATH" "$pf" "$@" 2>&1); }
# Same, but standing inside a given repository.
runin() { local d="$1" h="$2"; shift 2; (cd "$d" && HOME="$h" XDG_CONFIG_HOME="$h/.config" GIT_CONFIG_GLOBAL="$h/.gitconfig" PATH="$h/bin:$PATH" "$pf" "$@" 2>&1); }
# A repository in the lab, with no rules of its own unless a case adds them.
mkrepo() { local d="$1"; mkdir -p "$d"; git -C "$d" init -q; printf '%s' "$d"; }
cfg() { HOME="$1" XDG_CONFIG_HOME="$1/.config" GIT_CONFIG_GLOBAL="$1/.gitconfig" git config --global core.excludesfile 2>/dev/null; }
xdgignore() { printf '%s' "$1/.config/git/ignore"; }
# A PATH holding everything the script needs except jq, so "jq is missing" can be asserted as
# absence rather than as a stub that fails. A stub is still found by `command -v`, which is what
# the script tests, so the earlier jq case could not express this.
minpath() {
  local h="$1" d="$1/minbin" c
  mkdir -p "$d"
  for c in sh git bash uname mktemp dirname mkdir grep sed cut cp cat printf tr rm; do
    [ -e "$d/$c" ] || ln -sf "$(command -v "$c" 2>/dev/null || true)" "$d/$c" 2>/dev/null || true
  done
  rm -f "$d/jq"
  printf '%s' "$d"
}

echo "sdd-preflight"

# --- A. inside a repo that ignores nothing: a required gap ------------------
# This is the case that matters, because it is the one where something is actually broken: a
# session in this repository will offer to commit the spec tree.
h=$(newhome a)
r=$(mkrepo "$h/proj")
out=$(runin "$r" "$h"); rc=$?
chk "$rc" 1 "in a repo with no rule: exit 1"
has "$out" "not ignored in this repo" "names the repo, not the machine"
has "$out" "--fix appends it to" "says where --fix would put it"
has "$out" "\.gitignore" "and that it is the repo's own .gitignore"
if [ -e "$h/.claude/CLAUDE.md" ] || [ -e "$(xdgignore "$h")" ] || [ -e "$r/.gitignore" ]; then
  bad "a check-only run writes nothing"; else ok "a check-only run writes nothing"; fi

# every gap in one pass, not one per run
cat > "$h/bin/jq" <<'STUB'
#!/bin/sh
exit 127
STUB
chmod +x "$h/bin/jq"
out=$(runin "$r" "$h")
has "$out" "CLAUDE.md" "still reports CLAUDE.md when jq is unusable"
rm -f "$h/bin/jq"

# --- A2. the project's own .gitignore is a complete answer ------------------
# The case this script was corrected for. A `.specs` line in the repository's own .gitignore needs
# no global configuration, and it travels to everyone who clones, which a global file does not.
h=$(newhome a2)
r=$(mkrepo "$h/proj")
printf '.specs\n' > "$r/.gitignore"
out=$(runin "$r" "$h"); rc=$?
chk "$rc" 0 "a project .gitignore with .specs: exit 0"
has "$out" "this repo ignores .specs" "reports it as satisfied"
has "$out" "\.gitignore" "and names the file that did it"
has "$out" "local to this repo" "and warns that a new project needs its own"

# --- A3. a global ignore is equally a complete answer -----------------------
h=$(newhome a3)
mkdir -p "$h/.config/git"; printf '.specs\n' > "$h/.config/git/ignore"
r=$(mkrepo "$h/proj")
out=$(runin "$r" "$h"); rc=$?
chk "$rc" 0 "a global XDG ignore with .specs: exit 0"
hasnt "$out" "local to this repo" "and does not warn about a new project, since one is covered"

h=$(newhome a4)
printf '.specs\n' > "$h/.gitignore"
HOME="$h" XDG_CONFIG_HOME="$h/.config" GIT_CONFIG_GLOBAL="$h/.gitconfig" \
  git config --global core.excludesfile "$h/.gitignore"
r=$(mkrepo "$h/proj")
out=$(runin "$r" "$h"); rc=$?
chk "$rc" 0 "a plain ~/.gitignore named by core.excludesfile: exit 0"

# --- A5. .git/info/exclude counts too ---------------------------------------
# Not a mechanism anyone should be told to use, but the check claims "by any mechanism" and that
# claim should be true rather than approximately true.
h=$(newhome a5)
r=$(mkrepo "$h/proj")
printf '.specs\n' >> "$r/.git/info/exclude"
out=$(runin "$r" "$h"); rc=$?
chk "$rc" 0 ".git/info/exclude also satisfies it"

# --- B. outside a repository it is advice, not a verdict --------------------
# There is no project to be broken, and per-project entries are a legitimate arrangement this
# command cannot see from here. Reporting a required gap would be asserting a failure it has not
# observed.
h=$(newhome b)
out=$(run "$h"); rc=$?
chk "$rc" 0 "outside a repo with no global ignore: exit 0"
has "$out" "each project needs its own entry" "says what the consequence is"
has "$out" "config/git/ignore" "offers the global option"
has "$out" "travels with it" "and the per-project option"

# --- B1. --fix inside a repo writes to that repo ----------------------------
h=$(newhome b1)
r=$(mkrepo "$h/proj")
out=$(runin "$r" "$h" --fix); rc=$?
chk "$rc" 0 "exit 0 after --fix in a repo"
if grep -qxF '.specs' "$r/.gitignore" 2>/dev/null; then ok "--fix writes .specs to the repo's .gitignore"
else bad "--fix writes .specs to the repo's .gitignore"; fi
if [ -e "$(xdgignore "$h")" ]; then bad "--fix in a repo writes nothing global"
else ok "--fix in a repo writes nothing global"; fi
chk "$(cfg "$h")" "" "--fix does not write core.excludesfile"

# --- B2. --fix outside a repo writes the global file ------------------------
h=$(newhome b2)
out=$(run "$h" --fix); rc=$?
chk "$rc" 0 "exit 0 after --fix outside a repo"
if grep -qxF '.specs' "$(xdgignore "$h")" 2>/dev/null; then ok "--fix writes .specs to the XDG ignore file"
else bad "--fix writes .specs to the XDG ignore file"; fi
chk "$(cfg "$h")" "" "and still does not write core.excludesfile"

# --- B3. --fix alone leaves the preferences alone ---------------------------
h=$(newhome b3)
r=$(mkrepo "$h/proj")
out=$(runin "$r" "$h" --fix)
for entry in 'CLAUDE.md' '.claude'; do
  if grep -qxF "$entry" "$r/.gitignore" 2>/dev/null || grep -qxF "$entry" "$(xdgignore "$h")" 2>/dev/null; then
    bad "--fix alone leaves $entry alone"
  else ok "--fix alone leaves $entry alone"; fi
done
if [ -e "$h/.claude/CLAUDE.md" ]; then bad "--fix alone writes no starter CLAUDE.md"
else ok "--fix alone writes no starter CLAUDE.md"; fi
has "$out" "advise" "still reports the preferences it declined to write"

# --- B4. --fix-recommended writes them, globally ----------------------------
# Globally even inside a repository: not committing a personal file by accident is a machine-wide
# habit, not a property of one project.
h=$(newhome b4)
r=$(mkrepo "$h/proj")
out=$(runin "$r" "$h" --fix-recommended); rc=$?
chk "$rc" 0 "exit 0 after --fix-recommended"
for entry in 'CLAUDE.md' '.claude'; do
  if grep -qxF "$entry" "$(xdgignore "$h")" 2>/dev/null; then ok "--fix-recommended ignores $entry globally"
  else bad "--fix-recommended ignores $entry globally"; fi
done
if [ -s "$h/.claude/CLAUDE.md" ]; then ok "--fix-recommended writes a starter CLAUDE.md"
else bad "--fix-recommended writes a starter CLAUDE.md"; fi

# --- B5. an existing core.excludesfile is where a global entry goes ---------
h=$(newhome b5)
printf '*.swp\n' > "$h/.gitignore"
HOME="$h" XDG_CONFIG_HOME="$h/.config" GIT_CONFIG_GLOBAL="$h/.gitconfig" \
  git config --global core.excludesfile "$h/.gitignore"
out=$(run "$h" --fix); rc=$?
chk "$rc" 0 "exit 0 with an existing excludesfile"
if grep -qxF '.specs' "$h/.gitignore" 2>/dev/null; then ok "appends to the configured excludesfile"
else bad "appends to the configured excludesfile"; fi
if grep -qxF '*.swp' "$h/.gitignore" 2>/dev/null; then ok "leaves the file's existing entries"
else bad "leaves the file's existing entries"; fi
chk "$(cfg "$h")" "$h/.gitignore" "leaves core.excludesfile pointing where it did"
if [ -e "$(xdgignore "$h")" ]; then bad "does not create a second ignore file"
else ok "does not create a second ignore file"; fi

# --- B6. the preferences are reported and never fatal -----------------------
h=$(newhome b6)
r=$(mkrepo "$h/proj")
printf '.specs\n' > "$r/.gitignore"
out=$(runin "$r" "$h"); rc=$?
chk "$rc" 0 "exit 0 with every recommendation outstanding"
has "$out" "CLAUDE.md is not ignored" "advises on CLAUDE.md"
has "$out" "\.claude is not ignored" "advises on .claude"
has "$out" "no ~/.claude/CLAUDE.md" "advises on the personal layer"
has "$out" "recommendations never affect the exit status" "says so in the summary"

# --- B7. jq absent is a required gap ----------------------------------------
h=$(newhome b7)
r=$(mkrepo "$h/proj"); printf '.specs\n' > "$r/.gitignore"
d=$(minpath "$h")
out=$( (cd "$r" && HOME="$h" XDG_CONFIG_HOME="$h/.config" GIT_CONFIG_GLOBAL="$h/.gitconfig" PATH="$d" "$pf" 2>&1) ); rc=$?
chk "$rc" 1 "exit 1 when jq is absent"
has "$out" "jq is missing" "names jq"

# --- C. idempotent ----------------------------------------------------------
h=$(newhome c)
r=$(mkrepo "$h/proj")
runin "$r" "$h" --fix-recommended >/dev/null
before=$(cat "$r/.gitignore")
beforeg=$(cat "$(xdgignore "$h")")
out=$(runin "$r" "$h" --fix-recommended)
has "$out" "0 fixed" "a second run reports nothing fixed"
chk "$(cat "$r/.gitignore")" "$before" "a second run leaves the repo's .gitignore byte-identical"
chk "$(cat "$(xdgignore "$h")")" "$beforeg" "and the global one too"

# --- D. an existing CLAUDE.md is diffed, never overwritten -------------------
h=$(newhome d); mkdir -p "$h/.claude"
printf '# mine\n\nMy own rules.\n' > "$h/.claude/CLAUDE.md"
out=$(run "$h" --fix)
if grep -q '^# mine' "$h/.claude/CLAUDE.md"; then ok "never overwrites an existing CLAUDE.md"; else bad "never overwrites an existing CLAUDE.md"; fi
has "$out" "differs from the starter" "reports that an existing CLAUDE.md differs"

# A heading is the same section whichever way the user capitalises it. Exact matching reported a
# real CLAUDE.md covering three of four starter sections as covering none.
h=$(newhome d2); mkdir -p "$h/.claude"
{ echo '# mine'; grep '^## ' "$SDD_PLUGIN/scripts/claude-md-starter.md" | tr '[:lower:]' '[:upper:]'; } > "$h/.claude/CLAUDE.md"
out=$(run "$h" --fix)
has "$out" "covers every starter section" "matches headings regardless of case"

# --- E. refuses to write a settings file another tool manages ---------------
h=$(newhome e); mkdir -p "$h/.claude"
cat > "$h/bin/chezmoi" <<STUB
#!/bin/sh
[ "\$1" = managed ] && printf '%s\n' "$h/.claude/settings.json"
exit 0
STUB
chmod +x "$h/bin/chezmoi"
out=$(run "$h" --fix --otel-endpoint http://collector.invalid:4318)
has "$out" "REFUSED" "refuses a chezmoi-managed settings.json"
hasnt "$out" "ADDED telemetry" "does not claim to have written it"

# --- F. writes telemetry when nothing else manages the file -----------------
h=$(newhome f)
out=$(run "$h" --fix --otel-endpoint http://collector.invalid:4318)
if command -v jq >/dev/null 2>&1; then
  if jq -e '.env.OTEL_EXPORTER_OTLP_ENDPOINT == "http://collector.invalid:4318"' \
       "$h/.claude/settings.json" >/dev/null 2>&1; then ok "writes the telemetry endpoint"; else bad "writes the telemetry endpoint"; fi
  if jq -e . "$h/.claude/settings.json" >/dev/null 2>&1; then ok "leaves valid JSON"; else bad "leaves valid JSON"; fi
else
  ok "skipped telemetry write (no jq on this machine)"
fi

# --- G. the contract and the checks cannot drift apart ----------------------
# D6's intent: one enumeration. The prose lives in contract(), the logic lives in the checks, and
# these assertions are what stop the two describing different machines.
ids=$(sed -n '/^contract() {/,/^}/p' "$pf" | grep -E '^[a-z-]+\|' | cut -d'|' -f1)
# Whole marker lines only. Markers are indented to match the block they sit in, so this cannot
# anchor at column 0; but it must still require `contract:` immediately after the `#`, or it also
# matches the header comment that explains the convention.
marks=$(grep -E '^[[:space:]]*# contract: ' "$pf" | sed -E 's/^[[:space:]]*# contract: //' | tr ' ' '\n' | grep -v '^$' | sort -u)

for id in $ids; do
  if printf '%s\n' "$marks" | grep -qx "$id"; then ok "contract id '$id' is implemented by a check"
  else bad "contract id '$id' is listed but no check claims it"; fi
done
for m in $marks; do
  if printf '%s\n' "$ids" | grep -qx "$m"; then :
  else bad "check marker '$m' names a prerequisite the contract does not list"; fi
done
ok "every check marker names a listed prerequisite"

listed=$("$pf" --list | grep -cE '^  [a-z-]+ ')
chk "$listed" "$(printf '%s\n' "$ids" | grep -c .)" "--list prints every contract entry"

# --- H. the guide quotes --list rather than restating it --------------------
# Ready before the guide exists: when 8.01 writes docs/guide.md with the markers, this starts
# asserting. A guide that hand-copies the contract is the drift D6 exists to prevent.
# Every copy, not the first one found. The plugin's own README is the document that travels with
# a published copy, and the marketplace README is the one read here; a stale block in either is
# the drift the marker exists to prevent, and checking only one hides the other.
found=0
for guide in "$here/../README.md" "$SDD_PLUGIN/README.md"; do
  [ -f "$guide" ] || continue
  grep -q "preflight:list" "$guide" || continue
  found=$((found+1))
  # Strip the marker lines and the code fence around them, leaving only the quoted output.
  quoted=$(sed -n '/<!-- preflight:list -->/,/<!-- \/preflight:list -->/p' "$guide" | sed '1d;$d' | grep -v '^```')
  if [ "$quoted" = "$("$pf" --list)" ]; then ok "${guide#"$here"/../}: quoted contract matches --list"
  else bad "${guide#"$here"/../}: quoted contract is stale: regenerate it from sdd-preflight --list"; fi
done
[ "$found" -eq 0 ] && ok "skipped guide check (no README carries a preflight:list block)"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
