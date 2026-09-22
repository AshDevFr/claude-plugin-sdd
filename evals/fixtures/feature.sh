#!/usr/bin/env bash
# A staged feature change with a non-obvious reason, so a good message has
# something to explain beyond restating the diff.
set -euo pipefail
r="$1"
mkdir -p "$r/src"
cat > "$r/src/auth.py" <<'PY'
def login(user, password):
    # Constant time: a plain == leaks length and prefix through timing.
    import hmac
    return hmac.compare_digest(lookup_hash(password), lookup_hash(user))
PY
git -C "$r" add -A
