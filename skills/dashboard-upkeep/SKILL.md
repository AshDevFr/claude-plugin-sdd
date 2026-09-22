---
name: dashboard-upkeep
description: How to keep a project's live dashboard honest, what each hand-written section must say, when to regenerate, and where captures and mockups go. Use after starting a dashboard with /sdd:dashboard, after every task commit in a project that has one, and when publishing screenshots or mockups for the owner.
---

# Keeping the dashboard honest

The dashboard exists so the owner can see where the project stands from another machine without
asking. It is worth exactly as much as it is current. A page that is right about the commits and
a week stale about what is blocked is worse than no page, because it reads as current.

`sdd-dashboard path` prints the dashboard directory. The page is `content/report.html`; images and
other pages go beside it in `content/`.

## Two kinds of region

- **Generated**, between `<!--GEN:name-->` and `<!--/GEN:name-->`: `generated` (the stamp),
  `plans` (phase specs, plans with task progress from the subagent ledger, designs, task files),
  `commits`, `tests` and `inprogress`. `sdd-report` rewrites these. Never edit inside them, and
  never write a commit list by hand anywhere on the page: a hand-kept one was the first thing
  found wrong.
- **Hand-written**, everything else. `sdd-report` leaves it alone, so it is only as current as
  the last time you edited it.

If `sdd-report` fails on a missing marker, restore the marker from `report-template.html` beside
this file. Never delete the report to make the error go away.

## What the hand-written sections must say

Replace every `class="todo"` placeholder. A placeholder left in place is a visible gap, which is
honest; invented content to fill it is not.

- **Waiting on you.** The first card, shown full width at the top and flagged by a *Needs you*
  chip in the bar, because the owner should never have to scroll to learn something is expected
  of them. Everything the owner alone can unblock goes here, and nowhere else first: a design or
  mockup to approve (with its `/view/` link), a question, a decision to confirm. Keep the most
  urgent item first. Write "Nothing" when that is true, which turns the card quiet and hides the
  chip; leaving an item there once it is answered trains the owner to ignore it.
- **Status cards.** *Play / try it* is yours: a working link to the running build, or the exact
  command to run it.

  *Tests* and *In progress* are **generated and must not be typed**. Tests reads the newest
  `evals/results/*/meta.json`; where there is none it says "never run here", which is a true and
  useful thing for the owner to see. In progress lists the task files whose Status says so.

  Both were hand-written until 2026-09-16, and that is why they are not any more: the rule to
  keep them current already existed in this skill, and it did not hold on its author. A rule
  already broken by the person who wrote it is not a control.
- **Where things stand.** One row per area of the product, a pill, and one line on what works and
  what does not.
- **Current plan.** The active plan's tasks with state and the evidence for each: a commit, a test
  run or a capture. A task without evidence is not done.
- **Decisions I made for you (overrule any).** Every choice made on the owner's behalf that they
  might have made differently: a library, a scope cut, a default, a workaround. One-line why each.
  This table is how the owner finds out about a decision in time to overrule it, so err towards
  listing.
- **Known issues.** Including problems the owner reported, and for each whether the live build
  still has it. Check the build before writing "fixed"; a fix merged is not a fix deployed.
- **Screenshots.** Captured from the real product, current, each with a caption saying what it
  shows and when it was taken. Use the `.shots` grid, and `.shots phone` for phone captures. Any
  capture in a `<figure>` opens full size when clicked, carrying its caption with it, so a wide
  screenshot does not have to be legible at thumbnail size to be worth publishing.
- **Mockups.** Links to mockup pages published beside the report (`/view/<name>`), each marked as
  a mockup so nobody mistakes it for the product.

Pills: `done` green, `running` or `partly` amber, `queued` grey, `blocked` red.

## When to update

- **After every task commit**, run `sdd-report`. The plugin's PostToolUse hook already does this
  when a Bash call runs `git commit`, but the hand-written sections are yours: update *Now
  running*, *Current plan* and *Tests* in the same breath.
- **After publishing captures or mockups**: copy the files into `content/`, add them to the page
  (`<img src="/files/<name>">` for a capture, a link to `/view/<folder>/<page>.html` for a
  mockup), then run `sdd-report`. A mockup that asks the owner to choose also needs its own
  copy of `picks.js` in the folder.
- **When a decision is taken or an issue is found or fixed**, edit the table then, not at the end
  of the session.

Pages other than the report never replace it: `/` always serves the report, and the Pages menu
in the bar lists every other page newest first, a mockup folder's pages grouped together.

A page that is its own HTML document keeps its own head and styles, so it is served as written
rather than wrapped in the frame: that is what lets a mockup render identically from a spec repo
clone. It gets a small nav injected at the top right instead, a link home and the same page list,
so there is still a way back. Leave the top right of a mockup clear.

## Layout

The report carries no styles of its own; the server's frame supplies them. Each top-level `h2`
becomes a foldable section, listed with its `h3`s in the *On this page* index (a sidebar on a wide
screen, a dropdown on a phone). So keep one `h2` per section, put sub-headings in `h3`, and do not
nest the report's sections inside wrappers, or they drop out of the index.

## Asking the owner to choose on a mockup

A mockup that offers alternatives is worth more when the owner can answer on the page instead of
describing which one they meant. `picks.js`, beside this plugin's other scripts, turns marked-up
options into Pick buttons and builds a prompt for the owner to paste back. Copy it into the
mockup folder and load it relatively, so the same folder works served and opened from a clone:

```html
<script src="picks.js" defer></script>

<section data-pick-group="music-warm" data-pick-label="Music: the warm half (spring and summer)">
  <article data-pick-option="with-the-wind"><h3>With the wind (seamless)</h3>
    <p>A 72 s seamless loop, short enough that it needs silence between plays.</p></article>
  <article data-pick-option="sun-and-moon"><h3>Sun and moon</h3>
    <p>About 2 min 50, the longest of the warm set.</p></article>
</section>
```

Write the options only. The buttons, the per-group note box, the summary and the generated prompt
are added for you, and picks survive the reload that follows every republish.

- `data-pick-label` on a group overrides its heading; an option takes its own heading, then its text.
- `data-pick-multi` on a group allows more than one, `data-pick-note="off"` drops its note box.
- Ids are `[a-z0-9][a-z0-9_-]{0,63}`, unique per page for groups and per group for options. A
  malformed or duplicate id is refused with a console warning and that group does not appear.
- Give each option a short line saying what it costs or implies. A choice between two names with
  no consequences attached is not a decision the owner can make.

**The server never receives the answer, and that is deliberate.** It stays read-only. An endpoint
that fed picks into a session's context would be reachable by anyone who can reach port 8765, so
the answer travels back through the owner's own prompt, where it is already trusted. Say where the
page is and that the Pick buttons build something to paste; do not describe it as sending anything.

**When picks come back**, act on them in the same turn: empty the matching item out of *Waiting on
you*, add anything you decided on their behalf to *Decisions I made for you*, and record the
choices under the design in the spec repo. With nothing stored anywhere, an answer that is not
written down survives only in the transcript.

## Mockups also go into the spec repo

The dashboard directory is outside every repository and is not a record. Commit each mockup set to
the spec repo as well, under `.specs/docs/designs/mockups/<YYYY-MM-DD>-<topic>/`, with image paths
relative to the mockup's own HTML file (`<img src="login.png">`) so it renders from a clone, and
`picks.js` in the folder when the set asks the owner to choose. Commit with `git -C .specs` in the
same turn, like every spec repo change. The copy in the set is the one that runs, so an archived
mockup keeps working whatever the plugin does later.

Then copy the same folder, unchanged, into the dashboard's `content/`. Relative paths work there
too: the page is served at `/view/<date>-<topic>/<page>.html` and its images resolve beside it, so
the two copies stay byte-identical and neither needs its paths rewritten.
