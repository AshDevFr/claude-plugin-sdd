#!/usr/bin/env bash
# Assert that `sdd` points at nothing it does not ship.
#
# Every other check in this phase asserts that text exists. This one asserts the plugin WORKS on
# its own: that no skill reference, command reference or agent name inside `sdd` resolves to
# something only another plugin provides. The README has claimed "sdd works installed on its own"
# since phase 1, and until now the only thing checking it was the author reading.
#
# It is referential, not behavioural, and says so. It proves nothing points at a missing file. It
# cannot prove the guidance is any good.
#
# Silent on success, like the other check-* scripts, but named test-* because it builds a dirtied
# copy to prove it can fail.
#
# Needs bash and grep only.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/plugin-root.sh
. "$here/plugin-root.sh"

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); }

echo "sdd stands alone"

# The namespaces that are real plugin references. Taken from the marketplace's own plugins plus
# names known to belong to other plugins, because `<ns>:<name>` is a shape that ordinary text hits
# by accident: the first version of this file reported `<!-- /preflight:list -->` as a command
# reference to a plugin called `preflight`.
namespaces() {
  for d in "$SDD_REPO"/plugins/*/; do [ -d "$d" ] && basename "$d"; done
  printf 'superpowers\n'
}
known_ns() { namespaces | grep -qx "$1"; }

# scan <plugin-dir> -> prints "kind|reference|file:line" for everything sdd points at
scan() {
  local root=$1
  # Skill("<ns>:<name>") and Skill('<ns>:<name>')
  grep -rnoIE 'Skill\("[a-z0-9-]+:[a-z0-9-]+"\)' "$root" 2>/dev/null |
    sed -E 's|^([^:]+):([0-9]+):Skill\("([a-z0-9-]+):([a-z0-9-]+)"\)|skill\|\3:\4\|\1:\2|'
  # /<ns>:<command>
  grep -rnoIE '/[a-z0-9-]+:[a-z0-9-]+' "$root" 2>/dev/null |
    sed -E 's|^([^:]+):([0-9]+):/([a-z0-9-]+):([a-z0-9-]+)|command\|\3:\4\|\1:\2|'
}

# --- A. every reference resolves inside sdd ---------------------------------
# A reference to `delegation` is a failure, not an exception: the convention is that sdd describes
# delegation generically and never names a specific agent, and this is the check that has never
# existed for it.
dangling=0
foreign=0
while IFS='|' read -r kind ref where; do
  [ -n "$kind" ] || continue
  ns=${ref%%:*}; name=${ref#*:}
  known_ns "$ns" || continue   # not a plugin reference, just text shaped like one
  case "$ns" in
    sdd) ;;
    *) case "$where" in
         */demo/*) continue ;;
       esac
       bad "$kind reference to another plugin: $ref at ${where#"$SDD_REPO"/}"
       foreign=$((foreign+1)); continue ;;
  esac
  case "$kind" in
    skill)   [ -f "$SDD_PLUGIN/skills/$name/SKILL.md" ] && continue ;;
    command) [ -f "$SDD_PLUGIN/commands/$name.md" ] && continue ;;
  esac
  bad "$kind '$ref' resolves to nothing sdd ships, at ${where#"$SDD_REPO"/}"
  dangling=$((dangling+1))
done < <(scan "$SDD_PLUGIN" | sort -u)

[ "$dangling" -eq 0 ] && ok "every skill and command reference resolves to something sdd ships"
[ "$foreign" -eq 0 ] && ok "no reference names another plugin"

# --- B. no agent names -------------------------------------------------------
# sdd's rules describe delegation in general terms. A specific agent name here would dangle the
# moment sdd is installed alone, which is the configuration the README promises works.
# The bare-name list matches test-hooks.sh's plugin-separation check exactly, and `implementer` is
# deliberately absent from it: it is an ordinary English word that appears in prose describing
# delegation generically, which is the thing sdd is supposed to do. The namespaced forms are
# checked separately, where `delegation:implementer` IS a defect.
agents=$(grep -rnIE '\b(scout|test-runner|code-reviewer|architect|antigravity)\b|delegation:[a-z-]+' \
  "$SDD_PLUGIN/commands" "$SDD_PLUGIN/skills" "$SDD_PLUGIN/hooks" 2>/dev/null || true)
if [ -z "$agents" ]; then ok "no delegation agent is named in sdd's commands, skills or hooks"
else
  bad "sdd names a specific delegation agent"
  printf '%s\n' "$agents" | head -3 | sed "s|$SDD_REPO/||;s|^|          |"
fi

# --- C. the checks can fail --------------------------------------------------
# Three copies, one defect each. A referential check that cannot see a dangling reference is the
# only kind of defect this file could plausibly have.
if [ -n "${SDD_STANDALONE_NESTED:-}" ]; then
  # A nested run exists to be inspected by its parent, not to re-run the probes: without this each
  # probe spawns three more, and those spawn three more.
  echo
  echo "  $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
  exit $?
fi

lab=$(mktemp -d); trap 'rm -rf "$lab"' EXIT
probe() {
  local label=$1 file=$2 text=$3 want=$4
  local d
  d="$lab/$(printf '%s' "$label" | tr -c 'a-zA-Z0-9' '-')"
  # From the RESOLVED plugin root, not a hardcoded plugins/sdd. In a published copy the plugin is
  # the repository root and there is no plugins/ at all, so the probes copied nothing and all three
  # reported failure while the checks above passed. Caught by running this inside a snapshot.
  mkdir -p "$d/plugins" "$d/scripts"
  cp -R "$SDD_PLUGIN" "$d/plugins/sdd"
  cp "$here/plugin-root.sh" "$here/$(basename "$0")" "$d/scripts/"
  printf '%s\n' "$text" >> "$d/plugins/sdd/$file"
  # Capture, then grep. Piping the copy straight into grep looks right and is not: `pipefail` is
  # set, the dirtied copy correctly exits 1, and the pipeline then reports failure even when grep
  # matched. The first version of this file reported all three probes failing while every one of
  # them was working.
  local out
  out=$(SDD_STANDALONE_NESTED=1 "$d/scripts/$(basename "$0")" 2>&1)
  if printf '%s' "$out" | grep -q "$want"; then ok "detects $label"
  else
    bad "detects $label"
    printf '%s\n' "$out" | head -3 | sed 's/^/          /'
  fi
}
probe "a dangling skill reference"   "commands/plan.md" 'See Skill("sdd:no-such-skill") for more.' 'resolves to nothing'
probe "a dangling command reference" "commands/plan.md" 'Then run /sdd:no-such-command to finish.' 'resolves to nothing'
probe "a named delegation agent"     "commands/plan.md" 'Dispatch delegation:implementer for this.' 'names a specific delegation agent'

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
