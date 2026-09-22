#!/usr/bin/env python3
"""Diff a spec repo's task files against the code they claim to have produced.

Usage:
  task-converge.py [TASKS_DIR] [--repo DIR] [--phase N] [--since REF|DATE]
                   [--no-untracked] [--json [PATH]] [--quiet]

TASKS_DIR defaults to the first of .specs/docs/tasks, .<project>/docs/tasks,
docs/tasks, tasks that exists. --repo defaults to the git root of the cwd.

This tool is READ-ONLY. It gathers evidence and reports; it never edits a task
file, because a status header is a claim and flipping one automatically would
just manufacture a more confident claim. Judgement belongs to /converge.

Verdicts, per task file:

  CONFIRMED        marked done, and every File Plan entry is satisfied
  CLAIMED-UNBUILT  marked done, but File Plan entries are missing   <- the liars
  DONE-UNCLAIMED   not marked done, but every File Plan entry exists <- flip these
  PARTIAL          not marked done, some entries exist
  NOT-STARTED      not marked done, nothing exists
  NO-FILE-PLAN     no File Plan section at all, so nothing can be checked
  NO-FILES-BY-DESIGN  a File Plan that declares the task changes no files, which is
                   correct for a verification, measurement or decision task
  DEVIATION-RECORDED  marked done, entries missing, and every one of them accounted
                   for under the task's own `### Deviations` notes
  DROPPED          explicitly dropped; excluded from judgement

DEVIATION-RECORDED is what separates a deliberate departure from a claim that did not happen.
Without it, moving a file on purpose and never doing the work look identical from here: the File
Plan names a path, the path is absent, the status says Complete. The departure has to be written
into the task at the time, by whoever made it, which is the only moment anyone knows why. Partial
accounting does not count: one unexplained missing entry and the verdict is CLAIMED-UNBUILT again.

Each task in the JSON also carries its numbered acceptance criteria, where the file has them:
their IDs, text, `(covers SC-NN)` references and tick state. Nothing here judges whether a
criterion is met, because a File Plan cannot tell you that; the point is that a caller which
does has something to iterate over and a finding has something to cite.

Exit status is 0 unless --strict is passed, in which case any CLAIMED-UNBUILT
task exits 1 (for use as a CI or hook gate).
"""
import argparse, glob as globmod, json, os, re, subprocess, sys
from collections import Counter

DONE = ("🟢", "✅", "complete", "done", "shipped", "implemented")
DROPPED = ("⏸️", "⏸", "dropped", "cancelled", "canceled", "wontfix", "won't do")
SKIP_DIRS = {"archives", "archive", "screenshots", "node_modules", ".git"}

PAREN_ANY = re.compile(r"\s*\(([^()]*)\)")
TRAILING_PAREN = re.compile(r"\s*\(([^()]*)\)\s*$")
ANNOT_KEYWORD = re.compile(
    r"^(new|modify|modified|update|updated|delete|deleted|remove|removed|move|moved|rename|renamed)\b",
    re.I,
)
BULLET_RE = re.compile(r"^\s*[-*+]\s+")
BACKTICKED = re.compile(r"`([^`]+)`")
DASH_NOTE = re.compile(r"\s+[–—]\s+|\s+-\s+")
CONNECTORS = ("├──", "└──", "├─", "└─", "|--", "`--")

# A numbered acceptance criterion: `- [x] **AC1:** text (covers SC-02)`. Optional everywhere;
# a task file written before IDs existed simply yields none.
CRITERION_RE = re.compile(r"^\s*[-*]\s*\[([ xX])\]\s*\*\*(AC\d+):?\*\*\s*(.*)$")
COVERS_RE = re.compile(r"\bcovers\s+((?:SC|FR)-\d+(?:\s*(?:,|and)\s*(?:SC|FR)-\d+)*)", re.I)
COVERS_ID_RE = re.compile(r"(?:SC|FR)-\d+", re.I)

# A recorded departure from the File Plan, under `### Deviations` in the task's Progress Notes:
#   - `app/old.py` -> `app/new.py`, moved when the package was renamed
#   - `app/cache.py` dropped: the query turned out to be fast enough
DEVIATION_DROP_RE = re.compile(r"\b(drop(ped)?|remov(ed)?|delet(ed)?|not needed|superseded)\b", re.I)

# Template scaffolding and prose that must never be mistaken for a real path.
PLACEHOLDER_SUBSTR = ("file-to-create", "file-to-modify", "path/to/", "<", ">", "[", "]", "...", "…",
                      "yyyy-mm-dd")
PLACEHOLDER_EXACT = {"", ".", "..", "etc", "etc."}

# Generated, vendored, binary and asset-catalog paths. None of these are work
# anyone would write a task file for, and they otherwise swamp the report.
NOISE_RE = re.compile(
    r"(^|/)(target|dist|build|out|node_modules|vendor|\.venv|__pycache__|coverage)/"
    r"|\.(xcassets|xcodeproj|xcworkspace|framework|bundle|app)/"
    r"|(^|/)__snapshots__/|(^|/)snapshots?/"
    r"|(^|/)[^/]*\.lock$"
    r"|(^|/)(Cargo\.lock|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|uv\.lock|poetry\.lock|Package\.resolved|project\.pbxproj)$"
    r"|(^|/)CHANGELOG\.md$"
    r"|\.(png|jpe?g|heic|heif|gif|svg|webp|avif|pdf|ico|icns|ttf|otf|woff2?|eot"
    r"|mp3|mp4|mov|wav|ogg|zip|gz|tar|bin|so|dylib|a|o|class|jar|wasm|pt|onnx|safetensors)$",
    re.I,
)


# ─────────────────────────── parsing ───────────────────────────

class Evidence:
    __slots__ = ("satisfied", "total", "missing", "moved")

    def __init__(self, satisfied=0, total=0, missing=None, moved=None):
        self.satisfied, self.total = satisfied, total
        self.missing, self.moved = (missing or []), (moved or [])


def _split_annot(s):
    """Split an entry into (path, annotation).

    Real task files carry three shapes after the path: a bare keyword `(new)`,
    a compound `(new, 18 images)`, and a purely descriptive `(Sample.art)`.
    Only a leading keyword becomes an annotation; the rest is prose and is
    dropped, but the parentheses are stripped either way. Paths may be
    backticked, and may carry a trailing " - explanation".
    """
    s = BULLET_RE.sub("", s.strip())
    annot = ""
    # A keyword parenthetical may sit mid-line with prose after it
    # ("App.swift  (new)  app entry point"). Cut at the first keyword group
    # and discard everything to its right.
    for m in PAREN_ANY.finditer(s):
        k = ANNOT_KEYWORD.match(m.group(1).strip())
        if k:
            annot = k.group(1).lower()
            s = s[: m.start()].strip()
            break
    else:
        # No keyword anywhere; a purely descriptive trailing "(...)" is still noise.
        m = TRAILING_PAREN.search(s)
        if m:
            s = s[: m.start()].strip()
    bt = BACKTICKED.search(s)
    if bt:
        s = bt.group(1).strip()
    else:
        s = DASH_NOTE.split(s, 1)[0].strip().strip("`").strip()
    return s, annot


def _connector_index(line):
    for c in CONNECTORS:
        i = line.find(c)
        if i != -1:
            return i, len(c)
    return -1, 0


def _is_placeholder(p):
    low = p.lower()
    if low in PLACEHOLDER_EXACT:
        return True
    return any(t in low for t in PLACEHOLDER_SUBSTR)


def has_file_plan_section(doc):
    """Is there a File Plan heading at all?

    Distinct from whether it yields paths. A verification task whose File Plan reads
    "**None.** This task changes no files" has one and is correct; reporting that as
    NO-FILE-PLAN sends someone to fix nine files that are already right, which is what
    happened on 2026-09-16: five of nine flagged files had the section.
    """
    return re.search(r"^#{2,4}\s*File Plan\s*$", doc, re.M | re.I) is not None


def _file_plan_section(doc):
    m = re.search(r"^#{2,4}\s*File Plan\s*$", doc, re.M | re.I)
    if not m:
        return ""
    rest = doc[m.end():]
    nxt = re.search(r"^#{2,4}\s+\S", rest, re.M)
    section = rest[: nxt.start()] if nxt else rest
    blocks = re.findall(r"```[^\n]*\n(.*?)```", section, re.S)
    if blocks:
        return "\n".join(blocks)
    # Fallback: a bullet list of paths.
    out = []
    for ln in section.splitlines():
        s = ln.strip()
        if BULLET_RE.match(ln) and ("/" in s or "." in s):
            out.append(s)
    return "\n".join(out)


def _join_wrapped(block):
    """Join a line whose annotation wraps onto the next.

    A File Plan is often written as an aligned tree, and a long annotation wraps:

        plugins/delegation/README.md    (new - 306 lines, the tiering rationale;
                                         NOT under agents/, see the finding)

    Read line by line, the first line's annotation never closes, so it is not stripped and the
    path keeps a trailing "(new - 306 lines..." that matches no file; the second line becomes an
    entry of its own. Both were reported as missing while the file existed. Joining on unbalanced
    parentheses is enough, because a path never legitimately contains one.
    """
    out = []
    for line in block.splitlines():
        if out and out[-1].count("(") > out[-1].count(")"):
            out[-1] = out[-1].rstrip() + " " + line.strip()
        else:
            out.append(line)
    return "\n".join(out)


def parse_file_plan(doc):
    """Return [(path, annotation)] from a task doc's File Plan section."""
    block = _join_wrapped(_file_plan_section(doc))
    if not block.strip():
        return []
    out, prefix = [], {0: ""}
    for raw in block.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        ci, clen = _connector_index(line)
        if ci == -1:
            name, ann = _split_annot(line.strip().lstrip("│| ").strip())
            if not name:
                continue
            if name.endswith("/"):
                prefix = {0: name}
                continue
            if not _is_placeholder(name):
                out.append((name, ann))
            continue
        depth = ci // 4
        name, ann = _split_annot(line[ci + clen:].strip())
        if not name:
            continue
        base = prefix.get(depth, "")
        if name.endswith("/"):
            prefix[depth + 1] = base + name
            continue
        path = base + name
        if not _is_placeholder(path):
            out.append((path, ann))
    return out


def parse_deviations(doc):
    """{path: "moved"|"dropped"} from the task's `### Deviations` notes.

    Only a backticked path counts. Prose under the heading is common and reads as explanation,
    not as an entry, so requiring the backticks keeps a sentence about the layout from being
    parsed as a filename.
    """
    m = re.search(r"^#{2,4}\s*Deviations\b.*$", doc, re.M | re.I)
    if not m:
        return {}
    depth = len(re.match(r"#+", doc[m.start():]).group(0))
    rest = doc[m.end():]
    nxt = re.search(r"^#{1,%d}\s+\S" % depth, rest, re.M)
    body = rest[:nxt.start()] if nxt else rest

    out = {}
    for line in body.splitlines():
        if not line.strip().startswith(("-", "*")):
            continue
        paths = BACKTICKED.findall(line)
        if not paths:
            continue
        # The first backticked path is the File Plan entry this line accounts for; a second one
        # is where it went.
        out[paths[0].strip()] = "moved" if len(paths) > 1 else (
            "dropped" if DEVIATION_DROP_RE.search(line) else "moved")
    return out


def parse_criteria(doc):
    """The task's numbered acceptance criteria, in document order.

    Returns [] for a task with none, which is every task file written before IDs existed. An
    empty list is the honest answer there: a caller iterating it does nothing, where an invented
    numbering would hand it IDs that appear nowhere in the document it came from.
    """
    m = re.search(r"^(#{1,6})\s+Acceptance Criteria\s*$", doc, re.M | re.I)
    if not m:
        return []
    depth = len(m.group(1))
    rest = doc[m.end():]
    nxt = re.search(r"^#{1,%d}\s+\S" % depth, rest, re.M)
    body = rest[:nxt.start()] if nxt else rest

    out = []
    for line in body.splitlines():
        cm = CRITERION_RE.match(line)
        if cm:
            out.append({"id": cm.group(2).upper(), "checked": cm.group(1).lower() == "x",
                        "text": cm.group(3).strip(), "covers": []})
        elif out and line.strip() and not BULLET_RE.match(line) and line[:1] in " \t":
            # A criterion wrapped onto a continuation line. Given/When/Then criteria are long
            # enough that this is the common case, not the exception, and the `(covers ...)`
            # annotation is usually what ends up on the second line.
            out[-1]["text"] += " " + line.strip()
    for c in out:
        for cm in COVERS_RE.finditer(c["text"]):
            c["covers"].extend(i.upper() for i in COVERS_ID_RE.findall(cm.group(1)))
    return out


def field(text, key):
    m = re.search(r"^\*\*%s:?\*\*\s*(.+)$" % re.escape(key), text, re.M | re.I)
    return m.group(1).strip() if m else ""


def title(text, path):
    m = re.search(r"^#\s+(.+)$", text, re.M)
    return m.group(1).strip() if m else os.path.basename(path)


def task_number(name):
    m = re.match(r"^(\d+)\.(\d+)", os.path.basename(name))
    return (int(m.group(1)), int(m.group(2))) if m else (10**6, 0)


def path_present(repo, p, tracked):
    """Is this File Plan entry present in the repo? Globs count if anything matches."""
    if any(ch in p for ch in "*?"):
        if globmod.glob(os.path.join(repo, p)):
            return True
        return any(t == p or globmod.fnmatch.fnmatch(t, p) for t in tracked)
    return (p in tracked) or os.path.exists(os.path.join(repo, p))


def entry_satisfied(annotation, exists):
    """A (delete) entry is satisfied by absence; every other entry by presence."""
    if (annotation or "").lower().startswith(("delet", "remov")):
        return not exists
    return exists


def find_moved(path, tracked):
    """Where did a missing File Plan path go?

    Suffix first: a whole subtree relocating under a new root ('orchestrator/'
    -> 'components/orchestrator/') is the common case, and the basename alone is
    usually ambiguous there. Fall back to a unique basename match. Ambiguity
    means we say nothing rather than guess.
    """
    p = path.strip("/")
    if not p:
        return None
    hits = [t for t in tracked if t != p and t.endswith("/" + p)]
    if len(hits) == 1:
        return hits[0]
    if hits:
        return None  # ambiguous relocation; do not guess
    base = os.path.basename(p)
    hits = [t for t in tracked if os.path.basename(t) == base and t != p]
    return hits[0] if len(hits) == 1 else None


def classify(status, ev, doc=""):
    s = (status or "").lower()
    if any(d in s for d in DROPPED):
        return "DROPPED"
    if ev.total == 0:
        return "NO-FILES-BY-DESIGN" if has_file_plan_section(doc) else "NO-FILE-PLAN"
    done_hdr = any(d in s for d in DONE)
    all_ok = ev.satisfied == ev.total
    if done_hdr:
        if all_ok:
            return "CONFIRMED"
        # Every gap accounted for by a file that simply moved: the work shipped,
        # the File Plan path is what went stale.
        if ev.moved and len(ev.moved) == len(ev.missing):
            return "STALE-FILE-PLAN"
        # Every gap accounted for in writing, by whoever made the departure. `missing` carries
        # the annotation appended ("app/old.py (new)"), so the bare path is what must match.
        recorded = parse_deviations(doc)
        if recorded and all(TRAILING_PAREN.sub("", m).strip() in recorded for m in ev.missing):
            return "DEVIATION-RECORDED"
        return "CLAIMED-UNBUILT"
    if all_ok:
        return "DONE-UNCLAIMED"
    return "PARTIAL" if ev.satisfied > 0 else "NOT-STARTED"


# ─────────────────────────── git / fs ───────────────────────────

def sh(args, cwd=None):
    try:
        r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=60)
        return r.stdout if r.returncode == 0 else ""
    except Exception:
        return ""


def git_root(start):
    out = sh(["git", "-C", start, "rev-parse", "--show-toplevel"]).strip()
    return out or os.path.abspath(start)


def tracked_files(repo):
    return set(sh(["git", "-C", repo, "ls-files"]).splitlines())


def changed_since(repo, since, added_only=True):
    """Paths touched in the window. Added-only by default: a file that merely
    changed is expected churn, while a file that appeared and is named in no
    File Plan is work nobody wrote down."""
    args = ["git", "-C", repo, "log", "--name-only", "--pretty=format:"]
    if added_only:
        args.append("--diff-filter=A")
    if re.match(r"^\d{4}-\d{2}-\d{2}$", since) or since.endswith(("ago", "week", "month", "year")):
        args.append("--since=" + since)
    else:
        args.append(since + "..HEAD")
    return Counter(p for p in sh(args).splitlines() if p.strip())


def autodetect_tasks_dir(repo):
    cands = [".specs/docs/tasks", "docs/tasks", "tasks"]
    for d in sorted(os.listdir(repo)) if os.path.isdir(repo) else []:
        if d.startswith(".") and os.path.isdir(os.path.join(repo, d, "docs", "tasks")):
            cands.insert(0, os.path.join(d, "docs", "tasks"))
    for c in cands:
        p = os.path.join(repo, c)
        if os.path.isdir(p):
            return p
    return None


def collect_tasks(tasks_dir, phase=None):
    found = []
    for root, dirs, files in os.walk(tasks_dir):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for f in files:
            if not f.endswith(".md") or f.upper().startswith(("INDEX", "README")):
                continue
            n = task_number(f)
            if n[0] == 10**6:
                continue
            if phase is not None and n[0] != phase:
                continue
            found.append(os.path.join(root, f))
    return sorted(found, key=lambda p: task_number(p))


# ─────────────────────────── report ───────────────────────────

# Worst news first. Every verdict a task can carry must appear here or it is silently absent from
# the printed report while still being counted in the summary line, which is how NO-FILES-BY-DESIGN
# went nine tasks unmentioned.
ORDER = ["CLAIMED-UNBUILT", "STALE-FILE-PLAN", "DEVIATION-RECORDED", "DONE-UNCLAIMED", "PARTIAL",
         "NO-FILE-PLAN", "NO-FILES-BY-DESIGN", "CONFIRMED", "NOT-STARTED", "DROPPED"]

BLURB = {
    "CLAIMED-UNBUILT": "Marked done. The code does not back it up. Verify each one by hand.",
    "STALE-FILE-PLAN": "Marked done, and every gap is a file that moved. Work shipped; the plan path rotted.",
    "DEVIATION-RECORDED": "Marked done, and every gap is explained in the task's own Deviations notes.",
    "NO-FILES-BY-DESIGN": "A File Plan declaring no files, which is right for a verification or decision task.",
    "DONE-UNCLAIMED":  "Not marked done, but every planned file is present. Candidates to close.",
    "PARTIAL":         "Work started, not finished. Expected mid-phase.",
    "NO-FILE-PLAN":    "No usable File Plan, so this tool cannot judge them.",
    "CONFIRMED":       "Marked done and the code agrees.",
    "NOT-STARTED":     "Nothing on disk yet.",
    "DROPPED":         "Explicitly dropped.",
}


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("tasks_dir", nargs="?")
    ap.add_argument("--repo")
    ap.add_argument("--phase", type=int)
    ap.add_argument("--since", default="30 days ago")
    ap.add_argument("--no-untracked", action="store_true")
    ap.add_argument("--all-changes", action="store_true",
                    help="untracked bucket counts modified files too, not just added ones (noisy)")
    ap.add_argument("--json", nargs="?", const="-", default=None)
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args()

    repo = os.path.abspath(a.repo) if a.repo else git_root(os.getcwd())
    tasks_dir = a.tasks_dir or autodetect_tasks_dir(repo)
    if not tasks_dir or not os.path.isdir(tasks_dir):
        print("error: no tasks directory found. Pass one explicitly.", file=sys.stderr)
        return 2

    tracked = tracked_files(repo)
    tasks = collect_tasks(tasks_dir, a.phase)
    if not tasks:
        print(f"error: no task files matching N.NN-*.md under {tasks_dir}", file=sys.stderr)
        return 2

    results, planned_paths = [], set()
    for path in tasks:
        try:
            text = open(path, errors="replace").read()
        except OSError:
            continue
        entries = parse_file_plan(text)
        sat, missing, moved = 0, [], []
        for p, ann in entries:
            planned_paths.add(p)
            exists = path_present(repo, p, tracked)
            if entry_satisfied(ann, exists):
                sat += 1
                continue
            missing.append(p if not ann else f"{p} ({ann})")
            if not (ann or "").lower().startswith(("delet", "remov")):
                tgt = find_moved(p, tracked)
                if tgt:
                    moved.append((p, tgt))
        ev = Evidence(sat, len(entries), missing, moved)
        status = field(text, "Status") or "-"
        results.append({
            "file": os.path.relpath(path, repo),
            "task": ".".join(str(x) for x in task_number(path)),
            "title": title(text, path),
            "status": status,
            "verdict": classify(status, ev, text),
            "satisfied": ev.satisfied,
            "planned": ev.total,
            "missing": ev.missing,
            "moved": [{"from": a, "to": b} for a, b in ev.moved],
            "criteria": parse_criteria(text),
        })

    untracked = []
    if not a.no_untracked:
        for p, n in changed_since(repo, a.since, added_only=not a.all_changes).most_common():
            if p in planned_paths or NOISE_RE.search(p) or p.startswith(".specs/"):
                continue
            if any(p.startswith(d.rstrip("/") + "/") for d in [os.path.relpath(tasks_dir, repo)]):
                continue
            untracked.append({"path": p, "commits": n})

    payload = {
        "repo": repo,
        "tasks_dir": os.path.relpath(tasks_dir, repo),
        "phase": a.phase,
        "since": a.since,
        "tasks": results,
        "untracked_work": untracked,
        "summary": dict(Counter(r["verdict"] for r in results)),
    }

    if a.json is not None:
        blob = json.dumps(payload, indent=2, ensure_ascii=False)
        if a.json == "-":
            print(blob)
        else:
            open(a.json, "w").write(blob + "\n")
            if not a.quiet:
                print(f"wrote {a.json}")
        if a.json == "-":
            return 1 if (a.strict and payload["summary"].get("CLAIMED-UNBUILT")) else 0

    if not a.quiet:
        scope = f"phase {a.phase}" if a.phase else "all phases"
        print(f"converge: {len(results)} task files, {scope}")
        print(f"  repo      {repo}")
        print(f"  tasks     {payload['tasks_dir']}\n")

        by = {}
        for r in results:
            by.setdefault(r["verdict"], []).append(r)
        for v in ORDER:
            rows = by.get(v)
            if not rows:
                continue
            print(f"── {v}  ({len(rows)})")
            blurb = BLURB.get(v)
            if blurb:
                print(f"   {blurb}")
            for r in rows:
                bar = f"{r['satisfied']}/{r['planned']}" if r["planned"] else "-"
                print(f"   {r['task']:<8} {bar:<7} {r['file']}")
                print(f"   {'':<8} {'':<7} {r['title'][:88]}")
                seen_moved = {mv["from"] for mv in r["moved"]}
                for m in r["missing"][:6]:
                    bare = m.split(" (")[0]
                    if bare in seen_moved:
                        continue
                    print(f"   {'':<8} {'':<7}   missing: {m}")
                for mv in r["moved"][:6]:
                    print(f"   {'':<8} {'':<7}   moved?:  {mv['from']}  ->  {mv['to']}")
                extra = len(r["missing"]) - 6
                if extra > 0:
                    print(f"   {'':<8} {'':<7}   … and {extra} more")
            print()

        if untracked:
            kind = "Changed" if a.all_changes else "Added"
            print(f"── UNTRACKED WORK  ({len(untracked)})")
            print(f"   {kind} in the last '{a.since}' but named in no task File Plan.")
            for u in untracked[:25]:
                print(f"   {u['path']}")
            if len(untracked) > 25:
                print(f"   … and {len(untracked) - 25} more")
            print()

        s = payload["summary"]
        liars = s.get("CLAIMED-UNBUILT", 0)
        stale = s.get("STALE-FILE-PLAN", 0)
        judged = liars + stale + s.get("CONFIRMED", 0)
        print("summary: " + ", ".join(f"{k}={v}" for k, v in sorted(s.items())))
        if judged:
            print(f"headline: {liars} of {judged} tasks marked done could NOT be confirmed "
                  f"({liars / judged * 100:.0f}% of completion claims unverified); "
                  f"{stale} more shipped but point at moved files")
        if s.get("NO-FILE-PLAN"):
            print(f"note: {s['NO-FILE-PLAN']} tasks have no checkable File Plan and were not judged")

    return 1 if (a.strict and payload["summary"].get("CLAIMED-UNBUILT")) else 0


if __name__ == "__main__":
    sys.exit(main())
