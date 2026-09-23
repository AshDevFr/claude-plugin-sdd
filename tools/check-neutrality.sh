#!/usr/bin/env bash
# Fail when the `sdd` plugin names something the reader may not have: the author's
# infrastructure, one required git transport, or another plugin it does not ship.
#
# One invariant, three clauses. Shipped text is read by someone who installed this plugin and
# nothing else, on a machine that reaches neither the author's forge nor the author's habits.
# A private host they cannot clone, an SSH key they do not need, and a second plugin they do not
# have all fail the same way: an instruction that cannot be followed, with no hint that it was
# never meant for them.
#
# The drift this catches only matters because of how `sdd` is distributed. It is copied into a
# public snapshot by `snapshot-sdd.sh`, so anything reintroduced here reaches colleagues at the
# next publish, in a repository where the author's private host is unreachable and the reader has
# no way to know that the instruction was never meant for them. A diff does not read "git@" as a
# behaviour change; that is exactly why it needs a checker rather than care.
#
# It is the same family as check-prompt-contracts.sh: a free layer under the paid eval suite,
# greppable and boring, existing to catch an absence, which is unambiguous.
#
# Two halves:
#   1. Forbidden strings anywhere under plugins/sdd/, with one deliberate exception.
#   2. A required phrase in the install prose. A rewrite that puts SSH back as the sole
#      prerequisite will almost certainly drop the line that proves a remote generically, so
#      pinning that line is a cheap proxy for a property that cannot be grepped directly.
#   3. The names of other plugins. `sdd` once carried a table mapping five `superpowers` skills to
#      spec-repo paths and a paragraph endorsing that plugin by name. It was a personal working
#      note that reached shipped text, and it made a workflow plugin depend on a second plugin
#      overlapping it. The general rule it was a special case of survives and names nobody.
#
# Silent on success, like the other check-* scripts: no output and exit 0 is the pass.
#
# Needs bash and grep only.
set -uo pipefail

repo="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/plugin-root.sh
. "$here/plugin-root.sh"
plugin="$SDD_PLUGIN"
findings=0

say() { printf '%s\n' "$*"; }

[ -d "$plugin/commands" ] || { say "no sdd plugin found under $repo"; exit 1; }

# Scan what the plugin SHIPS, named explicitly. In the published snapshot the plugin is the
# repository root, so scanning "$plugin" would also sweep the harness directory beside it, where
# this script's own pattern list lives: the checker then reports itself and fails every run. Naming
# the shipped directories is also the honest scope, since a harness is not something a colleague
# is told to follow.
scan=()
for d in commands skills hooks bin scripts demo .claude-plugin; do
  [ -e "$plugin/$d" ] && scan+=("$plugin/$d")
done
[ -e "$plugin/README.md" ] && scan+=("$plugin/README.md")
[ ${#scan[@]} -gt 0 ] || { say "nothing to scan under $plugin"; exit 1; }

# --- 1. the author's infrastructure must not appear in the plugin -----------
#
# `plugin.json`'s author block is the exception and the only one. Attribution is not a transport
# assumption: a reader who cannot reach the author's forge loses nothing by the URL being there,
# whereas an instruction to clone from it is an instruction they cannot follow.
exception="$plugin/.claude-plugin/plugin.json"

# pattern|what it is
while IFS='|' read -r pat what; do
  [ -n "$pat" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file="${hit%%:*}"
    [ "$file" = "$exception" ] && continue
    say "transport: $what in ${file#"$repo"/}"
    say "    ${hit#*:}"
    findings=$((findings+1))
  done < <(grep -rnI -E "$pat" "${scan[@]}" 2>/dev/null)
done <<'PATTERNS'
4sh\.io|the author's git host
/home/ash\b|the author's home directory
/Users/ash\b|the author's home directory
ash-plugins|the author's marketplace name
gitea@|an SSH remote on the author's host
PATTERNS

# --- 2. the install prose must prove a remote, not require a transport ------
#
# Pinned phrase, with the reason recorded here rather than in a commit message nobody reads:
# `git ls-remote` is the one check that works for HTTPS, SSH and a local path alike. The prose
# that preceded it opened with "An SSH key authorised on the git host", which was false for every
# reader of the public snapshot.
required='git ls-remote'

for guide in "$repo/README.md" "$plugin/README.md"; do
  [ -f "$guide" ] || continue
  if ! grep -qF -- "$required" "$guide"; then
    say "transport: ${guide#"$repo"/} does not prove a remote with '$required'"
    say "    the install prose must work for HTTPS, SSH and a local path alike."
    say "    if this line moved on purpose, update the pin in $(basename "$0") and say why."
    findings=$((findings+1))
  fi
done

# --- 3. no other plugin's name in shipped text ------------------------------
#
# demo/ is excepted: it records why `.superpowers/` was removed from the demo project, which is a
# statement about a defect rather than an instruction to install anything.
#
# Add a name here when this plugin starts naming it. The list is short on purpose: a checker that
# greps for every plugin in existence would fire on prose that merely mentions one.
#
# Lines carrying a copyright notice are excepted. `sdd-dashboard`'s design follows another
# project's and credits it under MIT; stripping that to satisfy a neutrality rule would trade a
# licence obligation for tidiness, which is not a trade this check is allowed to make.
while IFS='|' read -r pat what; do
  [ -n "$pat" ] || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file="${hit%%:*}"
    case "${file#"$plugin"/}" in demo/*) continue ;; esac
    say "neutrality: $what in ${file#"$repo"/}"
    say "    ${hit#*:}"
    findings=$((findings+1))
    # Case-insensitive, and NOT by accident. The first version of this clause was case-sensitive
    # and walked straight past `sdd-dashboard`'s "Superpowers", the one mention in a shipped
    # script. A checker that misses the capitalised form of the word it exists to find is worse
    # than none, because it reports a clean tree.
  done < <(grep -rnIi -E "$pat" "${scan[@]}" 2>/dev/null | grep -vi 'copyright')
done <<'VENDORS'
superpowers|another plugin named in shipped text
VENDORS

[ "$findings" -eq 0 ] && exit 0
say ""
say "$findings finding(s)."
exit 1
