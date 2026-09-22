#!/usr/bin/env python3
"""Check a spec tree against itself, before anyone implements from it.

Usage:
  spec-analyze.py [DOCS_DIR] [--json [PATH]] [--quiet] [--strict]

DOCS_DIR defaults to the first of .specs/docs, docs that exists.

This tool is READ-ONLY, like task-converge.py beside it. It reports and proposes; it never edits
a document. A spec is a claim about what will be built, and an inconsistency between two claims
is a question for a person, not something to resolve by picking one.

`task-converge.py` asks whether the code matches the documents. This asks whether the documents
match *each other*, which is the cheaper question and the one worth asking first: an implementer
dispatched against a spec whose tasks do not exist wastes a session discovering it.

Findings, in the order they cost you:

  NO-SPEC             a PRD phase with no phase spec file
  ORPHAN-TASK         a task file no spec's Tasks Summary mentions
  MISSING-TASK        a Tasks Summary row with no task file
  STATUS-DISAGREE     a summary row and its task file give different statuses
  DEP-MISSING         Depends On names a task that does not exist
  DEP-INCOMPLETE      an In Progress task depends on one that is not Complete
  NO-VERIFICATION     a task file with no **Verification:** field
  PLACEHOLDER-VERIF   its Verification is still the template's bracketed text
  WEAK-VERIF          its Verification cannot fail: echo, true, :, or a bare cd
  CLARIFICATION       an unresolved [NEEDS CLARIFICATION: ...] marker
  UNCOVERED-CRITERION a spec success criterion no task claims to cover
  UNKNOWN-CRITERION-REF  a `covers` annotation naming a criterion that does not exist
  DUPLICATE-CRITERION-ID one criterion number used twice in the same document
  ASSUMPTION-CONTRADICTED an assumption and a clarification that name the same criterion

The last three read the optional criterion IDs (`SC-01` in a spec's Success Criteria, `AC1` in a
task's Acceptance Criteria) and the `(covers SC-NN)` annotations that connect them. Coverage is
declared, never inferred from prose: a criterion whose text obviously matches a task's is still
uncovered until something says so. Inferring it would turn a wording coincidence into a claim
that the work is accounted for, which is the claim this whole tool exists to doubt.

Documents that carry no IDs produce none of these three, so a tree written before they existed
reports exactly what it reported before.

ASSUMPTION-CONTRADICTED is narrower than its name, deliberately. Nothing here reads two prose lines
and decides they disagree; what it sees is that a default was recorded for a criterion under
`## Assumptions` and a decision was recorded about the same criterion under `## Clarifications`.
That is the shape a stale assumption takes after a conversation overtakes it. Whether the answer
actually overturned the default is the reader's call, which is why the finding names both lines
rather than asserting a contradiction.

Exit status is 0 unless --strict, which exits 1 when anything was found.
"""

import argparse
import json
import os
import re
import sys

STATUS_RX = re.compile(r"^\s*(?:[-*]\s+)?\*\*Status:?\*\*:?\s*(.*?)\s*$", re.M)
VERIF_RX = re.compile(r"^\*\*Verification:\*\*\s*`(.*)`\s*$", re.M)
DEPENDS_RX = re.compile(r"^\*\*Depends On:\*\*\s*(.*?)\s*$", re.M)
CLARIFY_RX = re.compile(r"\[NEEDS CLARIFICATION:([^\]]*)\]")
TASK_NUM_RX = re.compile(r"(\d+)\.(\d+)")
# A Tasks Summary row: | 1.01 | 🟢 COMPLETE | description |
ROW_RX = re.compile(r"^\|\s*(\d+\.\d+)\s*\|\s*([^|]*?)\s*\|", re.M)

# A numbered criterion: `- [ ] **SC-01:** ...` or `- [ ] **AC1:** ...`. The colon lives inside the
# bold in the templates, so it is optional here rather than assumed either way.
CRITERION_RX = re.compile(r"^\s*[-*]\s*\[[ xX]\]\s*\*\*((?:SC|FR)-\d+|AC\d+):?\*\*", re.M)
# `(covers SC-01, SC-03)`, and the same claim made in prose without the parentheses. Both are a
# reader telling you which requirement a piece of work answers to.
COVERS_RX = re.compile(
    r"\bcovers\s+((?:SC|FR)-\d+(?:\s*(?:,|and)\s*(?:SC|FR)-\d+)*)", re.I)
ID_RX = re.compile(r"(?:SC|FR)-\d+", re.I)
PHASE_IN_NAME_RX = re.compile(r"phase-(\d+)")
# Any criterion ID cited in a line of prose, as `(affects AC2)` or a trailing `(SC-01)`.
CITED_ID_RX = re.compile(r"\b((?:SC|FR)-\d+|AC\d+)\b")

# Commands that pass whatever the work did. The Stop hook proves a command ran; only this can
# suggest the command was never capable of failing.
WEAK_RX = re.compile(r"^\s*(echo\b|true\b|:\s*$|cd\s+\S+\s*$|printf\b|ls\b|cat\b)", re.I)


def norm_status(text):
    """Complete / in-progress / not-started / blocked, from prose or emoji.

    Order matters, and the trap is "Not Started": it contains the word "started", so a naive
    in-progress test claims a queued task is underway. The negative forms are checked first.
    """
    t = (text or "").lower()
    if re.search(r"\b(not started|not-started|todo|to do|queued|pending|draft|planning|planned)\b", t):
        return "not-started"
    if any(e in t for e in ("🟢", "✅")) or re.search(r"\b(complete|done|verified|shipped)\b", t):
        return "complete"
    if "🔴" in t or "blocked" in t:
        return "blocked"
    if "🟡" in t or re.search(r"\b(in progress|in-progress|wip|started|underway)\b", t):
        return "in-progress"
    return "not-started"


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def find_docs(given):
    if given:
        return given
    for c in (".specs/docs", "docs"):
        if os.path.isdir(c):
            return c
    return None


def task_files(docs):
    """Every task file, keyed by its N.MM number."""
    out = {}
    root = os.path.join(docs, "tasks")
    for dirpath, _dirs, names in os.walk(root):
        for n in sorted(names):
            if not n.endswith(".md"):
                continue
            m = TASK_NUM_RX.match(n)
            if m:
                out[f"{int(m.group(1))}.{m.group(2)}"] = os.path.join(dirpath, n)
    return out


def spec_files(docs):
    d = os.path.join(docs, "specs")
    if not os.path.isdir(d):
        return []
    return [os.path.join(d, n) for n in sorted(os.listdir(d)) if n.endswith(".md")]


def section(text, name):
    """The body under a heading of any level, to the next heading of the same or higher level.

    Scoping is what keeps a spec's per-task `#### Acceptance Criteria` out of its `## Success
    Criteria`. Those per-task blocks each start again at AC1 by design, so a document-wide scan
    would report a duplicate ID on every well-formed spec.
    """
    m = re.search(r"^(#{1,6})\s+%s\s*$" % re.escape(name), text, re.M | re.I)
    if not m:
        return ""
    depth = len(m.group(1))
    rest = text[m.end():]
    nxt = re.search(r"^#{1,%d}\s+\S" % depth, rest, re.M)
    return rest[:nxt.start()] if nxt else rest


def criterion_ids(text, name):
    """Every numbered criterion under the named heading, in document order, with duplicates."""
    return [m.group(1).upper() for m in CRITERION_RX.finditer(section(text, name))]


def covers_refs(text):
    """Every criterion this document claims to cover, anywhere in it."""
    out = []
    for m in COVERS_RX.finditer(text):
        out.extend(i.upper() for i in ID_RX.findall(m.group(1)))
    return out


def cited_by_line(text, name):
    """{criterion id: the line citing it} for every line under the named heading."""
    out = {}
    for line in section(text, name).splitlines():
        if not line.strip().startswith(("-", "*")):
            continue
        for cid in CITED_ID_RX.findall(line):
            out.setdefault(cid.upper(), line.strip())
    return out


def phase_of_spec(path):
    m = PHASE_IN_NAME_RX.search(os.path.basename(path))
    return int(m.group(1)) if m else None


def analyze(docs):
    findings = []

    def add(kind, where, detail):
        findings.append({"finding": kind, "where": where, "detail": detail})

    tasks = task_files(docs)
    specs = spec_files(docs)

    # A PRD phase with no spec. Phase numbers come from the spec filenames that do exist.
    prd = os.path.join(docs, "PRD.md")
    if os.path.isfile(prd):
        text = read(prd)
        have = set()
        for s in specs:
            m = re.search(r"phase-(\d+)", os.path.basename(s))
            if m:
                have.add(int(m.group(1)))
        for m in re.finditer(r"^\|\s*(\d+)\s*\|", text, re.M):
            n = int(m.group(1))
            if n not in have:
                add("NO-SPEC", "PRD.md", f"phase {n} is in the PRD's table with no spec file")

    claimed = {}
    for s in specs:
        text = read(s)
        base = os.path.basename(s)
        for num, status in ROW_RX.findall(text):
            claimed[num] = (base, status)
            if num not in tasks:
                add("MISSING-TASK", base, f"summary row {num} has no task file")

    for num, path in sorted(tasks.items()):
        rel = os.path.relpath(path, docs)
        text = read(path)
        m = STATUS_RX.search(text)
        status = norm_status(m.group(1) if m else "")

        if num not in claimed and specs:
            add("ORPHAN-TASK", rel, "no spec's Tasks Summary mentions this task")
        elif num in claimed:
            spec_base, spec_status = claimed[num]
            if norm_status(spec_status) != status:
                add("STATUS-DISAGREE", rel,
                    f"task says {status}, {spec_base} says {norm_status(spec_status)}")

        v = VERIF_RX.search(text)
        if not v:
            add("NO-VERIFICATION", rel, "no **Verification:** field")
        else:
            cmd = v.group(1).strip()
            if cmd.startswith("[") or not cmd:
                add("PLACEHOLDER-VERIF", rel, f"Verification is still a placeholder: `{cmd}`")
            elif WEAK_RX.match(cmd):
                add("WEAK-VERIF", rel, f"`{cmd}` would pass whether or not the work was done")

        d = DEPENDS_RX.search(text)
        if d:
            for dep in TASK_NUM_RX.findall(d.group(1)):
                key = f"{int(dep[0])}.{dep[1]}"
                if key not in tasks:
                    add("DEP-MISSING", rel, f"Depends On names {key}, which does not exist")
                elif status == "in-progress":
                    dtext = read(tasks[key])
                    dm = STATUS_RX.search(dtext)
                    if norm_status(dm.group(1) if dm else "") != "complete":
                        add("DEP-INCOMPLETE", rel,
                            f"in progress, but depends on {key} which is not complete")

    # ---- numbered criteria, and the references that point at them --------------------
    #
    # Everything here is gated on IDs actually being present, because they are optional per
    # document and a tree that predates them must report what it always reported.

    spec_sc = {}          # phase -> {id: spec basename}
    for sp in specs:
        ph = phase_of_spec(sp)
        ids = criterion_ids(read(sp), "Success Criteria")
        base = os.path.basename(sp)
        seen = set()
        for cid in ids:
            if cid in seen:
                add("DUPLICATE-CRITERION-ID", os.path.relpath(sp, docs),
                    f"{cid} is used more than once in Success Criteria")
            seen.add(cid)
            if ph is not None:
                spec_sc.setdefault(ph, {}).setdefault(cid, base)

    referenced = {}       # phase -> set of ids some task claims to cover
    for num, path in sorted(tasks.items()):
        rel = os.path.relpath(path, docs)
        text = read(path)
        ph = int(num.split(".")[0])

        seen = set()
        for cid in criterion_ids(text, "Acceptance Criteria"):
            if cid in seen:
                add("DUPLICATE-CRITERION-ID", rel,
                    f"{cid} is used more than once in Acceptance Criteria")
            seen.add(cid)

        refs = covers_refs(text)
        referenced.setdefault(ph, set()).update(refs)
        # A phase with no spec at all is already reported once as NO-SPEC. Reporting every
        # annotation in it as dangling as well says the same thing N more times.
        if ph in spec_sc or any(phase_of_spec(x) == ph for x in specs):
            known = spec_sc.get(ph, {})
            for ref in sorted(set(refs)):
                if ref not in known:
                    add("UNKNOWN-CRITERION-REF", rel,
                        f"covers {ref}, which no phase {ph} spec defines")

    for ph, ids in sorted(spec_sc.items()):
        hit = referenced.get(ph, set())
        # Nothing in the phase uses the annotation, so coverage was never recorded. That is not
        # the same as nothing being covered, and reporting every criterion here would bury the
        # findings that mean something under a phase-sized wall that means "not adopted yet".
        if not hit:
            continue
        for cid, base in sorted(ids.items()):
            if cid not in hit:
                add("UNCOVERED-CRITERION", os.path.relpath(os.path.join(docs, "specs", base), docs),
                    f"{cid} is covered by no task in phase {ph}")

    # ---- a default recorded for a criterion a decision later named ------------------
    #
    # Both sections have to exist, and both have to cite the same ID. Two prose lines about the
    # same subject that never name a criterion are invisible here, which is the intended limit:
    # inferring the link from wording would be the same mistake as inferring coverage from it.
    for dirpath, _dirs, names in os.walk(docs):
        if os.path.basename(dirpath) in ("archives", "archive"):
            continue
        for n in sorted(names):
            if not n.endswith(".md"):
                continue
            p = os.path.join(dirpath, n)
            text = read(p)
            assumed = cited_by_line(text, "Assumptions")
            if not assumed:
                continue
            clarified = cited_by_line(text, "Clarifications")
            for cid in sorted(set(assumed) & set(clarified)):
                add("ASSUMPTION-CONTRADICTED", os.path.relpath(p, docs),
                    f"{cid} is both assumed and clarified: "
                    f"assumption {assumed[cid]!r} against clarification {clarified[cid]!r}")

    # Unresolved questions anywhere in the tree.
    #
    # Two things are not unresolved questions, and both occur in this repo's own plan: a marker
    # quoted inside backticks, which is a document describing the convention rather than using
    # it, and one whose question is still the <angle-bracket> placeholder. Flagging either sends
    # a reader to a file that is working as intended.
    for dirpath, _dirs, names in os.walk(docs):
        for n in sorted(names):
            if not n.endswith(".md"):
                continue
            p = os.path.join(dirpath, n)
            text = read(p)
            for m in CLARIFY_RX.finditer(text):
                q = m.group(1).strip()
                if q.startswith("<") and q.endswith(">"):
                    continue
                before, after = text[max(0, m.start() - 1):m.start()], text[m.end():m.end() + 1]
                if before == "`" and after == "`":
                    continue
                add("CLARIFICATION", os.path.relpath(p, docs), q or "(no question given)")

    return findings


def main(argv=None):
    ap = argparse.ArgumentParser(prog="spec-analyze.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("docs", nargs="?", help="the docs directory (default: .specs/docs, then docs)")
    ap.add_argument("--json", nargs="?", const="-", metavar="PATH")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--strict", action="store_true", help="exit 1 when anything is found")
    args = ap.parse_args(argv)

    docs = find_docs(args.docs)
    if not docs or not os.path.isdir(docs):
        print("spec-analyze: no docs directory found", file=sys.stderr)
        return 2

    findings = analyze(docs)

    if args.json:
        payload = json.dumps({"docs": docs, "findings": findings}, indent=2)
        if args.json == "-":
            print(payload)
        else:
            with open(args.json, "w", encoding="utf-8") as f:
                f.write(payload + "\n")

    if not args.quiet and not (args.json and args.json == "-"):
        if not findings:
            print(f"spec-analyze: {docs} is internally consistent")
        else:
            by_kind = {}
            for f in findings:
                by_kind.setdefault(f["finding"], []).append(f)
            for kind in sorted(by_kind):
                print(f"{kind}  ({len(by_kind[kind])})")
                for f in by_kind[kind]:
                    print(f"  {f['where']}: {f['detail']}")
            print(f"\n{len(findings)} finding(s). Nothing was edited.")

    return 1 if (args.strict and findings) else 0


if __name__ == "__main__":
    sys.exit(main())
