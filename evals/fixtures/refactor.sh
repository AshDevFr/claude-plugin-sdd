#!/usr/bin/env bash
# A refactor whose only motivation lives in a planning document. This is the case
# where a phase number or task id leaks into a commit message.
set -euo pipefail
r="$1"
mkdir -p "$r/src"
cat > "$r/src/queue.py" <<'PY'
class SeriesQueue:
    def __init__(self): self._items = []
    def push(self, item): self._items.append(item)
    def drain(self): out, self._items = self._items, []; return out
PY
git -C "$r" add -A
