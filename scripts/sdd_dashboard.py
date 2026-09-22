"""Shared by sdd-dashboard, sdd-report and the refresh hook: where a project's dashboard lives.

Both executables and the hook must agree on one directory per project, or the generator writes a
report the server never serves. Keeping the resolution in one module is what makes that true.
Standard library only.
"""

import hashlib
import os
import re
import subprocess

DEFAULT_PORT = 8765
DEFAULT_HOST = "0.0.0.0"
# Long enough that an owner checking in the morning finds the page from the evening before, short
# enough that a forgotten server does not keep a project on the LAN for days. Any change to the
# content resets it, and every commit rewrites the report, so an active project never idles out.
DEFAULT_IDLE_HOURS = 12


def git(cwd, *args):
    """Run git and return stripped stdout, or None when it fails or git is absent."""
    try:
        out = subprocess.run(
            ["git", "-C", cwd, *args],
            capture_output=True, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def repo_root(start):
    """The checkout containing start, or start itself outside git."""
    return git(start, "rev-parse", "--show-toplevel") or os.path.realpath(start)


def main_root(start):
    """The main checkout, even when start is inside a linked worktree.

    Keyed on this rather than on the worktree, so a commit made in a worktree refreshes the same
    dashboard the owner already has open instead of a new one nobody is looking at.
    """
    common = git(start, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common:
        common = os.path.realpath(common)
        if os.path.basename(common) == ".git":
            return os.path.dirname(common)
    return repo_root(start)


def dashboard_dir(project, override=None):
    """Resolve the dashboard directory for a project.

    Outside the repository by default. A report regenerated after every commit would otherwise
    leave the working tree, or the spec repo, permanently dirty, and the spec repo's Stop guard
    would refuse to end every turn over a file nobody meant to commit. The state home survives
    reboots, which /tmp does not.
    """
    chosen = override or os.environ.get("SDD_DASHBOARD_DIR")
    if chosen:
        return os.path.abspath(os.path.expanduser(chosen))
    root = main_root(project)
    state_home = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", os.path.basename(root)) or "project"
    digest = hashlib.sha256(root.encode()).hexdigest()[:10]
    return os.path.join(state_home, "sdd-dashboard", f"{slug}-{digest}")


def project_name(project):
    return os.path.basename(main_root(project))
