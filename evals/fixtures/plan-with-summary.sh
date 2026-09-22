#!/usr/bin/env bash
# A multi-phase plan in the template's own layout: the Progress Summary table sits after
# Quick Links rather than first, and the log is called Progress Tracking. That is the shape
# on which /sdd:implement once inserted a second table above Quick Links and renamed the log.
set -euo pipefail
r="$1"
"$(dirname "$0")/specrepo.sh" "$r"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }
mkdir -p "$r/.specs/docs/plans"
cat > "$r/.specs/docs/plans/2026-09-12-audit-trail.md" <<'MD'
# Audit Trail - Implementation Plan

**Status:** 🔵 Not Started
**Created:** 2026-09-12
**Last Updated:** 2026-09-12
**Estimated Completion:** hours

## Quick Links

- Entry point: `src/main.py`

## Progress Summary

| Phase   | Status         | Description                         |
| ------- | -------------- | ----------------------------------- |
| Phase 1 | 🔵 NOT STARTED | Append-only log, fsynced per entry  |
| Phase 2 | 🔵 NOT STARTED | Read-only endpoint over the log     |

## Status Legend

- 🔵 Not Started | 🟡 In Progress | 🟢 Complete | 🔴 Blocked

## Implementation Phases

### Phase 1 - Append-only log

Write each widget read to `audit.log`, one JSON object per line, fsynced per entry.

**Done when:** a read produces exactly one line and survives a kill immediately after.

### Phase 2 - Expose it

A read-only endpoint returning the log, newest first, with a cursor.

## Progress Tracking

### 2026-09-12 - Plan written

Scope settled on a local file; no database.
MD
g "$r/.specs" add -A
g "$r/.specs" commit -qm "Add the audit trail plan"
