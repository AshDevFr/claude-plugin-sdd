# Resolve where the sdd plugin's files are, so a harness works in either layout.
#
# This repository is a marketplace, so the plugin sits at plugins/sdd/. The published snapshot is
# the plugin itself, with commands/, skills/, hooks/ and scripts/ at its root. The harnesses travel
# into that snapshot, and they have to find the same files in both places.
#
# The alternative was rewriting paths with sed while producing the snapshot. Rejected: it makes the
# fork's files textually different from the ones that were tested here, so a bug in the rewrite is
# a bug nothing has ever run. Resolving at runtime means the file that ships is the file that
# passed.
#
# Sets SDD_REPO (the tree's root) and SDD_PLUGIN (where the plugin's files are). Sourced, not run.
# Takes the root from $repo when the caller has one (the check-* scripts accept it as an argument),
# otherwise from $here/.. (the test-* harnesses compute $here from $0).

if [ -n "${repo:-}" ]; then
  SDD_REPO=$(cd "$repo" && pwd)
else
  SDD_REPO=$(cd "${here:?plugin-root.sh needs \$here or \$repo}/.." && pwd)
fi
if [ -d "$SDD_REPO/plugins/sdd" ]; then
  SDD_PLUGIN="$SDD_REPO/plugins/sdd"
else
  SDD_PLUGIN="$SDD_REPO"
fi

# The delegation plugin is a sibling in the marketplace and absent from a published copy of sdd
# alone. Empty rather than missing, so a harness can skip its sections instead of failing them:
# those failures say nothing about the tree under test.
if [ -d "$SDD_REPO/plugins/delegation" ]; then
  SDD_DELEGATION="$SDD_REPO/plugins/delegation"
else
  SDD_DELEGATION=""
fi
