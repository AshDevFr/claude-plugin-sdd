#!/usr/bin/env bash
# A plain repo with no spec tree. For cases where the spec machinery is irrelevant
# and would only add the commit policy as noise.
set -euo pipefail
r="$1"
echo "# scratch" > "$r/README.md"
git -C "$r" add -A
