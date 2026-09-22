#!/usr/bin/env python3
"""Regenerate INDEX.md for a spec repo's docs tree from what is on disk.

Usage: build-index.py [DOCS_DIR] [PROJECT_NAME]

Emits sections only for directories that exist. `implemented/` is split into the
date-prefixed docs (newest first) and the pre-convention undated ones. Review the output
before committing: it reports what documents claim, and claims can be stale.
"""
import os, re, glob, sys, datetime

docs = sys.argv[1] if len(sys.argv) > 1 else "docs"
repodir = os.path.basename(os.path.dirname(os.path.abspath(docs)))
project = sys.argv[2] if len(sys.argv) > 2 else repodir.lstrip(".")
os.chdir(docs)

DESC = {
    "plans": ("Active plans", "active implementation plans (in flight or queued)"),
    "planned": ("Planned / not started", "plans and PRDs not yet picked up"),
    "specs": ("Phase specs", "phase specs for the PRD -> specs -> tasks workflow"),
    "tasks": ("Tasks", "per-phase task files"),
    "ideas": ("Ideas", "concepts not yet planned, and dropped proposals"),
    "analysis": ("Analysis", "investigations and audits"),
}

def meta(p):
    title = status = None
    for ln in open(p, errors="replace").read().splitlines()[:40]:
        if title is None and ln.startswith("# "):
            title = ln[2:].strip()
        if status is None and re.match(r"^\*\*Status:?\*\*", ln.strip()):
            status = re.sub(r"^\*\*Status:?\*\*\s*", "", ln.strip())
        if title and status:
            break
    if status:
        status = status.split("—")[0].split(" - ")[0].strip()
        status = re.sub(r"\*\*", "", status)
        if len(status) > 46:
            status = status[:44].rsplit(" ", 1)[0] + "…"
    return (title or os.path.basename(p)), (status or "—")

L = []
A = L.append
A(f"# {project} Implementation Documentation")
A("")
A("> Index of every planning artifact in this spec repo: what shipped, what is in flight, what is")
A("> only an idea, and what is background research. Generated from disk; do not hand-edit.")
A("")
A(f"**Last Updated:** {datetime.date.today().isoformat()}")
A("")
A("---")
A("")
A("## Layout")
A("")
A("```")
A(f"{repodir}/{os.path.basename(os.path.abspath('.'))}/")
A("├── INDEX.md      # this file")
for d, (_, blurb) in DESC.items():
    if os.path.isdir(d):
        A(f"├── {d + '/':<14}# {blurb}")
if os.path.isdir("implemented"):
    A("├── implemented/  # shipped work, date-prefixed YYYY-MM-DD-<slug>.md")
if os.path.isdir("archives"):
    A("└── archives/     # historical dumps predating this repo, kept as-is")
A("```")
A("")
A("Location encodes state: a doc outside `implemented/` still has outstanding work. A plan is done")
A("when it moves to `implemented/` with the date it shipped as its filename prefix; multi-phase")
A("initiatives keep their numbered spec files inside one dated subdirectory.")
A("")
A("---")

for d, (heading, _) in DESC.items():
    files = sorted(glob.glob(f"{d}/**/*.md", recursive=True))
    if not files:
        continue
    A("")
    A(f"## {heading}")
    A("")
    A("| Doc | Status |")
    A("| --- | ------ |")
    for p in files:
        t, s = meta(p)
        A(f"| [{t}]({p}) | {s} |")

if os.path.isdir("implemented"):
    flat = sorted(glob.glob("implemented/*.md"))
    dated = [p for p in flat if re.match(r"implemented/\d{4}-\d{2}-\d{2}-", p)]
    undated = [p for p in flat if p not in dated]
    initiatives = sorted(glob.glob("implemented/*/"))
    items = []
    for p in dated:
        t, s = meta(p)
        items.append((os.path.basename(p)[:10], f"[{t}]({p})", s))
    for dpath in initiatives:
        name = os.path.basename(dpath.rstrip("/"))
        m = re.match(r"(\d{4}-\d{2}-\d{2})-(.*)", name)
        phases = sorted(glob.glob(dpath + "*.md"))
        links = ", ".join(f"[{os.path.basename(p).split('_')[0]}]({p})" for p in phases)
        items.append(((m.group(1) if m else "—"),
                      f"{(m.group(2) if m else name).replace('-', ' ')} ({links})", "🟢 Complete"))
    A("")
    A("---")
    A("")
    A(f"## Implemented — dated ({len(items)})")
    A("")
    A("Newest first.")
    A("")
    A("| Shipped | Work | Status |")
    A("| ------- | ---- | ------ |")
    for date, link, st in sorted(items, reverse=True):
        A(f"| {date} | {link} | {st} |")
    if undated:
        A("")
        A(f"## Implemented — undated ({len(undated)})")
        A("")
        A("Shipped before the date-prefix convention. Their own `Last Updated` header carries the date.")
        A("A few still read Planning or In Progress: those headers were never re-stamped, and the")
        A("filing is what to trust.")
        A("")
        A("| Work | Status |")
        A("| ---- | ------ |")
        for p in undated:
            t, s = meta(p)
            A(f"| [{t}]({p}) | {s} |")

if os.path.isdir("archives"):
    A("")
    A("---")
    A("")
    A("## Archives")
    A("")
    A("`archives/` holds documentation predating this repo. Nothing there is authoritative and its")
    A("paths are not maintained; read the current docs first.")

open("INDEX.md", "w").write("\n".join(L) + "\n")
print(f"wrote {os.path.abspath('INDEX.md')} ({len(L)} lines)")
