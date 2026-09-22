"""The command line. Two verbs only: check a file, or render it."""

import argparse
import sys

from .model import IncidentError, load, overall
from .render import LABEL, render


def cmd_check(args):
    incidents = load(args.file)
    open_ones = [i for i in incidents if i.is_open]
    print(f"{args.file}: {len(incidents)} incident(s), {len(open_ones)} open")
    print(f"overall: {LABEL[overall(incidents)]}")
    # Non-zero while something is open, so a deploy pipeline can refuse to ship into an outage.
    return 1 if open_ones else 0


def cmd_render(args):
    incidents = load(args.file)
    page = render(incidents, title=args.title)
    if args.out == "-":
        sys.stdout.write(page)
    else:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(page)
        print(f"wrote {args.out} ({len(incidents)} incident(s))")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(prog="beacon", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("check", help="validate an incidents file and report the overall state")
    c.add_argument("file")
    c.set_defaults(fn=cmd_check)

    r = sub.add_parser("render", help="render the status page")
    r.add_argument("file")
    r.add_argument("-o", "--out", default="status.html", help="output path, or - for stdout")
    r.add_argument("--title", default="Status", help="page title")
    r.set_defaults(fn=cmd_render)

    args = ap.parse_args(argv)
    try:
        return args.fn(args)
    except IncidentError as e:
        print(f"beacon: {e}", file=sys.stderr)
        return 2
    except OSError as e:
        print(f"beacon: {e}", file=sys.stderr)
        return 2
