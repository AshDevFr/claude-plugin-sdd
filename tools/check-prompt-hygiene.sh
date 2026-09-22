#!/usr/bin/env bash
# Fail if any command or skill has picked up prompt anti-patterns.
#
# The practice atlas cites measured figures for removing these: thoroughness boosters,
# verification rituals and scratchpad scaffolds cost tokens and buy no behaviour. A pass
# over every command and skill in this repo found none of them, so this script exists to
# keep it that way rather than to clean anything up.
#
# It deliberately does not police length. A long document is not a defect: the intricate
# commands are long because the work is, and the templates are structured because the
# structure is what makes a document readable months later. This checks for filler, not
# for size.
set -uo pipefail

repo="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
findings=0

# Phrases that add emphasis without adding instruction.
boosters='\b(carefully|be thorough|thoroughly|make sure to|ensure that you|it is important|very important|remember to|do not forget|double-check|step by step|take your time|as an AI)\b'

# A scratchpad scaffold tells the model where to think rather than what to do.
scaffolds='\b(think step by step|let.s think|in your scratchpad|reason out loud|before answering, think)\b'

while IFS= read -r f; do
  [ -r "$f" ] || continue
  rel=${f#"$repo"/}
  hits=$(grep -inE "$boosters" "$f" | head -3)
  if [ -n "$hits" ]; then
    echo "thoroughness boosters in $rel"
    printf '    %s\n' "$hits"
    findings=$((findings+1))
  fi
  hits=$(grep -inE "$scaffolds" "$f" | head -3)
  if [ -n "$hits" ]; then
    echo "scratchpad scaffold in $rel"
    printf '    %s\n' "$hits"
    findings=$((findings+1))
  fi
  # A description promising behaviour nothing implements is the defect commit-msg had:
  # it advertised phase awareness while the body forbade naming phases.
  desc=$(sed -n 's/^description: //p' "$f" | head -1)
  if [ -n "$desc" ] && printf '%s' "$desc" | grep -qiE '\bphase[- ]aware'; then
    echo "description claims phase awareness in $rel, which the rules forbid in output"
    findings=$((findings+1))
  fi
done < <(find "$repo/plugins" -name '*.md' \( -path '*/commands/*' -o -path '*/agents/*' -o -name 'SKILL.md' \) | sort)

[ "$findings" -eq 0 ] && exit 0
echo
echo "$findings artefact(s) carry prompt anti-patterns"
exit 1
