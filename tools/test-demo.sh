#!/usr/bin/env bash
# Assert the demo: that `sdd-demo` materialises the shape it claims, and that the two copies of
# the demo carried in the plugin cannot silently disagree.
#
# The drift assertion is the reason this file exists. The plugin carries the demo twice, as
# browsable directories and as git bundles, and `sdd-demo` uses only the bundles. Editing a
# directory therefore changes what a reader sees on the forge and nothing about what the command
# produces, with no error anywhere. That is the cost of carrying both, and case D is what pays it.
#
# Everything runs in a mktemp -d. Nothing here touches a real project or the network: the whole
# point of shipping bundles is that materialising the demo needs neither.
#
# Needs bash, git, python3 (for the demo's own test suite) and diff.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/plugin-root.sh
. "$here/plugin-root.sh"
repo=$(cd "$here/.." && pwd)
demo="$SDD_PLUGIN/demo"
sdd_demo="$SDD_PLUGIN/scripts/sdd-demo"

[ -x "$sdd_demo" ] || { echo "FAIL: $sdd_demo is not executable"; exit 1; }

lab=$(mktemp -d)
trap 'rm -rf "$lab"' EXIT
pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
chk() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$2', got '$1')"; fi; }

echo "sdd-demo"

# --- A. it materialises the shape ------------------------------------------
t="$lab/demo"
out=$("$sdd_demo" "$t" 2>&1); rc=$?
chk "$rc" 0 "exit 0 on a fresh target"

if [ -e "$t/.git" ]; then ok "the code repository exists"; else bad "the code repository exists"; fi
if [ -e "$t/.specs/.git" ]; then ok ".specs is a separate git repository"
else bad ".specs is a separate git repository"; fi

code_commits=$(git -C "$t" rev-list --count HEAD 2>/dev/null)
spec_commits=$(git -C "$t/.specs" rev-list --count HEAD 2>/dev/null)
# Counted from the bundle itself rather than from a literal, so adding a commit to the demo does
# not fail this for the wrong reason. What must hold is that the whole history survived the round
# trip: a clone that silently truncated would still look like a working demo.
ref="$lab/ref"
git clone -q "$demo/beacon.bundle" "$ref" 2>/dev/null
chk "$code_commits" "$(git -C "$ref" rev-list --count HEAD 2>/dev/null)" "the code history is complete"
refs="$lab/refs"
git clone -q "$demo/beacon-specs.bundle" "$refs" 2>/dev/null
chk "$spec_commits" "$(git -C "$refs" rev-list --count HEAD 2>/dev/null)" "the spec history is complete"
if [ "${code_commits:-0}" -gt 10 ]; then ok "the code history is real, not collapsed ($code_commits commits)"
else bad "the code history is real, not collapsed (got ${code_commits:-0})"; fi
if [ "${spec_commits:-0}" -gt 1 ]; then ok "the spec history is real, not collapsed ($spec_commits commits)"
else bad "the spec history is real, not collapsed (got ${spec_commits:-0})"; fi

# The single most important property: the outer repository ignores the inner one, and does so by
# its own committed .gitignore, so it holds on a machine with no global ignore configured at all.
if git -C "$t" check-ignore -q .specs 2>/dev/null; then ok "the code repo ignores .specs"
else bad "the code repo ignores .specs"; fi
src=$(git -C "$t" check-ignore -v .specs 2>/dev/null | cut -d: -f1)
case "$src" in
  *.gitignore) ok "and does so by its own committed .gitignore, not the machine's" ;;
  *) bad "and does so by its own committed .gitignore, not the machine's (matched $src)" ;;
esac

chk "$(git -C "$t" status --short)" "" "the materialised code repo is clean"
chk "$(git -C "$t/.specs" status --short)" "" "the materialised spec repo is clean"

# A clone from a bundle keeps an origin pointing at the bundle file. Left in place it breaks the
# first fetch, and there is nowhere a teaching artifact should be pushed anyway.
chk "$(git -C "$t" remote)" "" "no origin in the code repo"
chk "$(git -C "$t/.specs" remote)" "" "no origin in the spec repo"

# --- B. the Task Workflow keys resolve --------------------------------------
# Without these the pipeline resolves nothing, which is exactly the state the demo was found in:
# CLAUDE.md was on the author's disk and excluded by a global ignore, so no clone ever had it.
cm="$t/CLAUDE.md"
if [ -s "$cm" ]; then ok "CLAUDE.md is present in the clone"; else bad "CLAUDE.md is present in the clone"; fi
if grep -q '^## Task Workflow' "$cm" 2>/dev/null; then ok "it carries a Task Workflow section"
else bad "it carries a Task Workflow section"; fi

prd=$(grep -oE '`\.specs/docs/PRD\.md`' "$cm" 2>/dev/null | head -1 | tr -d '`')
if [ -n "$prd" ] && [ -s "$t/$prd" ]; then ok "the PRD key resolves to a real file"
else bad "the PRD key resolves to a real file"; fi
if [ -d "$t/.specs/docs/specs" ] && [ -n "$(ls -A "$t/.specs/docs/specs" 2>/dev/null)" ]; then
  ok "the phase specs directory resolves and is not empty"
else bad "the phase specs directory resolves and is not empty"; fi
if [ -d "$t/.specs/docs/tasks/phase-1" ]; then ok "the task directory pattern resolves"
else bad "the task directory pattern resolves"; fi

# --- C. the verification command actually works -----------------------------
# Every task file in the demo names ./run-tests. A demo whose verification command does not run is
# a demo of the one thing this suite refuses to let you claim.
if [ -x "$t/run-tests" ]; then
  rt=$("$t/run-tests" 2>&1); rrc=$?
  chk "$rrc" 0 "./run-tests passes"
  if printf '%s' "$rt" | grep -q 'Ran 36 tests'; then ok "and runs 36 tests"
  else bad "and runs 36 tests ($(printf '%s' "$rt" | grep -E '^Ran' || echo 'no count'))"; fi
else
  bad "./run-tests is executable"
fi

# --- D. the committed directories match the bundles -------------------------
# The assertion this file exists for. Prove it can fail, below, or it is decoration.
compare() {
  local bundle="$1" dir="$2" label="$3" work
  work="$lab/cmp-$label"
  if ! git clone -q "$bundle" "$work" 2>/dev/null; then
    bad "$label: could not clone the bundle"; return
  fi
  rm -rf "$work/.git"
  if diff -r -q "$work" "$dir" >"$lab/diff-$label" 2>&1; then
    ok "$label: the committed directory matches the bundle"
  else
    bad "$label: the committed directory and the bundle disagree"
    sed 's/^/          /' "$lab/diff-$label" | head -5
  fi
}
compare "$demo/beacon.bundle" "$demo/beacon" code
compare "$demo/beacon-specs.bundle" "$demo/beacon-specs" specs

# The drift check must be able to see drift. A copy of the committed tree with one edited file
# stands in for the real failure, which is someone editing the directory and not the bundle.
dirty="$lab/dirty"
cp -r "$demo/beacon" "$dirty"
printf '\ndrift\n' >> "$dirty/README.md"
w2="$lab/cmp-proof"
git clone -q "$demo/beacon.bundle" "$w2" 2>/dev/null && rm -rf "$w2/.git"
if diff -r -q "$w2" "$dirty" >/dev/null 2>&1; then
  bad "the drift check can detect an edited directory"
else
  ok "the drift check can detect an edited directory"
fi

# --- E. it refuses a target it should not write -----------------------------
occupied="$lab/occupied"; mkdir -p "$occupied"; printf 'mine\n' > "$occupied/a"
out=$("$sdd_demo" "$occupied" 2>&1); rc=$?
chk "$rc" 1 "refuses a non-empty directory"
if printf '%s' "$out" | grep -q 'not empty'; then ok "and says why"; else bad "and says why"; fi

out=$("$sdd_demo" "$t" 2>&1); rc=$?
chk "$rc" 1 "refuses a directory already holding a repository"
if printf '%s' "$out" | grep -q 'git repository'; then ok "and names that as the reason"
else bad "and names that as the reason"; fi

out=$("$sdd_demo" 2>&1); rc=$?
chk "$rc" 2 "exit 2 with no argument"

# --- F. no network, and nothing outside the plugin --------------------------
# Asserted structurally: the only inputs are two files inside the plugin.
for b in beacon.bundle beacon-specs.bundle; do
  if [ -r "$demo/$b" ]; then ok "$b ships inside the plugin"; else bad "$b ships inside the plugin"; fi
done
if grep -qE 'curl|wget|https?://' "$sdd_demo"; then
  bad "sdd-demo reaches nothing over the network"
else
  ok "sdd-demo reaches nothing over the network"
fi

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
