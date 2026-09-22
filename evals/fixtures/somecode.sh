#!/usr/bin/env bash
# A small piece of non-obvious code, for cases about explaining it.
set -euo pipefail
r="$1"
mkdir -p "$r/src"
cat > "$r/src/ratelimit.py" <<'PY2'
import time

class TokenBucket:
    def __init__(self, rate, burst):
        self.rate, self.burst = rate, burst
        self.tokens = burst
        self.updated = time.monotonic()

    def allow(self, cost=1):
        now = time.monotonic()
        self.tokens = min(self.burst, self.tokens + (now - self.updated) * self.rate)
        self.updated = now
        if self.tokens >= cost:
            self.tokens -= cost
            return True
        return False
PY2
git -C "$r" add -A
