#!/usr/bin/env python3
"""Unit tests for spec-analyze.py, on fixture spec trees built from nothing."""

import importlib.util
import os
import pathlib
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("spec_analyze", HERE / "spec-analyze.py")
sa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sa)


def write(root, rel, text):
    p = pathlib.Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)
    return p


def task(status="Not Started", verif="`./run-tests`", depends="None", extra=""):
    v = f"**Verification:** {verif}\n" if verif else ""
    return (f"# Task 1.01: Fixture\n\n**Status:** {status}\n**Depends On:** {depends}\n{v}{extra}")


def kinds(findings):
    return sorted(f["finding"] for f in findings)


class Analyze(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.docs = os.path.join(self.d.name, "docs")
        os.makedirs(self.docs)

    def tearDown(self):
        self.d.cleanup()

    def run_on(self):
        return sa.analyze(self.docs)

    # --- the clean case ----------------------------------------------------------------
    def test_a_consistent_tree_reports_nothing(self):
        write(self.docs, "specs/phase-1_x.md",
              "# Phase 1\n\n| Task | Status | Description |\n| 1.01 | 🟢 COMPLETE | thing |\n")
        write(self.docs, "tasks/phase-1/1.01-thing.md", task(status="Complete"))
        self.assertEqual(self.run_on(), [])

    # --- documents disagreeing with each other -----------------------------------------
    def test_a_summary_row_with_no_task_file(self):
        write(self.docs, "specs/phase-1_x.md",
              "# Phase 1\n\n| 1.01 | 🟢 COMPLETE | thing |\n| 1.02 | 🔵 NOT STARTED | other |\n")
        write(self.docs, "tasks/phase-1/1.01-thing.md", task(status="Complete"))
        self.assertIn("MISSING-TASK", kinds(self.run_on()))

    def test_a_task_file_no_summary_mentions(self):
        write(self.docs, "specs/phase-1_x.md", "# Phase 1\n\n| 1.01 | 🟢 COMPLETE | thing |\n")
        write(self.docs, "tasks/phase-1/1.01-thing.md", task(status="Complete"))
        write(self.docs, "tasks/phase-1/1.09-stray.md", task(status="Complete"))
        self.assertIn("ORPHAN-TASK", kinds(self.run_on()))

    def test_status_disagreement_is_reported_both_ways(self):
        write(self.docs, "specs/phase-1_x.md", "# Phase 1\n\n| 1.01 | 🟢 COMPLETE | thing |\n")
        write(self.docs, "tasks/phase-1/1.01-thing.md", task(status="In Progress"))
        f = [x for x in self.run_on() if x["finding"] == "STATUS-DISAGREE"]
        self.assertEqual(len(f), 1)
        self.assertIn("in-progress", f[0]["detail"])
        self.assertIn("complete", f[0]["detail"])

    def test_a_prd_phase_with_no_spec(self):
        write(self.docs, "PRD.md", "# PRD\n\n| Phase | Name |\n| 1 | one |\n| 2 | two |\n")
        write(self.docs, "specs/phase-1_x.md", "# Phase 1\n")
        f = [x for x in self.run_on() if x["finding"] == "NO-SPEC"]
        self.assertEqual(len(f), 1)
        self.assertIn("phase 2", f[0]["detail"])

    # --- verifications that prove nothing -----------------------------------------------
    def test_a_missing_verification(self):
        write(self.docs, "tasks/phase-1/1.01-thing.md", task(verif=""))
        self.assertIn("NO-VERIFICATION", kinds(self.run_on()))

    def test_a_placeholder_verification(self):
        write(self.docs, "tasks/phase-1/1.01-thing.md", task(verif="`[one runnable command]`"))
        self.assertIn("PLACEHOLDER-VERIF", kinds(self.run_on()))

    def test_a_verification_that_cannot_fail(self):
        for cmd in ("`echo ok`", "`true`", "`:`", "`cd src`", "`ls`"):
            with self.subTest(cmd=cmd):
                write(self.docs, "tasks/phase-1/1.01-thing.md", task(verif=cmd))
                self.assertIn("WEAK-VERIF", kinds(self.run_on()), cmd)

    def test_a_real_command_is_not_flagged_as_weak(self):
        for cmd in ("`./run-tests`", "`cargo test -p parser`", "`make lint`", "`pytest tests/`"):
            with self.subTest(cmd=cmd):
                write(self.docs, "tasks/phase-1/1.01-thing.md", task(verif=cmd))
                self.assertNotIn("WEAK-VERIF", kinds(self.run_on()), cmd)

    # --- dependencies --------------------------------------------------------------------
    def test_depends_on_a_task_that_does_not_exist(self):
        write(self.docs, "tasks/phase-1/1.01-thing.md", task(depends="1.07"))
        self.assertIn("DEP-MISSING", kinds(self.run_on()))

    def test_in_progress_depending_on_something_incomplete(self):
        write(self.docs, "tasks/phase-1/1.01-thing.md", task(status="In Progress", depends="1.02"))
        write(self.docs, "tasks/phase-1/1.02-other.md", task(status="Not Started"))
        self.assertIn("DEP-INCOMPLETE", kinds(self.run_on()))

    def test_not_started_depending_on_something_incomplete_is_fine(self):
        # Only work claimed to be underway is a problem; a queued task may wait.
        write(self.docs, "tasks/phase-1/1.01-thing.md", task(status="Not Started", depends="1.02"))
        write(self.docs, "tasks/phase-1/1.02-other.md", task(status="Not Started"))
        self.assertNotIn("DEP-INCOMPLETE", kinds(self.run_on()))

    # --- unresolved questions --------------------------------------------------------------
    def test_a_clarification_marker_anywhere_is_found(self):
        write(self.docs, "specs/phase-1_x.md",
              "# Phase 1\n\nUse [NEEDS CLARIFICATION: stdlib or FastAPI?] for the server.\n")
        f = [x for x in self.run_on() if x["finding"] == "CLARIFICATION"]
        self.assertEqual(len(f), 1)
        self.assertIn("FastAPI", f[0]["detail"])

    def test_a_quoted_marker_is_documentation_not_a_question(self):
        # This repo's own plan quotes the convention in backticks; flagging it sends a reader to
        # a file that is working as intended.
        write(self.docs, "specs/phase-1_x.md",
              "# Phase 1\n\nCommands write `[NEEDS CLARIFICATION: <question>]` rather than guessing.\n")
        self.assertNotIn("CLARIFICATION", kinds(self.run_on()))

    def test_a_placeholder_question_is_not_a_question(self):
        write(self.docs, "specs/phase-1_x.md",
              "# Phase 1\n\nUse [NEEDS CLARIFICATION: <the question>] here.\n")
        self.assertNotIn("CLARIFICATION", kinds(self.run_on()))

    def test_a_real_marker_beside_a_quoted_one_is_still_found(self):
        write(self.docs, "specs/phase-1_x.md",
              "# Phase 1\n\nWrite `[NEEDS CLARIFICATION: <question>]`.\n\n"
              "[NEEDS CLARIFICATION: stdlib or FastAPI?]\n")
        f = [x for x in self.run_on() if x["finding"] == "CLARIFICATION"]
        self.assertEqual(len(f), 1)
        self.assertIn("FastAPI", f[0]["detail"])

    # --- the contract ------------------------------------------------------------------------
    def test_nothing_is_edited(self):
        p = write(self.docs, "tasks/phase-1/1.01-thing.md", task(verif="`echo ok`"))
        before = p.read_text()
        self.run_on()
        self.assertEqual(p.read_text(), before)


class Criteria(unittest.TestCase):
    """Numbered criteria, and the three findings that read them.

    The whole point of an ID is that something else can cite it, so the risks are all about
    references: one that points nowhere, one number meaning two things, and a requirement no
    reference reaches at all.

    The constraint running through every case below is that IDs are optional. A tree written
    before they existed must report exactly what it reported before, which is why the first two
    cases assert silence rather than a finding.
    """

    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.docs = os.path.join(self.d.name, "docs")
        os.makedirs(self.docs)

    def tearDown(self):
        self.d.cleanup()

    def run_on(self):
        return sa.analyze(self.docs)

    def spec(self, criteria, rows="| 1.01 | 🟢 COMPLETE | thing |"):
        return write(self.docs, "specs/phase-1_x.md",
                     f"# Phase 1\n\n| Task | Status | Description |\n{rows}\n\n"
                     f"## Success Criteria\n\n{criteria}\n")

    def task(self, criteria, num="1.01", status="Complete"):
        return write(self.docs, f"tasks/phase-1/{num}-thing.md",
                     f"# Task {num}: Fixture\n\n**Status:** {status}\n**Depends On:** None\n"
                     f"**Verification:** `./run-tests`\n\n"
                     f"## Acceptance Criteria\n\n{criteria}\n")

    # --- documents without IDs are untouched by all of this ----------------------------
    def test_a_tree_with_no_ids_anywhere_reports_nothing_new(self):
        self.spec("- [ ] the widget list loads\n- [ ] it loads in under a second")
        self.task("- [ ] Given a store, when listed, then 200")
        self.assertEqual(kinds(self.run_on()), [])

    def test_a_spec_with_ids_whose_tasks_have_none_reports_nothing(self):
        # The migration case, and the one that decides whether this is usable on a live repo.
        # A spec regenerated with IDs beside tasks written before them has no coverage recorded
        # anywhere, which is not the same as coverage being absent. Reporting every criterion as
        # uncovered here would bury the findings that mean something under a wall that means
        # "this repo has not adopted the annotation yet".
        self.spec("- [ ] **SC-01:** the widget list loads\n- [ ] **SC-02:** in under a second")
        self.task("- [ ] Given a store, when listed, then 200")
        self.assertEqual(kinds(self.run_on()), [])

    # --- a criterion nothing covers ----------------------------------------------------
    def test_a_success_criterion_no_task_covers(self):
        self.spec("- [ ] **SC-01:** the widget list loads\n- [ ] **SC-02:** in under a second")
        self.task("- [ ] **AC1:** Given a store, when listed, then 200 (covers SC-01)")
        f = [x for x in self.run_on() if x["finding"] == "UNCOVERED-CRITERION"]
        self.assertEqual(len(f), 1)
        self.assertIn("SC-02", f[0]["detail"])

    def test_one_criterion_covered_by_two_tasks_is_not_a_finding(self):
        self.spec("- [ ] **SC-01:** the widget list loads",
                  rows="| 1.01 | 🟢 COMPLETE | a |\n| 1.02 | 🟢 COMPLETE | b |")
        self.task("- [ ] **AC1:** the list renders (covers SC-01)", num="1.01")
        self.task("- [ ] **AC1:** the list paginates (covers SC-01)", num="1.02")
        self.assertNotIn("UNCOVERED-CRITERION", kinds(self.run_on()))

    def test_one_criterion_line_may_cover_several(self):
        self.spec("- [ ] **SC-01:** it loads\n- [ ] **SC-02:** quickly")
        self.task("- [ ] **AC1:** the list renders in 200ms (covers SC-01, SC-02)")
        self.assertNotIn("UNCOVERED-CRITERION", kinds(self.run_on()))

    def test_coverage_is_scoped_to_the_phase(self):
        # SC-01 means a different thing in each spec, so phase 1's task covering SC-01 must not
        # silence phase 2's SC-01. Both phases use the annotation here, which is what isolates
        # scoping from the not-adopted-yet rule above.
        self.spec("- [ ] **SC-01:** the widget list loads")
        self.task("- [ ] **AC1:** the list renders (covers SC-01)", num="1.01")
        write(self.docs, "specs/phase-2_y.md",
              "# Phase 2\n\n| 2.01 | 🟢 COMPLETE | thing |\n\n"
              "## Success Criteria\n\n- [ ] **SC-01:** the cart empties\n"
              "- [ ] **SC-02:** the receipt prints\n")
        write(self.docs, "tasks/phase-2/2.01-thing.md",
              "# Task 2.01: Fixture\n\n**Status:** Complete\n**Depends On:** None\n"
              "**Verification:** `./run-tests`\n\n## Acceptance Criteria\n\n"
              "- [ ] **AC1:** the receipt renders (covers SC-02)\n")
        f = [x for x in self.run_on() if x["finding"] == "UNCOVERED-CRITERION"]
        self.assertEqual([x["where"] for x in f], ["specs/phase-2_y.md"])
        self.assertIn("SC-01", f[0]["detail"])

    # --- a reference that points nowhere -----------------------------------------------
    def test_a_covers_naming_a_criterion_that_does_not_exist(self):
        self.spec("- [ ] **SC-01:** the widget list loads")
        self.task("- [ ] **AC1:** Given a store, when listed, then 200 (covers SC-04)")
        f = [x for x in self.run_on() if x["finding"] == "UNKNOWN-CRITERION-REF"]
        self.assertEqual(len(f), 1)
        self.assertIn("SC-04", f[0]["detail"])

    def test_a_covers_against_a_spec_that_numbers_nothing(self):
        # A dangling pointer is dangling whether the spec has no such number or no numbers at
        # all. The task is the document carrying the ID, and it names something absent.
        self.spec("- [ ] the widget list loads")
        self.task("- [ ] **AC1:** Given a store, when listed, then 200 (covers SC-01)")
        self.assertIn("UNKNOWN-CRITERION-REF", kinds(self.run_on()))

    def test_no_spec_for_the_phase_is_reported_once_not_per_reference(self):
        # NO-SPEC already says the spec is missing. Adding a dangling-reference finding for
        # every annotation in the phase says the same thing several times.
        write(self.docs, "PRD.md", "| 1 | phase one |\n")
        self.task("- [ ] **AC1:** a (covers SC-01)\n- [ ] **AC2:** b (covers SC-02)")
        self.assertNotIn("UNKNOWN-CRITERION-REF", kinds(self.run_on()))

    # --- one number meaning two things -------------------------------------------------
    def test_a_task_reusing_a_criterion_number(self):
        self.spec("- [ ] **SC-01:** it loads")
        self.task("- [ ] **AC1:** the list renders\n- [ ] **AC1:** the list paginates")
        f = [x for x in self.run_on() if x["finding"] == "DUPLICATE-CRITERION-ID"]
        self.assertEqual(len(f), 1)
        self.assertIn("AC1", f[0]["detail"])

    def test_a_spec_reusing_a_success_criterion_number(self):
        self.spec("- [ ] **SC-01:** it loads\n- [ ] **SC-01:** it loads quickly")
        self.task("- [ ] **AC1:** the list renders (covers SC-01)")
        f = [x for x in self.run_on() if x["finding"] == "DUPLICATE-CRITERION-ID"]
        self.assertEqual([x["where"] for x in f], ["specs/phase-1_x.md"])

    def test_the_same_number_in_two_different_tasks_is_normal(self):
        # AC numbers are local to a file. Every task file having an AC1 is the design, not a
        # collision, and a check that said otherwise would fire on every well-formed repo.
        self.spec("- [ ] **SC-01:** it loads",
                  rows="| 1.01 | 🟢 COMPLETE | a |\n| 1.02 | 🟢 COMPLETE | b |")
        self.task("- [ ] **AC1:** renders (covers SC-01)", num="1.01")
        self.task("- [ ] **AC1:** paginates (covers SC-01)", num="1.02")
        self.assertNotIn("DUPLICATE-CRITERION-ID", kinds(self.run_on()))

    # --- scoping -----------------------------------------------------------------------
    def test_acceptance_criteria_elsewhere_in_a_spec_are_not_success_criteria(self):
        # A spec carries per-task Acceptance Criteria as well, numbered AC1 inside each task
        # subsection. Those repeat by design and must not be read as duplicate IDs, nor as
        # success criteria needing coverage.
        write(self.docs, "specs/phase-1_x.md",
              "# Phase 1\n\n| 1.01 | 🟢 COMPLETE | thing |\n\n"
              "## Success Criteria\n\n- [ ] **SC-01:** it loads\n\n"
              "## Tasks\n\n### Task 1.1: A\n\n#### Acceptance Criteria\n\n"
              "- [ ] **AC1:** renders\n\n### Task 1.2: B\n\n#### Acceptance Criteria\n\n"
              "- [ ] **AC1:** paginates\n")
        self.task("- [ ] **AC1:** renders (covers SC-01)")
        self.assertEqual(kinds(self.run_on()), [])

    def test_a_covers_outside_the_criteria_section_is_still_a_reference(self):
        # Prose in Implementation Notes citing SC-02 is a claim about coverage too, and the
        # reader treats it as one.
        self.spec("- [ ] **SC-01:** it loads\n- [ ] **SC-02:** quickly")
        write(self.docs, "tasks/phase-1/1.01-thing.md",
              "# Task 1.01: Fixture\n\n**Status:** Complete\n**Depends On:** None\n"
              "**Verification:** `./run-tests`\n\n"
              "## Implementation Notes\n\n- the cache is what covers SC-02\n\n"
              "## Acceptance Criteria\n\n- [ ] **AC1:** renders (covers SC-01)\n")
        self.assertNotIn("UNCOVERED-CRITERION", kinds(self.run_on()))

    # --- the contract ------------------------------------------------------------------
    def test_nothing_is_edited(self):
        self.spec("- [ ] **SC-01:** it loads")
        p = self.task("- [ ] **AC1:** renders (covers SC-99)")
        before = p.read_text()
        self.run_on()
        self.assertEqual(p.read_text(), before)


class Assumptions(unittest.TestCase):
    """An assumption and a clarification landing on the same criterion.

    What a script can see here is narrow, and saying so precisely is the point. It cannot read two
    prose lines and decide they disagree. What it can see is that a default was recorded for a
    criterion and, separately, a decision was recorded about the same criterion, which is the
    situation where a stale assumption survives a conversation that overtook it. The finding is
    the co-citation; the judgement is the reader's.
    """

    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.docs = os.path.join(self.d.name, "docs")
        os.makedirs(self.docs)

    def tearDown(self):
        self.d.cleanup()

    def run_on(self):
        return sa.analyze(self.docs)

    def doc(self, assumptions="", clarifications="", rel="tasks/phase-1/1.01-thing.md"):
        body = "# Task 1.01: Fixture\n\n**Status:** Complete\n**Depends On:** None\n"
        body += "**Verification:** `./run-tests`\n\n"
        if clarifications:
            body += f"## Clarifications\n\n### Session 2026-09-17\n\n{clarifications}\n\n"
        if assumptions:
            body += f"## Assumptions\n\n{assumptions}\n\n"
        body += "## Acceptance Criteria\n\n- [ ] **AC1:** it renders\n- [ ] **AC2:** it paginates\n"
        return write(self.docs, rel, body)

    def test_an_assumption_and_a_clarification_on_the_same_criterion(self):
        self.doc(assumptions="- **Page size is 50** - no volume given (affects AC2)",
                 clarifications="- Q: what page size? -> A: 20, to fit one screen (AC2)")
        f = [x for x in self.run_on() if x["finding"] == "ASSUMPTION-CONTRADICTED"]
        self.assertEqual(len(f), 1)
        self.assertIn("AC2", f[0]["detail"])

    def test_different_criteria_are_not_a_finding(self):
        # The normal shape of a well-run document: things were assumed, other things were asked.
        self.doc(assumptions="- **Page size is 50** - no volume given (affects AC2)",
                 clarifications="- Q: what does empty render as? -> A: a placeholder row (AC1)")
        self.assertNotIn("ASSUMPTION-CONTRADICTED", kinds(self.run_on()))

    def test_assumptions_with_no_clarifications_are_not_a_finding(self):
        self.doc(assumptions="- **Page size is 50** - no volume given (affects AC2)")
        self.assertNotIn("ASSUMPTION-CONTRADICTED", kinds(self.run_on()))

    def test_clarifications_with_no_assumptions_are_not_a_finding(self):
        self.doc(clarifications="- Q: what page size? -> A: 20 (AC2)")
        self.assertNotIn("ASSUMPTION-CONTRADICTED", kinds(self.run_on()))

    def test_neither_section_citing_an_id_is_not_a_finding(self):
        # Both sections present and both about page size, but nothing ties them to a criterion.
        # Guessing from the prose is exactly what this must not do.
        self.doc(assumptions="- **Page size is 50** - no volume was given",
                 clarifications="- Q: what page size? -> A: 20, to fit one screen")
        self.assertNotIn("ASSUMPTION-CONTRADICTED", kinds(self.run_on()))

    def test_it_reads_a_spec_as_well_as_a_task(self):
        write(self.docs, "specs/phase-1_x.md",
              "# Phase 1\n\n| 1.01 | 🟢 COMPLETE | thing |\n\n"
              "## Success Criteria\n\n- [ ] **SC-01:** it loads\n\n"
              "## Clarifications\n\n### Session 2026-09-17\n\n- Q: how fast? -> A: 200ms (SC-01)\n\n"
              "## Assumptions\n\n- **One second is fine** - nothing said (affects SC-01)\n")
        write(self.docs, "tasks/phase-1/1.01-thing.md",
              "# Task 1.01: Fixture\n\n**Status:** Complete\n**Depends On:** None\n"
              "**Verification:** `./run-tests`\n")
        f = [x for x in self.run_on() if x["finding"] == "ASSUMPTION-CONTRADICTED"]
        self.assertEqual([x["where"] for x in f], ["specs/phase-1_x.md"])

    def test_a_document_with_neither_section_is_untouched(self):
        self.doc()
        self.assertEqual(kinds(self.run_on()), [])


class Cli(unittest.TestCase):
    def test_strict_exits_one_when_something_is_found(self):
        with tempfile.TemporaryDirectory() as d:
            docs = os.path.join(d, "docs")
            write(docs, "tasks/phase-1/1.01-thing.md", task(verif="`echo ok`"))
            self.assertEqual(sa.main([docs, "--quiet", "--strict"]), 1)

    def test_it_exits_zero_without_strict(self):
        with tempfile.TemporaryDirectory() as d:
            docs = os.path.join(d, "docs")
            write(docs, "tasks/phase-1/1.01-thing.md", task(verif="`echo ok`"))
            self.assertEqual(sa.main([docs, "--quiet"]), 0)

    def test_a_missing_directory_exits_two(self):
        self.assertEqual(sa.main(["/nonexistent/docs", "--quiet"]), 2)


if __name__ == "__main__":
    unittest.main()
