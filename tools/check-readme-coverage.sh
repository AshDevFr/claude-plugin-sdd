#!/usr/bin/env bash
# Fail when a command, skill, agent or script this marketplace ships is named nowhere
# in README.md.
#
# The drift this catches is the cheapest kind to introduce and the hardest to notice: an
# artefact is added, it works, its tests pass, and the one document a colleague reads
# never learns it exists. It happened here. `toolkit` shipped exactly one skill,
# `rust-bootstrap`, and the README described the plugin as "language and domain skills"
# without ever naming it, so the only way to discover the plugin's entire contents was to
# clone the repository the README exists to save you cloning.
#
# Scope is the four kinds the guide promises to cover. Hooks are deliberately excluded:
# the README documents what a hook will do to you, not which files implement it, and
# listing eight script names would be inventory rather than guidance.
#
# A script counts as covered under its own name or under the command that invokes it,
# because `sdd-bootstrap` is reached as `/sdd:bootstrap` and naming the file as well
# would be noise. Only executables are checked, so data files sitting in scripts/ are
# not mistaken for entry points.
#
# It matches substrings and does not attempt precision. A check that a name appears
# somewhere cannot tell a real mention from an accident, and does not need to: it exists
# to catch absence, which is unambiguous. The reverse direction, a README naming
# something that no longer ships, is not checked here.
#
# Needs bash and grep only, so it runs anywhere the rest of the harness does.
set -uo pipefail

repo="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
missing=0

# The corpus is the root README plus each plugin's own, because a plugin published on its own
# carries its guide and not this repository's front page. It is a UNION and not an alternative:
# an artefact named in neither is still a failure, which is the whole point. Naming it in the
# plugin's guide is the better answer of the two, since that is the document that travels.
readmes=("$repo/README.md")
for g in "$repo"/plugins/*/README.md; do
  [ -r "$g" ] && readmes+=("$g")
done

if [ ! -r "$repo/README.md" ]; then
  echo "no README.md at $repo"
  exit 1
fi

# covered <kind> <label> <token> [alternate-token]
covered() {
  local kind=$1 label=$2 tok=$3 alt=${4:-} f
  for f in "${readmes[@]}"; do
    grep -qF -- "$tok" "$f" && return 0
    [ -n "$alt" ] && grep -qF -- "$alt" "$f" && return 0
  done
  echo "$kind not mentioned in any README: $label"
  missing=$((missing + 1))
}

# Both layouts. A marketplace holds plugins under plugins/<name>/; a published single plugin IS
# the repository root. Getting this wrong is worse than a false failure: the loop would simply
# find nothing and the check would pass while checking nothing, which is how a guard stops being
# one without anybody noticing.
plugin_dirs=()
for d in "$repo"/plugins/*/; do
  [ -d "$d" ] && plugin_dirs+=("$d")
done
if [ ${#plugin_dirs[@]} -eq 0 ] && [ -r "$repo/.claude-plugin/plugin.json" ]; then
  plugin_dirs=("$repo/")
fi
if [ ${#plugin_dirs[@]} -eq 0 ]; then
  echo "no plugins found at $repo"
  exit 1
fi

for d in "${plugin_dirs[@]}"; do
  plugin=$(basename "$d")
  # At the repo root the directory name is the checkout's name, not the plugin's. Read it.
  if [ "$d" = "$repo/" ] && command -v jq >/dev/null 2>&1; then
    plugin=$(jq -r '.name // empty' "$repo/.claude-plugin/plugin.json" 2>/dev/null || true)
    [ -n "$plugin" ] || plugin=$(basename "$repo")
  fi

  for f in "$d"commands/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .md)
    covered command "/$plugin:$name" "/$plugin:$name"
  done

  for s in "$d"skills/*/; do
    [ -e "$s" ] || continue
    name=$(basename "$s")
    covered skill "$plugin:$name" "$name"
  done

  for f in "$d"agents/*.md; do
    [ -e "$f" ] || continue
    name=$(basename "$f" .md)
    covered agent "$plugin:$name" "$name"
  done

  # bin/ as well as scripts/: a plugin's bin/ is put on the Bash PATH, so what ships there is
  # something a session runs by bare name, which is more reason to name it, not less.
  for f in "$d"scripts/* "$d"bin/*; do
    [ -x "$f" ] || continue
    name=$(basename "$f")
    # sdd-bootstrap is reached as /sdd:bootstrap, so either form counts.
    covered script "$name" "$name" "/$plugin:${name#"$plugin"-}"
  done
done

[ "$missing" -eq 0 ] && exit 0
echo
echo "$missing artefact(s) ship with no mention in the README a colleague reads first"
exit 1
