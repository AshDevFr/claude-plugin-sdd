#!/usr/bin/env python3
"""Backfill YYYY-MM-DD- prefixes onto shipped docs, and optionally fold one directory
into another, rewriting every reference that the renames would break.

Usage:
  backfill-dates.py DOCS_DIR [--dir implemented] [--fold planned:plans] [--apply]

Without --apply this is a dry run: it reports the renames, how many references it would
rewrite, and every reference whose basename is ambiguous (the same filename living in two
directories) so you can eyeball those before committing.

Dates come from the doc's own **Last Updated** / **Completed** header, falling back to the
last commit that touched it. A spec repo that was imported wholesale will have the import
commit date on every old file, so prefer the header and check the fallbacks by hand.

Reference rewriting is path-aware: a link is only retargeted when it actually resolves to a
file being renamed. That is what keeps `analysis/foo.md` intact while `implemented/foo.md`
gains its date.
"""
import collections, glob, os, re, subprocess, sys

args = sys.argv[1:]
if not args or args[0].startswith("-"):
    sys.exit(__doc__)
docs = args[0]
apply = "--apply" in args
target_dir = "implemented"
folds = []
for i, a in enumerate(args):
    if a == "--dir":
        target_dir = args[i + 1]
    if a == "--fold":
        src, dst = args[i + 1].split(":")
        folds.append((src, dst))

os.chdir(docs)
DATED = re.compile(r"\d{4}-\d{2}-\d{2}-")


def header_date(p):
    for ln in open(p, errors="replace").read().splitlines()[:40]:
        m = re.match(r"^\*\*(Last Updated|Completed|Date Completed):?\*\*\s*(.+)$", ln.strip(), re.I)
        if m:
            d = re.search(r"\d{4}-\d{2}-\d{2}", m.group(2))
            if d:
                return d.group(0), "header"
    out = subprocess.run(["git", "log", "-1", "--format=%ad", "--date=short", "--", p],
                         capture_output=True, text=True).stdout.strip()
    return (out, "git") if out else (None, None)


renames, undated, sources = {}, [], {}
for p in sorted(glob.glob(f"{target_dir}/*.md")):
    b = os.path.basename(p)
    if DATED.match(b):
        continue
    d, src = header_date(p)
    if not d:
        undated.append(p)
        continue
    renames[p] = f"{target_dir}/{d}-{b}"
    sources[p] = src
for src, dst in folds:
    for p in sorted(glob.glob(f"{src}/*.md")):
        renames[p] = f"{dst}/{os.path.basename(p)}"
        sources[p] = "fold"

# a basename living in two directories cannot be rewritten by name alone
where = collections.defaultdict(set)
for p in glob.glob("**/*.md", recursive=True):
    where[os.path.basename(p)].add(os.path.dirname(p))
AMBIGUOUS = {b for b, dirs in where.items() if len(dirs) > 1}


def resolve(ref, fromdir):
    ref = ref.split("#")[0].strip()
    if not ref.endswith(".md") or ref.startswith(("http://", "https://")):
        return None
    for prefix in ("./",):
        ref = ref[len(prefix):] if ref.startswith(prefix) else ref
    m = re.match(r"^\.[\w-]+/docs/(.*)$", ref)   # ".specs/docs/implemented/x.md"
    if m:
        return os.path.normpath(m.group(1)), True
    return os.path.normpath(os.path.join(fromdir, ref)), False


def retarget(ref, fromdir):
    body, frag = (ref.split("#", 1) + [""])[:2]
    frag = "#" + frag if "#" in ref else ""
    r = resolve(body, fromdir)
    if not r or r[0] not in renames:
        return None, None, None
    path, absolute = r
    new = renames[path]
    if absolute:
        root = re.match(r"^(\.[\w-]+/docs/)", body).group(1)
        return root + new + frag, os.path.basename(path), os.path.basename(new)
    return os.path.relpath(new, fromdir or ".") + frag, os.path.basename(path), os.path.basename(new)


stats, edits = collections.Counter(), {}
for t in sorted(glob.glob("**/*.md", recursive=True)):
    if t.startswith("archives/"):
        continue
    d = os.path.dirname(t)
    s = s0 = open(t, errors="replace").read()

    def link(m):
        text, tgt = m.group(1), m.group(2)
        nt, ob, nb = retarget(tgt, d)
        if nt is None:
            return m.group(0)
        stats["link"] += 1
        if text.strip("`") == ob or text.strip("`").endswith("/" + ob):
            text = text.replace(ob, nb)
        return f"[{text}]({nt})"

    s = re.sub(r"\[([^\]\n]*)\]\(([^)\s]+\.md(?:#[^)\s]*)?)\)", link, s)

    def span(m):
        nt, _, _ = retarget(m.group(1), d)
        if nt is None:
            return m.group(0)
        stats["code-span"] += 1
        return f"`{nt}`"

    s = re.sub(r"`([^`\n]*\.md)`", span, s)

    for old, new in renames.items():
        ob, nb = os.path.basename(old), os.path.basename(new)
        if ob == nb or ob in AMBIGUOUS:
            continue
        s, n = re.subn(r"(?<![\w./-])" + re.escape(ob), nb, s)
        stats["bare"] += n
    if s != s0:
        edits[t] = s

by_src = collections.Counter(sources.values())
print(f"{len(renames)} renames ({dict(by_src)}); "
      f"rewrites {dict(stats)} across {len(edits)} files")
if undated:
    print(f"\nNO DATE — resolve these by hand (check the main repo's history):")
    for p in undated:
        print("   ", p)
guessed = [p for p, s in sources.items() if s == "git"]
if guessed:
    print(f"\n{len(guessed)} dated from git rather than a header — verify these are not all the import commit:")
    for p in guessed[:10]:
        print(f"    {renames[p]}")
if AMBIGUOUS:
    print(f"\nambiguous basenames (handled by path, not by name): {', '.join(sorted(AMBIGUOUS))}")

if not apply:
    print("\ndry run — re-run with --apply")
    sys.exit(0)
for old, new in renames.items():
    os.makedirs(os.path.dirname(new), exist_ok=True)
    subprocess.run(["git", "mv", old, new], check=True)
for t, s in edits.items():
    open(renames.get(t, t), "w").write(s)
print("\napplied — now re-run build-index.py and check for broken links")
