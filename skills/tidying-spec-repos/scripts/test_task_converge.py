#!/usr/bin/env python3
"""Tests for task-converge.py. Run: python3 -m unittest discover -s <this dir> -p 'test_*.py'"""
import importlib.util, os, unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("task_converge", os.path.join(_HERE, "task-converge.py"))
tc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tc)


class ParseFilePlan(unittest.TestCase):
    def test_simple_tree_with_root_dir(self):
        doc = """
## File Plan

```
src/api/
├── handlers.rs       (new)
├── mod.rs            (modify)
└── routes.rs
```
"""
        self.assertEqual(
            tc.parse_file_plan(doc),
            [("src/api/handlers.rs", "new"),
             ("src/api/mod.rs", "modify"),
             ("src/api/routes.rs", "")],
        )

    def test_nested_directories(self):
        doc = """
## File Plan

```
crates/core/
├── src/
│   ├── lib.rs        (modify)
│   └── model/
│       └── user.rs   (new)
└── Cargo.toml        (modify)
```
"""
        self.assertEqual(
            tc.parse_file_plan(doc),
            [("crates/core/src/lib.rs", "modify"),
             ("crates/core/src/model/user.rs", "new"),
             ("crates/core/Cargo.toml", "modify")],
        )

    def test_flat_list_without_tree_glyphs(self):
        doc = """
## File Plan

```
src/main.rs (modify)
tests/integration.rs (new)
```
"""
        self.assertEqual(
            tc.parse_file_plan(doc),
            [("src/main.rs", "modify"), ("tests/integration.rs", "new")],
        )

    def test_multiple_root_dirs_in_one_block(self):
        doc = """
## File Plan

```
src/
└── a.rs      (new)
tests/
└── b.rs      (new)
```
"""
        self.assertEqual(
            tc.parse_file_plan(doc),
            [("src/a.rs", "new"), ("tests/b.rs", "new")],
        )

    def test_delete_annotation_is_captured(self):
        doc = """
## File Plan

```
src/
└── legacy.rs   (delete)
```
"""
        self.assertEqual(tc.parse_file_plan(doc), [("src/legacy.rs", "delete")])

    def test_only_reads_the_file_plan_section(self):
        doc = """
## Implementation Notes

```
some/other/thing.rs   (new)
```

## File Plan

```
src/real.rs   (new)
```

## Testing Strategy

```
tests/decoy.rs  (new)
```
"""
        self.assertEqual(tc.parse_file_plan(doc), [("src/real.rs", "new")])

    def test_missing_file_plan_returns_empty(self):
        self.assertEqual(tc.parse_file_plan("# Task 1.01\n\nNo plan here.\n"), [])

    def test_placeholder_template_entries_are_ignored(self):
        doc = """
## File Plan

```
path/to/
├── file-to-create.ext       (new)
└── file-to-modify.ext       (modify)
```
"""
        self.assertEqual(tc.parse_file_plan(doc), [])


class RealWorldBulletFormat(unittest.TestCase):
    """Formats observed in actual task files, not just the template."""

    def test_backticked_bullets_with_freeform_parenthetical(self):
        doc = """
## File Plan

- `CodexReader/Fixtures/SampleSeries.swift` (Sample.art)
- `CodexReader/Fixtures/FixtureArt.swift` (bundled-art cover path)
- `project.yml` (folder resource)
"""
        self.assertEqual(
            tc.parse_file_plan(doc),
            [("CodexReader/Fixtures/SampleSeries.swift", ""),
             ("CodexReader/Fixtures/FixtureArt.swift", ""),
             ("project.yml", "")],
        )

    def test_keyword_extracted_from_compound_parenthetical(self):
        doc = "## File Plan\n\n- `a/b.jpg` (new, 18 images)\n- `c/d.swift` (modify, two call sites)\n"
        self.assertEqual(
            tc.parse_file_plan(doc),
            [("a/b.jpg", "new"), ("c/d.swift", "modify")],
        )

    def test_dash_description_suffix_is_stripped(self):
        doc = "## File Plan\n\n- `CodexReader/Settings/SettingsView.swift` - branch moved into ServersSettingsScreen\n"
        self.assertEqual(
            tc.parse_file_plan(doc),
            [("CodexReader/Settings/SettingsView.swift", "")],
        )

    def test_ellipsis_paths_are_dropped_as_uncheckable(self):
        doc = "## File Plan\n\n- `Packages/Foo/Tests/...` (fixture-based open test)\n- `Packages/Foo/Package.swift` (new)\n"
        self.assertEqual(tc.parse_file_plan(doc), [("Packages/Foo/Package.swift", "new")])

    def test_glob_paths_are_kept(self):
        doc = "## File Plan\n\n- `Packages/Foo/Sources/Foo/*` (new)\n"
        self.assertEqual(tc.parse_file_plan(doc), [("Packages/Foo/Sources/Foo/*", "new")])

    def test_fenced_flat_format_with_column_aligned_annotations(self):
        doc = """
## File Plan

```
CodexReader/Search/SearchModel.swift                       (modify)
CodexReaderTests/SearchModelTests.swift                    (new)
```
"""
        self.assertEqual(
            tc.parse_file_plan(doc),
            [("CodexReader/Search/SearchModel.swift", "modify"),
             ("CodexReaderTests/SearchModelTests.swift", "new")],
        )


class AnnotationFollowedByProse(unittest.TestCase):
    """The dominant real format: column-aligned (new) with a trailing comment."""

    def test_annotation_midline_with_trailing_prose(self):
        doc = """
## File Plan

```
CodexReader.xcodeproj                 (new)
CodexReader/
├── App.swift                         (new)  app entry point
└── Navigation/RootView.swift         (new)  navigation shell, empty for now
Makefile                              (new)  build, test, format, lint
```
"""
        self.assertEqual(
            tc.parse_file_plan(doc),
            [("CodexReader.xcodeproj", "new"),
             ("CodexReader/App.swift", "new"),
             ("CodexReader/Navigation/RootView.swift", "new"),
             ("Makefile", "new")],
        )

    def test_root_dir_line_carrying_annotation_still_sets_prefix(self):
        doc = """
## File Plan

```
Spikes/ArchiveSpike/                  (new)  throwaway harness, not shipped
├── main.swift                        (new)  run both libraries over a directory
└── README.md                         (new)  how to run it
```
"""
        self.assertEqual(
            tc.parse_file_plan(doc),
            [("Spikes/ArchiveSpike/main.swift", "new"),
             ("Spikes/ArchiveSpike/README.md", "new")],
        )

    def test_dated_filename_placeholder_is_dropped(self):
        doc = """
## File Plan

```
.specs/docs/plans/
└── YYYY-MM-DD-archive-spike-results.md   (new)  the decision and its evidence
```
"""
        self.assertEqual(tc.parse_file_plan(doc), [])


class StaleFilePlan(unittest.TestCase):
    """A file that moved is stale bookkeeping, not unbuilt work."""

    def test_all_gaps_explained_by_moves_is_stale_plan_not_unbuilt(self):
        ev = tc.Evidence(satisfied=1, total=2, missing=["a/X.swift"],
                         moved=[("a/X.swift", "b/X.swift")])
        self.assertEqual(tc.classify("🟢 Complete", ev), "STALE-FILE-PLAN")

    def test_a_genuinely_absent_file_still_reads_unbuilt(self):
        ev = tc.Evidence(satisfied=1, total=3, missing=["a/X.swift", "a/Y.swift"],
                         moved=[("a/X.swift", "b/X.swift")])
        self.assertEqual(tc.classify("🟢 Complete", ev), "CLAIMED-UNBUILT")

    def test_moves_do_not_upgrade_an_unclaimed_task(self):
        """A same-basename twin is a hint for a human, not proof of completion.
        An unclaimed task stays unclaimed; the move is surfaced in the report."""
        ev = tc.Evidence(satisfied=0, total=1, missing=["a/X.swift"],
                         moved=[("a/X.swift", "b/X.swift")])
        self.assertEqual(tc.classify("🔵 NOT STARTED", ev), "NOT-STARTED")


class FindMoved(unittest.TestCase):
    def test_unique_basename_match_is_reported(self):
        tracked = {"CodexReader/Admin/LibraryListView.swift", "other/Thing.swift"}
        self.assertEqual(
            tc.find_moved("CodexReader/Library/LibraryListView.swift", tracked),
            "CodexReader/Admin/LibraryListView.swift",
        )

    def test_relocated_subtree_is_found_by_suffix(self):
        """A whole tree moving under a new root is the common case, and the
        basename alone is often ambiguous ('client.ts')."""
        tracked = {"components/orchestrator/src/db/client.ts",
                   "web/src/api/client.ts"}
        self.assertEqual(
            tc.find_moved("orchestrator/src/db/client.ts", tracked),
            "components/orchestrator/src/db/client.ts",
        )

    def test_suffix_match_wins_over_ambiguous_basename(self):
        tracked = {"a/deep/mod.rs", "b/mod.rs", "c/mod.rs"}
        self.assertEqual(tc.find_moved("deep/mod.rs", tracked), "a/deep/mod.rs")

    def test_no_match_returns_none(self):
        self.assertIsNone(tc.find_moved("a/Nope.swift", {"b/Other.swift"}))

    def test_ambiguous_match_returns_none(self):
        tracked = {"a/mod.rs", "b/mod.rs"}
        self.assertIsNone(tc.find_moved("c/mod.rs", tracked))


class Classify(unittest.TestCase):
    def ev(self, satisfied, total):
        return tc.Evidence(satisfied=satisfied, total=total, missing=[])

    def test_claimed_done_and_all_files_present_is_confirmed(self):
        self.assertEqual(tc.classify("🟢 Complete", self.ev(3, 3)), "CONFIRMED")

    def test_claimed_done_with_missing_files_is_claimed_unbuilt(self):
        self.assertEqual(tc.classify("Complete", self.ev(1, 3)), "CLAIMED-UNBUILT")

    def test_not_claimed_but_all_present_is_done_unclaimed(self):
        self.assertEqual(tc.classify("🔵 NOT STARTED", self.ev(2, 2)), "DONE-UNCLAIMED")

    def test_not_claimed_and_partially_present_is_partial(self):
        self.assertEqual(tc.classify("🟡 IN PROGRESS", self.ev(1, 3)), "PARTIAL")

    def test_not_claimed_and_nothing_present_is_not_started(self):
        self.assertEqual(tc.classify("Draft", self.ev(0, 2)), "NOT-STARTED")

    def test_no_file_plan_is_unjudgeable(self):
        self.assertEqual(tc.classify("Complete", self.ev(0, 0)), "NO-FILE-PLAN")

    def test_dropped_tasks_are_excluded_from_judgement(self):
        self.assertEqual(tc.classify("⏸️ DROPPED", self.ev(0, 2)), "DROPPED")


class SatisfiedPredicate(unittest.TestCase):
    """A (delete) entry is satisfied by ABSENCE; every other entry by presence."""

    def test_new_file_satisfied_when_present(self):
        self.assertTrue(tc.entry_satisfied("new", exists=True))
        self.assertFalse(tc.entry_satisfied("new", exists=False))

    def test_delete_file_satisfied_when_absent(self):
        self.assertTrue(tc.entry_satisfied("delete", exists=False))
        self.assertFalse(tc.entry_satisfied("delete", exists=True))

    def test_unannotated_file_satisfied_when_present(self):
        self.assertTrue(tc.entry_satisfied("", exists=True))


class TaskNumber(unittest.TestCase):
    def test_extracts_dotted_number_from_filename(self):
        self.assertEqual(tc.task_number("3.11-series-download-queue.md"), (3, 11))

    def test_handles_zero_padded_phase(self):
        self.assertEqual(tc.task_number("12.04-thing.md"), (12, 4))

    def test_unparseable_sorts_last(self):
        self.assertEqual(tc.task_number("README.md"), (10**6, 0))



class NoFilesByDesign(unittest.TestCase):
    """A File Plan that declares the task changes no files is correct, not missing.

    Measured 2026-09-16: of nine files this tool reported as NO-FILE-PLAN in its own repository,
    five had the section and said "**None.** This task changes no files. It is entirely
    verification." Two subagents sent to backfill them independently reported the premise was
    wrong. Reporting a correct document as a fault sends people to fix what is already right.
    """

    def verdict_for(self, body):
        return tc.classify("Complete", tc.Evidence(0, 0, [], []), body)

    def test_a_file_plan_declaring_no_files_is_by_design(self):
        body = ("# Task 1.01: Verify\n\n**Status:** Complete\n\n## File Plan\n\n"
                "**None.** This task changes no files. It is entirely verification.\n\n"
                "## Implementation Notes\n")
        self.assertEqual(self.verdict_for(body), "NO-FILES-BY-DESIGN")

    def test_prose_instead_of_a_tree_is_still_by_design(self):
        body = ("# Task 1.01: Measure\n\n**Status:** Complete\n\n## File Plan\n\n"
                "No product files. The output is a recorded command sequence and its result.\n\n"
                "## Implementation Notes\n")
        self.assertEqual(self.verdict_for(body), "NO-FILES-BY-DESIGN")

    def test_no_section_at_all_is_still_a_fault(self):
        body = ("# Task 1.01: Build\n\n**Status:** Complete\n\n## Implementation Notes\n"
                "Did some work.\n")
        self.assertEqual(self.verdict_for(body), "NO-FILE-PLAN")

    def test_has_file_plan_section_reads_any_heading_level(self):
        for h in ("## File Plan", "### File Plan", "#### file plan"):
            with self.subTest(h=h):
                self.assertTrue(tc.has_file_plan_section(f"# T\n\n{h}\n\nNone.\n"))
        self.assertFalse(tc.has_file_plan_section("# T\n\n## Scope\n\nNone.\n"))


class WrappedAnnotations(unittest.TestCase):
    """A File Plan written as an aligned tree wraps long annotations onto a second line.

    Found 2026-09-16: plugins/delegation/README.md was reported missing while it existed, because
    its annotation wrapped, so the path kept an unterminated "(new - 306 lines..." and the
    continuation line became an entry of its own. Two false CLAIMED-UNBUILT entries from one
    correct document.
    """

    PLAN = (
        "# T\n\n## File Plan\n\n```\n"
        "plugins/delegation/README.md      (new - 306 lines, the tiering rationale;\n"
        "                                   NOT under agents/, see the finding)\n"
        "scripts/test-hooks.sh             (modify)\n"
        "```\n\n## Implementation Notes\n"
    )

    def test_the_wrapped_path_is_recovered(self):
        paths = [p for p, _a in tc.parse_file_plan(self.PLAN)]
        self.assertIn("plugins/delegation/README.md", paths)

    def test_the_continuation_line_is_not_an_entry(self):
        paths = [p for p, _a in tc.parse_file_plan(self.PLAN)]
        self.assertFalse([p for p in paths if p.startswith("NOT under")], paths)

    def test_the_following_entry_still_parses(self):
        paths = [p for p, _a in tc.parse_file_plan(self.PLAN)]
        self.assertIn("scripts/test-hooks.sh", paths)

    def test_a_plan_with_no_wrapping_is_unchanged(self):
        plan = ("# T\n\n## File Plan\n\n```\na.md   (new)\nb.md   (modify)\n```\n\n## X\n")
        self.assertEqual([p for p, _a in tc.parse_file_plan(plan)], ["a.md", "b.md"])

if __name__ == "__main__":
    unittest.main(verbosity=2)


class Criteria(unittest.TestCase):
    """The numbered acceptance criteria, carried into the JSON so a finding can cite one.

    This tool does not judge whether a criterion is met; reading a File Plan cannot tell you
    that. What it can do is put the criteria where the caller already has the task's evidence,
    so a behavioural pass has something to iterate over and a finding has something to name.
    """

    def test_numbered_criteria_are_parsed_in_order(self):
        doc = """
## Acceptance Criteria

- [x] **AC1:** Given a store, when listed, then 200 (covers SC-02)
- [ ] **AC2:** the list paginates
"""
        self.assertEqual(
            tc.parse_criteria(doc),
            [{"id": "AC1", "checked": True,
              "text": "Given a store, when listed, then 200 (covers SC-02)",
              "covers": ["SC-02"]},
             {"id": "AC2", "checked": False, "text": "the list paginates", "covers": []}],
        )

    def test_a_criterion_may_cover_several(self):
        doc = "## Acceptance Criteria\n\n- [ ] **AC1:** fast and correct (covers SC-01, SC-03)\n"
        self.assertEqual(tc.parse_criteria(doc)[0]["covers"], ["SC-01", "SC-03"])

    def test_unnumbered_criteria_yield_nothing(self):
        # Every task file written before IDs existed. The list is empty rather than invented,
        # so a caller iterating it does nothing instead of doing something wrong.
        doc = "## Acceptance Criteria\n\n- [ ] the list renders\n- [x] it paginates\n"
        self.assertEqual(tc.parse_criteria(doc), [])

    def test_no_acceptance_criteria_section_at_all(self):
        self.assertEqual(tc.parse_criteria("# Task 1.01\n\n**Status:** Complete\n"), [])

    def test_a_later_section_is_not_swept_in(self):
        doc = """
## Acceptance Criteria

- [ ] **AC1:** the list renders

## Testing Strategy

- [ ] **AC9:** not a criterion, and not this task's
"""
        self.assertEqual([c["id"] for c in tc.parse_criteria(doc)], ["AC1"])

    def test_wrapped_criterion_text_is_joined(self):
        doc = """
## Acceptance Criteria

- [ ] **AC1:** Given three widgets in the store, when `GET /widgets` is called,
      then the response is 200 (covers SC-01)
"""
        c = tc.parse_criteria(doc)[0]
        self.assertIn("then the response is 200", c["text"])
        self.assertEqual(c["covers"], ["SC-01"])


class RecordedDeviations(unittest.TestCase):
    """A File Plan path that moved or was dropped on purpose, and said so.

    Without this, a deliberate departure is indistinguishable from a lie. The File Plan says
    `app/old.py`, the file is not there, and the task is marked Complete: that is CLAIMED-UNBUILT,
    which is the finding reserved for a task claiming work it did not do. Recording the departure
    in the task's own Progress Notes is what separates the two, and it has to be recorded at the
    time, by whoever moved the file.

    The asymmetry matters more than the feature. An unrecorded move must still be flagged, or the
    finding stops meaning anything.
    """

    def plan(self, entries, deviations=None):
        doc = "## File Plan\n\n```\n" + "\n".join(entries) + "\n```\n"
        if deviations:
            doc += "\n## Progress Notes\n\n### Deviations\n\n" + deviations + "\n"
        return doc

    def test_a_recorded_move(self):
        doc = self.plan(["app/old.py       (new)"],
                        "- `app/old.py` -> `app/new.py`, moved when the package was renamed")
        self.assertEqual(tc.parse_deviations(doc), {"app/old.py": "moved"})

    def test_a_recorded_drop(self):
        doc = self.plan(["app/cache.py     (new)"],
                        "- `app/cache.py` dropped: the query turned out to be fast enough")
        self.assertEqual(tc.parse_deviations(doc), {"app/cache.py": "dropped"})

    def test_several_entries(self):
        doc = self.plan(["a.py (new)", "b.py (new)"],
                        "- `a.py` -> `x.py`, renamed\n- `b.py` dropped: not needed")
        self.assertEqual(tc.parse_deviations(doc), {"a.py": "moved", "b.py": "dropped"})

    def test_no_deviations_section(self):
        self.assertEqual(tc.parse_deviations(self.plan(["a.py (new)"])), {})

    def test_a_line_naming_no_path_is_ignored(self):
        # Prose under the heading is common and must not be read as a path.
        doc = self.plan(["a.py (new)"], "- the layout changed a lot during this task")
        self.assertEqual(tc.parse_deviations(doc), {})

    def test_a_recorded_path_is_not_claimed_unbuilt(self):
        doc = self.plan(["app/old.py       (new)"],
                        "- `app/old.py` -> `app/new.py`, moved when the package was renamed")
        ev = tc.Evidence(satisfied=0, total=1, missing=["app/old.py"])
        self.assertEqual(tc.classify("🟢 Complete", ev, doc), "DEVIATION-RECORDED")

    def test_an_unrecorded_move_is_still_flagged(self):
        # The whole check turns on this. If recording were optional in effect, the verdict would
        # be a formality rather than evidence.
        doc = self.plan(["app/old.py       (new)"])
        ev = tc.Evidence(satisfied=0, total=1, missing=["app/old.py"])
        self.assertEqual(tc.classify("🟢 Complete", ev, doc), "CLAIMED-UNBUILT")

    def test_one_recorded_and_one_not_is_still_flagged(self):
        # Partial accounting is not accounting. A task that explains one of its two missing files
        # has an unexplained missing file.
        doc = self.plan(["a.py (new)", "b.py (new)"], "- `a.py` dropped: not needed")
        ev = tc.Evidence(satisfied=0, total=2, missing=["a.py", "b.py"])
        self.assertEqual(tc.classify("🟢 Complete", ev, doc), "CLAIMED-UNBUILT")

    def test_a_missing_entry_with_its_annotation_still_matches(self):
        # `missing` carries the annotation appended: "app/old.py (new)". The recorded path is
        # bare, and the two have to meet.
        doc = self.plan(["app/old.py       (new)"], "- `app/old.py` dropped: superseded")
        ev = tc.Evidence(satisfied=0, total=1, missing=["app/old.py (new)"])
        self.assertEqual(tc.classify("🟢 Complete", ev, doc), "DEVIATION-RECORDED")

    def test_a_deviation_does_not_rescue_an_incomplete_task(self):
        # Recording a departure says where a file went, not that the work is done.
        doc = self.plan(["a.py (new)"], "- `a.py` dropped: not needed")
        ev = tc.Evidence(satisfied=0, total=1, missing=["a.py"])
        self.assertEqual(tc.classify("Not Started", ev, doc), "NOT-STARTED")


class ReportCoverage(unittest.TestCase):
    """Every verdict classify can return must be printable.

    Found by adding DEVIATION-RECORDED to the print order and forgetting the blurb table: the
    reporter raised KeyError on a real repo while the JSON was correct throughout. The second
    case is the older half of the same gap, where NO-FILES-BY-DESIGN was counted in the summary
    line and never printed, so nine tasks were invisible in the report that people actually read.
    """

    VERDICTS = {"CONFIRMED", "CLAIMED-UNBUILT", "DONE-UNCLAIMED", "PARTIAL", "NOT-STARTED",
                "NO-FILE-PLAN", "NO-FILES-BY-DESIGN", "DEVIATION-RECORDED", "DROPPED",
                "STALE-FILE-PLAN"}

    def test_every_verdict_is_printed(self):
        self.assertEqual(self.VERDICTS - set(tc.ORDER), set())

    def test_every_printed_verdict_has_a_blurb(self):
        self.assertEqual([v for v in tc.ORDER if v not in tc.BLURB], [])
