---
description: Start, check, refresh or stop the live project dashboard the owner reads from another machine
argument-hint: "[start|stop|status|refresh|url] [--port N] [--host ADDR] [--no-key] [--keep-running] [--idle-hours H]"
disable-model-invocation: true
---

# Dashboard

Manage this project's dashboard: a page on the LAN showing where the project stands without
asking. Action: `$ARGUMENTS` (default `start`).

Both scripts ship inside this plugin, alongside `picks.js` for mockups that ask the owner to
choose between options:

```sh
${CLAUDE_PLUGIN_ROOT}/scripts/sdd-dashboard start|stop|status|url|path
${CLAUDE_PLUGIN_ROOT}/scripts/sdd-report [--init]
${CLAUDE_PLUGIN_ROOT}/scripts/picks.js          # copied into a mockup folder, see dashboard-upkeep
```

Run them from the project root. The dashboard directory lives outside the repository, under
`~/.local/state/sdd-dashboard/`, so regenerating after every commit never dirties the working
tree or the spec repo. `sdd-dashboard path` prints it.

## start (the default)

1. `sdd-dashboard start`, passing through any `--port`, `--host`, `--url-host`, `--no-key`,
   `--key`, `--keep-running`, `--stop-with-session` or `--idle-hours` from the arguments. It is idempotent: on a running server it prints the existing URL
   and changes nothing. The port and key are saved, so later starts reuse them without flags.
2. `sdd-report --init`. On first use this scaffolds `report.html` from the template, then fills
   the generated regions. On later runs it only regenerates.
3. If the report was just scaffolded, fill in its hand-written sections now, following the
   **`sdd:dashboard-upkeep`** skill. A dashboard of placeholders is not worth sending anyone.
4. Print the `url` line for the owner.

The server only ever serves. A mockup's Pick buttons build a prompt the owner pastes back, and
nothing is posted to the machine, so there is no inbound channel to describe or defend. The
`sdd:dashboard-upkeep` skill covers the markup.

**The first time in a project, say what start exposes.** The server binds every interface on
port 8765 by default, over plain HTTP. With the key (the default), anyone on the network holding
the URL can read the page, and the key can be read off the wire. With `--no-key`, anyone who can
reach the port can. If the owner reads on the same machine, `--host 127.0.0.1` keeps it local.

**When it stops.** When a Claude session in this project exits (not on `/clear` or resume), on
`stop`, on a reboot, or after 12 hours with no page view and no change to its content. A stopped
server stays stopped, deliberately: nothing restarts it, a commit included, until someone runs
`start`. When the owner reports the page is down, `sdd-dashboard status` says when and why it
stopped. Both settings below are saved for later starts:

- `--keep-running`: outlive the session, for an owner who reads after it ends. Offer it when the
  owner says they read from another machine later; do not add it unasked. `--stop-with-session`
  undoes it, without a restart. The server belongs to the project, so with two sessions open in
  the same project, the first to exit stops it for both unless it was started with this.
- `--idle-hours H`: change the 12-hour idle limit. An open tab counts as a view. `--idle-hours 0`
  removes it; changing it needs a restart.

Mention these when the user asks how to get rid of a server they forgot, rather than suggesting
`kill`: `stop` also checks the pid really is the dashboard before signalling it.

If start fails because the port is taken, report it and suggest `--port`. Do not pick a port
silently: the owner's bookmark depends on it.

## refresh

`sdd-report`. Regenerating rewrites the file, which reloads every open tab. If it fails on a
missing marker, say which one and restore it from
`${CLAUDE_PLUGIN_ROOT}/skills/dashboard-upkeep/report-template.html`. Do not delete the report to get
past the error: that throws away every hand-written section.

## status

`sdd-dashboard status`. Running: the URL, the content and state directories, and when it will
stop (idle limit, session binding, or only on `stop`). Stopped: when and why, from its last stop
(`sdd-dashboard stop`, the session ending, or the idle limit). It exits non-zero when stopped, which
is the answer, not an error. Relay it as one or two lines.

## url

`sdd-dashboard url`. It exits non-zero and says so when the server is not running; say that
rather than handing over a dead link.

## stop

`sdd-dashboard stop`. The content directory and the saved port and key stay, so the next start
hands out the same URL. `sdd-dashboard status` says when and why a stopped server stopped.
