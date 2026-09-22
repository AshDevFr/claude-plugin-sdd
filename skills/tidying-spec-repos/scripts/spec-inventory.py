#!/usr/bin/env python3
"""Inventory a nested spec repo's docs tree: title, status, phase tally, dates, verdict.

Usage: spec-inventory.py [DOCS_DIR]   (default: ./docs, relative to the spec repo root)

Emits one TSV row per markdown doc plus a summary. Verdicts are suggestions from the
document's own bookkeeping; they are NOT proof the work shipped. Verify SHIPPED against
the code before moving anything.
"""
import os, re, subprocess, sys, datetime

DONE = ("🟢", "✅", "complete", "done", "shipped", "implemented")
OPEN = ("🔵", "🟡", "🔴", "⏸️", "not started", "planning", "in progress", "blocked", "paused", "draft")
SKIP_DIRS = {"archives", "archive", "screenshots", "node_modules", ".git"}

def head(path, n=60):
    try:
        return open(path, errors="replace").read().splitlines()[:n]
    except OSError:
        return []

def field(lines, key):
    pat = re.compile(r"^\*\*%s:?\*\*\s*(.+)$" % re.escape(key), re.I)
    for ln in lines:
        m = pat.match(ln.strip())
        if m:
            return m.group(1).strip()
    return ""

def title(lines, path):
    for ln in lines:
        if ln.startswith("# "):
            return ln[2:].strip()
    return os.path.basename(path)

def phase_tally(path):
    """Count status cells in the Progress Summary / Tasks Summary table."""
    done = total = 0
    in_table = False
    for ln in open(path, errors="replace"):
        if not in_table:
            # the header row of a Progress Summary / Tasks Summary table
            if re.match(r"^\|\s*(Phase|Task|Defect|Step)s?\s*\|", ln, re.I):
                in_table = True
            continue
        if True:
            if not ln.startswith("|"):
                break
            if re.match(r"^\|[\s:|-]+\|", ln):
                continue
            cells = [c.strip() for c in ln.strip().strip("|").split("|")]
            if len(cells) < 2:
                continue
            cell = cells[1].lower()
            total += 1
            if any(d in cell for d in DONE):
                done += 1
    return done, total

def git_date(repo, path):
    try:
        out = subprocess.run(["git", "-C", repo, "log", "-1", "--format=%ad", "--date=short", "--", path],
                             capture_output=True, text=True, timeout=15).stdout.strip()
        return out or "-"
    except Exception:
        return "-"

def classify(status, done, total, in_implemented, in_analysis=False):
    if in_analysis:
        # investigations never "ship"; they belong in analysis/ permanently
        return "ANALYSIS"
    s = status.lower()
    hdr_done = any(d in s for d in DONE) and not s.startswith("**status: unresolved")
    tbl_done = total > 0 and done == total
    tbl_open = total > 0 and done < total
    if in_implemented:
        return "FILED" if (hdr_done or tbl_done or total == 0) else "FILED-STALE-HEADER"
    if hdr_done and (tbl_done or total == 0):
        return "SHIPPED"
    if tbl_done and not hdr_done:
        return "SHIPPED-STALE-HEADER"
    if hdr_done and tbl_open:
        return "MIXED-VERIFY"
    return "ACTIVE"

def main():
    docs = sys.argv[1] if len(sys.argv) > 1 else "docs"
    repo = subprocess.run(["git", "-C", docs, "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True).stdout.strip() or "."
    rows = []
    for root, dirs, files in os.walk(docs):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        for f in sorted(files):
            if not f.endswith(".md") or f == "INDEX.md":
                continue
            p = os.path.join(root, f)
            lines = head(p)
            status = field(lines, "Status") or "-"
            done, total = phase_tally(p)
            in_impl = os.sep + "implemented" + os.sep in p + os.sep
            in_analysis = os.sep + "analysis" + os.sep in p + os.sep
            verdict = classify(status, done, total, in_impl, in_analysis)
            gdate = git_date(repo, os.path.relpath(p, repo))
            last = field(lines, "Last Updated") or field(lines, "Date") or ""
            m = re.search(r"\d{4}-\d{2}-\d{2}", last)
            shipped = m.group(0) if (m and verdict.startswith("SHIPPED")) else gdate
            rows.append((verdict, p, title(lines, p), status.split("—")[0].strip()[:38],
                         f"{done}/{total}" if total else "-", shipped))
    rows.sort(key=lambda r: (r[0], r[1]))
    print(f"{'VERDICT':<20} {'SHIPPED':<11} {'PHASES':<7} {'PATH':<58} STATUS / TITLE")
    for v, p, t, s, ph, d in rows:
        print(f"{v:<20} {d:<11} {ph:<7} {p:<58} {s} | {t[:52]}")
    print()
    counts = {}
    for r in rows:
        counts[r[0]] = counts.get(r[0], 0) + 1
    print("summary:", ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))
    print("today:", datetime.date.today().isoformat())

main()
