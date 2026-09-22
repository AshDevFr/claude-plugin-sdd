#!/usr/bin/env bash
# Fail when a load-bearing sentence has gone missing from a command, skill or rules file.
#
# Everything these plugins do, they do by telling a model to do it. There is no function to
# unit-test: the behaviour lives in the prompt, so the prompt is what must be checked. The
# failure this guards against has happened repeatedly here, and always the same way. A file is
# rewritten for length or for clarity, one sentence goes with the trimming, and nothing notices
# until an eval run costs money to tell you, or until nobody notices at all.
#
# `scripts/prompt-contracts.json` names, per file, the phrases that must survive a rewrite, each
# with the reason it is pinned. That reason is the point of the file. A contract without one
# leaves the next person exactly one move when it fires, which is to delete it.
#
# Patterns are extended regular expressions matched line by line, and they are deliberately
# short: a phrase, never a paragraph. A contract over a whole paragraph fires on every legitimate
# edit and gets removed within a month. A contract over four words fires when the idea leaves.
#
# A pattern may instead be an absence (`"absent": true`), for wording removed on measured
# grounds that must not come back.
#
# What this cannot do is tell a load-bearing sentence from a decorative one. That judgement is
# made when the contract is written, which is why each entry records it in prose.
#
# Silence and exit 0 mean clean. Exit 1 is a finding. Exit 2 means the contracts themselves could
# not be read, which is distinct on purpose: a caller that conflates the two reads a broken
# harness as a pass. Needs bash, grep and jq.
set -uo pipefail

repo="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
# Beside this script, not at a fixed path under the repo: the harnesses are copied into the
# published snapshot as tools/, and a checker that cannot find its own data file reports a missing
# file rather than a passing tree, which is at least loud but is still not the check running.
contracts="${2:-$(cd "$(dirname "$0")" && pwd)/prompt-contracts.json}"
[ -r "$contracts" ] || contracts="$repo/scripts/prompt-contracts.json"
findings=0

say() { printf '%s\n' "$*"; }

command -v jq >/dev/null 2>&1 || { say "jq is not on PATH, so the contracts cannot be read"; exit 2; }
[ -r "$contracts" ] || { say "no contracts file at $contracts"; exit 2; }
jq -e '.contracts | type == "object"' "$contracts" >/dev/null 2>&1 || {
  say "the contracts file cannot be parsed, or has no .contracts object: $contracts"
  exit 2
}

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  path="$repo/$rel"

  if [ ! -r "$path" ]; then
    # The quietest way for this whole harness to stop working. A renamed file takes every
    # pattern pinned to it out of service, and a run over the new tree looks identical to a
    # run over the old one: same exit code, same silence.
    say "contract names a file that does not exist: $rel"
    say "  every pattern pinned to it has stopped being checked. Repoint the contract at the"
    say "  file's new path, or remove it knowingly."
    findings=$((findings+1))
    continue
  fi

  n=$(jq -r --arg f "$rel" '.contracts[$f] | length' "$contracts")
  if [ "$n" -eq 0 ]; then
    say "contract pins nothing: $rel"
    say "  an entry with an empty pattern list is counted among the files covered and asserts"
    say "  nothing about any of them."
    findings=$((findings+1))
    continue
  fi

  i=0
  while [ "$i" -lt "$n" ]; do
    pat=$(jq -r --arg f "$rel" --argjson i "$i" '.contracts[$f][$i].pattern // ""' "$contracts")
    why=$(jq -r --arg f "$rel" --argjson i "$i" '.contracts[$f][$i].why // ""' "$contracts")
    absent=$(jq -r --arg f "$rel" --argjson i "$i" '.contracts[$f][$i].absent // false' "$contracts")
    i=$((i+1))

    if [ -z "$pat" ]; then
      say "contract entry has no pattern: $rel (entry $i)"
      findings=$((findings+1))
      continue
    fi
    if [ -z "$why" ]; then
      # Without this, a firing contract is indistinguishable from an obsolete one, and the
      # cheapest way out is always to delete it.
      say "contract has no reason attached: $rel"
      say "  pattern: $pat"
      say "  add \"why\": what breaks when this wording goes. A contract nobody can justify is"
      say "  one nobody can defend against a rewrite."
      findings=$((findings+1))
      continue
    fi

    if [ "$absent" = "true" ]; then
      if grep -qE -- "$pat" "$path"; then
        say "forbidden wording is back: $rel"
        say "  pattern: $pat"
        say "  why:     $why"
        findings=$((findings+1))
      fi
    elif ! grep -qE -- "$pat" "$path"; then
      say "contract broken: $rel"
      say "  pattern: $pat"
      say "  why:     $why"
      findings=$((findings+1))
    fi
  done
done < <(jq -r '.contracts | keys[]' "$contracts")

[ "$findings" -eq 0 ] && exit 0
say ""
say "$findings contract(s) no longer hold. Each pattern above is a sentence whose absence was"
say "a defect once. If a rewrite retired one on purpose, edit prompt-contracts.json in the same"
say "commit and say why there."
exit 1
