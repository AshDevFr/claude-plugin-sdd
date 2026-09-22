#!/usr/bin/env python3
"""Grade one run's result against a case's graders, or lint the graders themselves.

    grade.py <case.json> <run.json> [repo]   grade a run
    grade.py --lint <case.json>...           report graders that cannot fail
    grade.py --selftest                      unit checks for the lint

Python rather than grep because the patterns use inline flags like (?i) and (?s),
which are PCRE features. macOS grep has no -P at all, so a grep-based grader
silently reports every must_match as missing and every must_not_match as ok: the
second of those is a false green, which is the failure mode worth avoiding.

Prints one TSV line per grader: id, verdict, detail. Exits 1 if any grader failed.
"""
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent


# ---- grading -------------------------------------------------------------------------------
def reply_text(case, run):
    """What the run printed, after the case's extract rule."""
    raw = run.get("result") or ""
    mode = case.get("extract", "raw")
    if mode == "fenced":
        m = re.search(r"```[^\n]*\n(.*?)```", raw, re.S)
        if not m:
            print("extract\tmissing\tno fenced code block in the output")
            sys.exit(1)
        return m.group(1)
    return raw


def artefact_text(case, repo):
    """What the run wrote. Exits when the file the case names is absent, which is a real failure.

    The path may contain a glob. Commands that create a dated directory write today's date, so a
    case pinning the date it was authored on passes exactly once: `bug-assess` was written on
    2026-09-17, and failed all three trials on 2026-09-22 because the run correctly wrote
    `2026-09-22-discount-zero-division`. A glob is the fix; an ambiguous one is refused, because
    silently grading the first of several matches would hide a command writing two directories.
    """
    artefact = case["artefact"]
    root = pathlib.Path(repo)
    if any(c in artefact for c in "*?["):
        matches = sorted(p for p in root.glob(artefact) if p.is_file())
        if not matches:
            print(f"artefact\tmissing\tthe run did not write anything matching {artefact}")
            sys.exit(1)
        if len(matches) > 1:
            names = ", ".join(str(m.relative_to(root)) for m in matches)
            print(f"artefact\tambiguous\t{artefact} matched {len(matches)} files: {names}")
            sys.exit(1)
        return matches[0].read_text()
    f = root / artefact
    if not f.is_file():
        print(f"artefact\tmissing\tthe run did not write {artefact}")
        sys.exit(1)
    return f.read_text()


def extract(case, run, repo):
    """The text the graders see: the artefact the run wrote, or what it printed."""
    raw = run.get("result") or ""

    # Grade the artefact, not the transcript. The first baseline run "found a bug" that was
    # entirely the model's commentary after the commit message: phrases like "all four tests
    # will fail" and "I left out the Co-Authored-By trailer" tripped graders whose rules are
    # about the message itself. Both were compliance, read as violation.
    #
    # extract: "fenced" takes the first fenced code block, which the command is now required
    # to print the message in. No fence means no gradeable artefact, which is a real failure.
    # Preferred: grade the file the run produced, not anything it printed. A markdown
    # artefact usually contains fenced code blocks of its own, so asking for it inside a
    # fence and extracting the first one truncates it at the first nested fence: a task
    # file of 5,436 characters arrived as 1,799 and three graders failed on sections that
    # were present. Reading the file sidesteps the whole problem.
    artefact = case.get("artefact")
    if artefact:
        f = pathlib.Path(repo) / artefact
        if not f.is_file():
            print(f"artefact\tmissing\tthe run did not write {artefact}")
            sys.exit(1)
        return f.read_text()

    mode = case.get("extract", "raw")
    if mode == "fenced":
        m = re.search(r"```[^\n]*\n(.*?)```", raw, re.S)
        if not m:
            print("extract\tmissing\tno fenced code block in the output")
            sys.exit(1)
        return m.group(1)
    return raw


def grade(case_path, run_path, repo="."):
    """Grade every grader against its own source.

    A case with an artefact grades against the file by default, because that is the thing the
    run produced. One command can be worth checking in both places at once: /sdd:implement is
    graded on what it says it found and on the Status it actually wrote, and a grader says which
    it wants with "source": "reply" or "artefact".
    """
    case = json.load(open(case_path))
    run = json.load(open(run_path))
    default_source = "artefact" if case.get("artefact") else "reply"
    texts = {}

    def text_for(source):
        if source not in texts:
            texts[source] = (artefact_text(case, repo) if source == "artefact"
                             else reply_text(case, run))
        return texts[source]

    failed = False
    for g in case["graders"]:
        text = text_for(g.get("source", default_source))
        gid, verdict, detail = g["id"], "ok", ""
        pos, neg = g.get("must_match"), g.get("must_not_match")
        if pos is not None and not re.search(pos, text):
            verdict, detail = "missing", f"no match for /{pos}/"
        if verdict == "ok" and neg is not None:
            m = re.search(neg, text)
            if m:
                verdict, detail = "forbidden", f"found {m.group(0)!r}"
        if verdict != "ok":
            failed = True
        print(f"{gid}\t{verdict}\t{detail}")
    return 1 if failed else 0


# ---- the vacuity lint ------------------------------------------------------------------------
# A grader that cannot fail is worse than no grader: it reports green forever and is counted as
# coverage. quick.json's `verification-actually-ran` matched (?i)(ok|passed|version) on a case
# whose prompt asks for a "version" key, so no entry a reasonable run could write would fail it.
# The two ways a must_match comes to be vacuous are that the pattern is already in the prompt,
# which the model will echo, or already in the artefact before the run touches it.
def prerun_artefact(case):
    """The artefact's contents as the fixture leaves them, before any model runs. None if absent."""
    artefact, fixture = case.get("artefact"), case.get("fixture")
    if not artefact or not fixture:
        return None
    script = HERE / "fixtures" / fixture
    if not script.is_file():
        return None
    with tempfile.TemporaryDirectory() as d:
        subprocess.run(["git", "-C", d, "init", "-q"], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["bash", str(script), d], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        f = pathlib.Path(d) / artefact
        return f.read_text() if f.is_file() else None


def _compile_error(pattern):
    """The message if this pattern cannot compile, else None."""
    try:
        re.compile(pattern)
        return None
    except re.error as e:
        return str(e)


def lint_case(case_path):
    """Report graders that cannot fail. Returns a list of (grader_id, verdict, detail)."""
    case = json.load(open(case_path))
    prompt = case.get("prompt", "")
    pre = prerun_artefact(case)
    out = []

    for g in case["graders"]:
        gid = g["id"]

        # A pattern the engine refuses is a grader that cannot run, which the suite would
        # otherwise discover mid-run as a traceback. Found by writing one: (?i) is a global
        # flag and Python refuses it anywhere but the start.
        broken = next((f"{k} is not a usable regex: {e}"
                       for k in ("must_match", "must_not_match") if g.get(k) is not None
                       for e in [_compile_error(g[k])] if e), None)
        if broken:
            out.append((gid, "broken", broken))
            continue
        if "lint_ignore" in g:
            out.append((gid, "ignored", g["lint_ignore"]))
            continue

        source = g.get("source", "artefact" if case.get("artefact") else "reply")
        pre_here = pre if source == "artefact" else None
        pos, neg = g.get("must_match"), g.get("must_not_match")
        if pos is not None:
            m = re.search(pos, prompt)
            if m:
                out.append((gid, "vacuous",
                            f"must_match /{pos}/ already matches the case prompt at {m.group(0)!r}"))
                continue
            if pre_here is not None:
                m = re.search(pos, pre_here)
                if m:
                    out.append((gid, "vacuous",
                                f"must_match /{pos}/ already matches the artefact before the run"
                                f" at {m.group(0)!r}"))
                    continue

        if neg is not None:
            example = g.get("violating_example")
            if example is not None and not re.search(neg, example):
                out.append((gid, "broken",
                            f"must_not_match /{neg}/ does not catch its own violating_example"))
                continue
            if pre_here is not None:
                m = re.search(neg, pre_here)
                if m:
                    out.append((gid, "pre-violating",
                                f"must_not_match /{neg}/ already matches the artefact before the"
                                f" run at {m.group(0)!r}"))
                    continue

        out.append((gid, "ok", ""))
    return out


def lint(paths):
    bad = 0
    for path in paths:
        rows = lint_case(path)
        problems = [r for r in rows if r[1] in ("vacuous", "broken", "pre-violating")]
        name = os.path.basename(path)
        if problems:
            bad += len(problems)
            for gid, verdict, detail in problems:
                print(f"{name}\t{gid}\t{verdict}\t{detail}")
    return 1 if bad else 0


# ---- self-test ---------------------------------------------------------------------------------
def selftest():
    """Synthetic cases only, so fixing a real case never breaks the check that found it."""
    failures = []

    def check(label, got, want):
        if got != want:
            failures.append(f"{label}: expected {want!r}, got {got!r}")

    def verdicts(case):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump(case, f)
            path = f.name
        try:
            return {gid: v for gid, v, _ in lint_case(path)}
        finally:
            os.unlink(path)

    # a must_match the prompt already contains cannot fail
    v = verdicts({"prompt": "add a version key to healthz", "graders": [
        {"id": "echoes-prompt", "must_match": "(?i)version"},
        {"id": "real", "must_match": "(?m)^## 20\\d\\d"}]})
    check("pattern in prompt", v["echoes-prompt"], "vacuous")
    check("pattern not in prompt", v["real"], "ok")

    # lint_ignore is an explicit, reviewable escape hatch, not a silent skip
    v = verdicts({"prompt": "version", "graders": [
        {"id": "waived", "must_match": "(?i)version", "lint_ignore": "the word is the artefact"}]})
    check("lint_ignore", v["waived"], "ignored")

    # a must_not_match that cannot catch its own example is broken
    v = verdicts({"prompt": "x", "graders": [
        {"id": "toothless", "must_not_match": "co-authored-by",
         "violating_example": "Co-Authored-By: someone"},
        {"id": "sound", "must_not_match": "(?i)co-authored-by",
         "violating_example": "Co-Authored-By: someone"}]})
    check("case-sensitive miss", v["toothless"], "broken")
    check("catches its example", v["sound"], "ok")

    for f in failures:
        print(f"selftest\tFAIL\t{f}")
    print(f"selftest\t{'FAIL' if failures else 'ok'}\t{len(failures)} failure(s)")
    return 1 if failures else 0


# ---- entry -------------------------------------------------------------------------------------
if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--selftest":
        sys.exit(selftest())
    if args and args[0] == "--lint":
        if len(args) < 2:
            print("usage: grade.py --lint <case.json>...", file=sys.stderr)
            sys.exit(2)
        sys.exit(lint(args[1:]))
    if len(args) < 2:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)
    sys.exit(grade(args[0], args[1], args[2] if len(args) > 2 else "."))
