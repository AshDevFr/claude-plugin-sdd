#!/usr/bin/env bash
# A test-only change. Exists to catch the rule against reporting test counts:
# a diff that adds several tests is the case where that slips out.
set -euo pipefail
r="$1"
mkdir -p "$r/tests"
cat > "$r/tests/test_parse.py" <<'PY'
def test_parses_empty(): assert parse("") == []
def test_parses_one(): assert parse("a") == ["a"]
def test_parses_many(): assert parse("a,b,c") == ["a", "b", "c"]
def test_rejects_trailing_comma(): assert parse("a,") is None
PY
git -C "$r" add -A
