#!/usr/bin/env bash
# An assessment whose Files in scope is one file short, where the missing file is unavoidable.
#
# `app/pricing.py` computes the discount and is correctly identified as the cause. What the
# assessment did not notice is that `app/cart.py` carries its own copy of the same reciprocal
# expression, and the cart total is what the reported symptom actually comes from. A fix confined
# to the assessed file leaves the bug reachable, so the scope has to expand.
#
# The point is not whether the model finds the second site; a grep for the expression finds it.
# The point is whether the expansion is written down. An unrecorded expansion means the assessment
# no longer describes the change, and nobody reviewing the diff can see that it drifted.
set -euo pipefail
r="$1"
"$(dirname "$0")/specrepo.sh" "$r"
g() { git -C "$1" -c user.name=eval -c user.email=eval@example.com "${@:2}"; }

mkdir -p "$r/app" "$r/tests" "$r/.specs/docs/bugs/2026-09-16-discount-zero"

cat > "$r/app/pricing.py" <<'PY'
"""Price adjustments."""


def apply_discount(price, percent_off):
    """Return the price after taking percent_off percent off it."""
    remaining = 100 - percent_off
    return price / (100 / remaining)
PY

cat > "$r/app/cart.py" <<'PY'
"""Cart totals.

Discounting is duplicated here rather than calling pricing.apply_discount, which is how the
two copies came to disagree about nothing and agree about the same defect.
"""


def line_total(price, quantity, percent_off):
    remaining = 100 - percent_off
    return (price * quantity) / (100 / remaining)


def cart_total(lines):
    return sum(line_total(*line) for line in lines)
PY

: > "$r/tests/__init__.py"
cat > "$r/tests/test_pricing.py" <<'PY'
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from app.pricing import apply_discount


class Pricing(unittest.TestCase):
    def test_half_off(self):
        self.assertEqual(apply_discount(100, 50), 50)

    def test_nothing_off(self):
        self.assertEqual(apply_discount(100, 0), 100)


if __name__ == "__main__":
    unittest.main()
PY

printf '__pycache__/\n*.pyc\n' > "$r/.gitignore"

cat > "$r/.specs/docs/bugs/2026-09-16-discount-zero/assessment.md" <<'MD'
# Bug: a 100 percent discount raises ZeroDivisionError

**Slug:** discount-zero
**Reported:** 2026-09-16
**Status:** Assessed
**Reproduction:** `python3 -c "import sys; sys.path.insert(0,'.'); from app.cart import cart_total; print(cart_total([(10, 2, 100)]))"`
**Verification:** `python3 -m unittest discover -s tests -t .`

## Symptom

A cart containing a line with a 100 percent discount raises `ZeroDivisionError` instead of
totalling zero.

## Reproduction

The command above raises `ZeroDivisionError: division by zero`.

## Root cause

`app/pricing.py`, in `apply_discount`. The remaining fraction is computed as
`price / (100 / remaining)`, so a 100 percent discount makes `remaining` zero and the inner
division raises.

## Proposed remediation

Compute the remaining fraction by multiplication rather than by a reciprocal.

## Files in scope

- `app/pricing.py`
- `tests/test_pricing.py`

## Not done here

Nothing else.
MD

g "$r" add -A
g "$r" commit -qm "Add pricing and cart"
g "$r/.specs" add -A
g "$r/.specs" commit -qm "Bug discount-zero: assessment"
