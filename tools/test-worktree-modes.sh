#!/usr/bin/env bash
# Assert each --specs mode of sdd-worktree against a scratch repo built from nothing.
#
# These are claims about git behaviour, and git changes underneath them, so they are
# rebuilt every run rather than fixed as a snapshot.
#
# The guard assertions drive the real Stop hook with the JSON it expects, the same way the
# hook suite does. Sharing the repo builders with that suite is deliberate: two sets would
# drift and then disagree about what a spec repo looks like.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/plugin-root.sh
. "$here/plugin-root.sh"
wt="$SDD_PLUGIN/bin/sdd-worktree"
guard="$SDD_PLUGIN/hooks/spec-repo-guard.sh"
[ -x "$wt" ] || { echo "FAIL: $wt is not executable"; exit 1; }

lab=$(mktemp -d)
trap 'rm -rf "$lab"' EXIT
. "$here/lib-lab.sh"
pass=0; fail=0

ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }
chk() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$2', got '$1')"; fi; }

# blocks <cwd> -> "block" or "silent", by driving the real Stop hook
blocks() {
  local out
  out=$(printf '{"cwd":"%s","stop_hook_active":false}' "$1" | "$guard" 2>/dev/null)
  if [ -n "$out" ] && printf '%s' "$out" | grep -q '"block"'; then echo block; else echo silent; fi
}

echo "sdd-worktree: --specs=none"
r=$(mkrepo none-mode); mkspecs "$r" noremote clean
( cd "$r" && "$wt" feature-a "$lab/wt-none" >/dev/null 2>&1 ) || bad "none: the command failed"
chk "$([ -d "$lab/wt-none" ] && echo yes || echo no)" yes "the worktree is created"
chk "$([ -e "$lab/wt-none/.specs" ] && echo yes || echo no)" no "no .specs in the worktree"
chk "$(blocks "$lab/wt-none")" silent "the guard does not block there"

echo
echo "sdd-worktree: --specs=link"
r=$(mkrepo link-mode); mkspecs "$r" noremote clean
out=$( cd "$r" && "$wt" feature-b "$lab/wt-link" --specs=link 2>&1 ) || bad "link: the command failed"
# An agent is refused on the symlink TARGET, because the permission check resolves the link
# before testing it against the session's working directory. Measured in use: the shell reads
# the file fine and only the agent is blocked, so every filesystem assertion here passes while
# the mode fails at the one thing it is for. The hint is the only thing that makes it usable.
case "$out" in
  *--add-dir*) ok "link mode tells the caller it needs --add-dir to be readable by an agent" ;;
  *) bad "link mode created a tree an agent cannot read and said nothing about --add-dir" ;;
esac
chk "$([ -L "$lab/wt-link/.specs" ] && echo yes || echo no)" yes ".specs is a symlink"
chk "$([ -e "$lab/wt-link/.specs/.git" ] && echo yes || echo no)" yes "it resolves to a spec repo, which is what the guard tests"
case "$(readlink "$lab/wt-link/.specs")" in
  /*) ok "the link target is absolute, so it resolves from any directory" ;;
  *)  bad "the link target is relative" ;;
esac
chk "$(cat "$lab/wt-link/.specs/note.md" 2>/dev/null)" spec "the spec tree is readable through the link"
echo "through-the-link write" > "$lab/wt-link/.specs/via-link.md"
chk "$([ -f "$r/.specs/via-link.md" ] && echo yes || echo no)" yes "a write through the link lands in the main repo's spec tree"
chk "$(blocks "$lab/wt-link")" block "the guard fires on that uncommitted write"
# Invisibility rests on the real global ignore, not on anything in the scratch repo.
st=$(git -C "$lab/wt-link" status --porcelain 2>/dev/null | grep -c '\.specs' || true)
if [ "$st" = "0" ]; then
  ok "the code repo's git does not see .specs (via the real global ignore)"
else
  bad "the code repo's git sees .specs; the global ignore is not covering it here"
fi

echo
echo "sdd-worktree: --specs=worktree"
r=$(mkrepo wt-mode); mkspecs "$r" noremote clean
( cd "$r" && "$wt" feature-c "$lab/wt-tree" --specs=worktree >/dev/null 2>&1 ) || bad "worktree: the command failed"
chk "$([ -e "$lab/wt-tree/.specs/.git" ] && echo yes || echo no)" yes ".specs/.git exists, as a worktree pointer file"
chk "$([ -f "$lab/wt-tree/.specs/.git" ] && echo file || echo dir)" file "it is a pointer FILE, which is the case -e must handle"
b=$(git -C "$lab/wt-tree/.specs" rev-parse --abbrev-ref HEAD 2>/dev/null)
chk "$b" "feature-c-specs" "the spec tree is on its own branch"
echo "spec-side only" > "$lab/wt-tree/.specs/independent.md"
g "$lab/wt-tree/.specs" add -A; g "$lab/wt-tree/.specs" commit -qm "spec side"
chk "$([ -f "$r/.specs/independent.md" ] && echo yes || echo no)" no "a commit there does not appear on the main spec branch"
echo "dirty" > "$lab/wt-tree/.specs/dirty.md"
chk "$(blocks "$lab/wt-tree")" block "the guard fires through the worktree pointer file"

echo
echo "sdd-worktree: refusals"
r=$(mkrepo no-specs)
( cd "$r" && "$wt" f "$lab/r1" --specs=link >/dev/null 2>&1 )
chk "$?" 1 "link is refused when there is no spec repo"
chk "$([ -e "$lab/r1" ] && echo yes || echo no)" no "and it creates nothing"
( cd "$r" && "$wt" f "$lab/r2" --specs=worktree >/dev/null 2>&1 )
chk "$?" 1 "worktree is refused when there is no spec repo"

r=$(mkrepo plain-specs); mkdir -p "$r/.specs"; echo x > "$r/.specs/note.md"
( cd "$r" && "$wt" f "$lab/r3" --specs=worktree >/dev/null 2>&1 )
chk "$?" 1 "worktree is refused when .specs is not a git repo"
chk "$([ -e "$lab/r3" ] && echo yes || echo no)" no "and it creates nothing"

r=$(mkrepo existing); mkspecs "$r" noremote clean; mkdir -p "$lab/taken"
( cd "$r" && "$wt" f "$lab/taken" >/dev/null 2>&1 )
chk "$?" 1 "an existing target path is refused"

echo
echo "sdd-worktree: no dangling symlink is reachable"
dangling=0
for d in "$lab"/wt-*; do
  [ -L "$d/.specs" ] || continue
  [ -e "$d/.specs/.git" ] || dangling=$((dangling+1))
done
chk "$dangling" 0 "every .specs symlink created resolves to a spec repo"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
