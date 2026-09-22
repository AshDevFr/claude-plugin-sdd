#!/usr/bin/env bash
# A spec repo with an implementation plan and some real commits, so a PR message has
# both a plan to read and a diff to describe.
set -euo pipefail
r="$1"
"$(dirname "$0")/specrepo.sh" "$r"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }
mkdir -p "$r/.specs/docs/plans"
cat > "$r/.specs/docs/plans/2026-09-01-audit-trail.md" <<'MD'
# Plan: Audit trail

**Status:** 🟢 Complete
**Created:** 2026-09-01

## Objective

Record every widget read in a durable log so an operator can reconstruct who saw what.

## Phases

### Phase 1: Append-only log
Write each read to a local append-only file, fsynced per entry.

### Phase 2: Expose it
A read-only endpoint returning the log, newest first, with a cursor.
MD
g "$r/.specs" add -A
g "$r/.specs" commit -qm "Add the audit trail plan"
mkdir -p "$r/src"
cat > "$r/src/audit.py" <<'PY2'
import os, json

def append(entry, path="audit.log"):
    # fsync per entry: an operator reconstructing an incident needs the log to
    # survive a hard kill, and buffered writes lose the last seconds.
    with open(path, "a") as fh:
        fh.write(json.dumps(entry) + "\n")
        fh.flush()
        os.fsync(fh.fileno())
PY2
g "$r" add -A
g "$r" commit -qm "feat: append-only audit log with fsync per entry"
