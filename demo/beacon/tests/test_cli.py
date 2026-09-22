import contextlib
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from beacon.cli import main

HERE = os.path.dirname(os.path.abspath(__file__))
EXAMPLES = os.path.join(os.path.dirname(HERE), "examples")
GOOD = os.path.join(EXAMPLES, "incidents.toml")
BROKEN = os.path.join(EXAMPLES, "broken.toml")


def run(argv):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = main(argv)
    return code, out.getvalue(), err.getvalue()


class Check(unittest.TestCase):
    # Non-zero while something is open, so a deploy pipeline can refuse to ship into an outage.
    def test_exits_non_zero_while_an_incident_is_open(self):
        code, out, _ = run(["check", GOOD])
        self.assertEqual(code, 1)
        self.assertIn("1 open", out)

    def test_reports_the_overall_state(self):
        _, out, _ = run(["check", GOOD])
        self.assertIn("Monitoring", out)

    def test_a_bad_file_exits_two_and_explains(self):
        code, _, err = run(["check", BROKEN])
        self.assertEqual(code, 2)
        self.assertIn("degraded", err)

    def test_a_missing_file_exits_two(self):
        code, _, err = run(["check", os.path.join(EXAMPLES, "nope.toml")])
        self.assertEqual(code, 2)
        self.assertIn("beacon:", err)


class Render(unittest.TestCase):
    def test_writes_a_file_and_says_so(self):
        with tempfile.TemporaryDirectory() as d:
            out_path = os.path.join(d, "status.html")
            code, out, _ = run(["render", GOOD, "-o", out_path])
            self.assertEqual(code, 0)
            self.assertIn("3 incident(s)", out)
            with open(out_path, encoding="utf-8") as f:
                self.assertIn("<!DOCTYPE html>", f.read())

    def test_dash_writes_to_stdout(self):
        code, out, _ = run(["render", GOOD, "-o", "-"])
        self.assertEqual(code, 0)
        self.assertIn("<!DOCTYPE html>", out)

    def test_title_reaches_the_page(self):
        _, out, _ = run(["render", GOOD, "-o", "-", "--title", "Acme Status"])
        self.assertIn("<title>Acme Status</title>", out)


if __name__ == "__main__":
    unittest.main()
