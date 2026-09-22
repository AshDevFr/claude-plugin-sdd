---
name: project-overview
description: Generate or refresh a comprehensive, human-readable project overview document by reading the codebase, implementation docs (PRD/specs/tasks), config, migrations, API surface, and frontend. The doc records git provenance (date, branch, commit, tag) in frontmatter so subsequent runs diff against the last-generated commit and update only what changed. Use when the user asks to create, generate, update, or refresh a project overview / architecture summary (e.g. from /sdd:project-overview).
---

# Project Overview Generator

Produce a single, authoritative `*-overview.md` that describes what a project *is* and *does*: its purpose, architecture, tech stack, API surface, data model, key subsystems, configuration, and deployment. The audience is a new engineer (or an LLM) who needs to understand the whole system without reading the source.

The document is **idempotent and provenance-stamped**. Every run records the git state it was generated from. A later run reads that stamp, diffs the repo against it, and updates only the parts that drifted, then re-stamps.

## What this is not

- Not a README (which is install/usage-oriented). The overview is descriptive and exhaustive.
- Not the PRD or plan (which are forward-looking). The overview describes the system *as it exists now*.
- Not auto-generated API reference. It is curated prose + tables, written for comprehension.

---

## Step 1: Resolve the document location and name

Determine where the overview lives, in this order:

1. **Explicit arg.** If the caller passed a path, use it.
2. **Existing doc.** Search the repo for an existing overview. Look for files matching `*-overview.md` (commonly under `.specs/`, `docs/`, or the repo root). Prefer one containing the `generator: project-overview` frontmatter key; if none has it but a plausible hand-written or pre-convention overview exists, **adopt that file** rather than creating a second one alongside it. Reuse the exact path. This is the update path.
3. **Default.** For a new doc, pick the directory in this preference order: `.specs/` if the project has a spec repo, else `docs/` if it exists and is tracked, else the repo root. Name the file `<project>-overview.md`, where `<project>` is the repo/directory name (lowercased, e.g. `tsundoku-overview.md`).

If the chosen default directory is gitignored (e.g. `tmp/`), mention that to the user so they know the doc will not be committed; offer `docs/` as an alternative.

Determine `<project>` from the workspace directory name unless the CLAUDE.md / Cargo / package metadata gives a clearer canonical name.

---

## Step 2: Capture git provenance

Before reading anything, snapshot the current git state. These commands are read-only:

```sh
git rev-parse --abbrev-ref HEAD          # branch
git rev-parse HEAD                        # full commit
git rev-parse --short HEAD                # short commit
git describe --tags --abbrev=0 2>/dev/null || true   # nearest tag (may be empty)
git describe --tags 2>/dev/null || true              # tag + distance (e.g. v1.6.1-3-g170c16a)
git status --porcelain                    # dirty working tree?
```

Use the harness date (today's date from context) for the `generated` field, not a shell date call. If the working tree is dirty, note it: the doc reflects uncommitted state, and the recorded commit will not fully describe the source.

---

## Step 3: If a doc already exists, decide create vs. update vs. up-to-date

Read the existing doc's frontmatter (see the schema in Step 6). Compare its `commit` to the current `HEAD`:

- **Same commit, clean tree** → the doc is current. Report "already up to date (generated <date> from <commit>)" and stop, unless the caller forced a regenerate. Do not rewrite an up-to-date doc.
- **Different commit (or dirty tree, or forced)** → this is an **update**. Compute what changed and refresh the doc:

  ```sh
  git log --oneline <prev_commit>..HEAD          # commits since last generation
  git diff --stat <prev_commit> HEAD             # files changed + churn
  ```

  Use the diff to target your re-reading: a change touching only `web/` means the frontend sections need attention; new files under `crates/td-*/` or `migration/` mean architecture/data-model sections do. Do not blindly rewrite the whole doc; preserve accurate prose and revise the sections the diff implicates. Still re-verify the high-level facts (tech-stack versions, CLI subcommands, route groups) in case they drifted.

  If `<prev_commit>` is unreachable (history rewritten / shallow clone), fall back to a full regeneration and say so.

- **Existing doc with no frontmatter** (hand-written, or written before this convention) → treat it as an **update**, but you have no recorded commit to diff from. Recover an anchor instead of giving up:

  ```sh
  git log -1 --format=%H --date=short -- <doc_path>          # last commit that touched the doc
  git log -1 --format=%H --before="<that date +1 day>" HEAD   # repo state at that time
  ```

  If the doc lives in a nested or separate repo (a gitignored spec repo, say), run the first command with `-C <that repo>` and use its date to find the anchor commit in the *code* repo. Diff from that anchor, and say in your report that the range is inferred from the doc's own history rather than a recorded stamp. If no anchor is recoverable, do a full pass and say so.

  Either way, preserve the existing prose that is still accurate: adopting a doc means revising it, not replacing it wholesale. Stamp frontmatter on the way out and seed the changelog.

- **No existing doc** → this is a **create**. Do a full pass (Steps 4–5).

---

## Step 4: Gather the material

Read broadly before writing. Prioritize breadth over depth; you are mapping the system, not auditing it. For a large repo, delegate fan-out reading to subagents (the Explore agent) and synthesize their findings.

Sources, in rough priority:

1. **Project instructions** — `CLAUDE.md` (root and any nested), `README.md`, `AGENTS.md`. These often state the architecture and key design decisions directly; lean on them heavily but verify against code.
2. **Implementation docs** — the PRD, per-phase specs, and tasks. Resolve their location from the CLAUDE.md `## Task Workflow` section (or the `.specs/docs/` spec repo). These give intent, phase status, and design rationale. Note: these are often gitignored/local-only — use them for understanding but do not assume the reader can open them.
3. **Workspace / module layout** — `Cargo.toml` / `package.json` / `go.mod` / etc. Enumerate crates/packages/modules and their roles. The repository layout section of CLAUDE.md is a strong starting point.
4. **CLI surface** — the arg parser (clap derive, commander, argparse). List every subcommand with a one-line description.
5. **API surface** — routers and route registrations. Group endpoints by concern. For utoipa/OpenAPI projects, the spec or the `#[utoipa::path]` annotations enumerate routes. Note auth requirements and any non-REST surfaces (SSE, WebSocket, GraphQL, OPDS, gRPC).
6. **Data model** — ORM entities and the migration history. The migration filenames + entity structs tell the domain story. List key tables/entities with a one-line purpose.
7. **Config** — the config struct + example config file + env-var conventions. Produce a table of sections and notable settings.
8. **Background work** — schedulers, cron jobs, task queues, workers, real-time streams.
9. **Frontend** — framework, routing, state, data fetching, key pages/routes, testing setup. Enumerate user-facing pages/routes if the UI is non-trivial.
10. **Deployment** — Dockerfiles, compose files, Helm charts, CI, release tooling (cargo-dist, etc.).
11. **Auth & security** — auth methods, RBAC/roles, encryption, secret handling.
12. **Status** — if the PRD/plan has a phase table, summarize current completion honestly (what's done, what's in progress, what's not started). Derive from the docs and corroborate with code; do not overstate completeness.

When the code contradicts a doc (CLAUDE.md says X, code does Y), trust the code and describe reality. Flag significant contradictions to the user in your final summary.

---

## Step 5: Write the document

Match the structure and register of a polished system-overview doc. Use the section set below as a menu, not a mandate: include the sections that apply, in a sensible order, and omit those that do not (a CLI tool has no frontend; a library has no deployment story). Lead with a tight 2–4 sentence abstract that says what the project is, who it's for, and its single most important architectural choice.

### Recommended section menu

- **Title + abstract** — `# <Project> - <one-line positioning>` then the abstract paragraph.
- **Supported formats / inputs / backends** — if the project is defined by what it ingests or plugs into.
- **Architecture** — backend language/framework/runtime/DB, frontend stack, the binary/process shape, key traits/abstractions. Subsection per tier.
- **CLI commands** — table of subcommands.
- **API layer** — one subsection per surface (REST, SSE, OPDS, compat layers…), endpoints grouped by concern.
- **Authentication & authorization** — methods, OIDC, RBAC roles table, rate limiting.
- **Core domain subsystems** — one `##` section per major feature area (e.g. for tsundoku: discovery sources, resolution pipeline, metadata providers, review queue, scheduler). This is the heart of the doc — explain how each works, not just that it exists.
- **Real-time features** — SSE/WS streams and their event types.
- **Background tasks / scheduling** — queue, task types, cron jobs.
- **Configuration** — table of config sections + notable settings; env-var prefix and nesting convention.
- **Deployment** — Docker, binaries, scaling model.
- **Data model** — key entities/tables with one-line purposes.
- **Tech stack summary** — condensed bullet list.
- **Current status** — phase table with honest status, if applicable.
- **Changelog** — always last, always present. See Step 6b.

### Style

- Tables for enumerable things (commands, routes, roles, config sections, task types, entities).
- Prose for explaining *how* a subsystem works and *why* a design choice was made.
- Concrete: name the actual crates, traits, tables, routes, env vars, file paths. A reader should be able to grep for any noun you use.
- No em dashes (use commas, parentheses, semicolons, colons, or separate sentences).
- Honest about scope and status. If something is "reserved for a future phase" or "currently unused," say so. Do not describe aspirations as if shipped.
- Do not reference internal plan/phase/task identifiers as if the reader can open them. Translate intent into standalone description.

---

## Step 6: Stamp the provenance frontmatter and changelog

Every generated doc carries two provenance elements, and **both are required**: frontmatter at the top recording the git state it was generated from, and a `## Changelog` at the bottom recording how it got here. The frontmatter is the machine contract the next run diffs against; the changelog is the human-readable revision trail. A doc with one and not the other is incomplete.

### 6a: Frontmatter

Every generated doc begins with YAML frontmatter recording exactly what it was generated from. This is the contract the next run diffs against. Keep the keys stable.

```markdown
---
title: <Project> Overview
generator: project-overview
generated: 2026-05-30
branch: main
commit: 170c16a
commitFull: 170c16ae3f...d9
tag: v1.6.1
dirty: false
---

# <Project> - <positioning line>

<abstract>
...
```

Field rules:

- `generator: project-overview` — the discriminator that marks this as a generated overview and makes it findable on the next run. Never change it.
- `generated` — the date from the harness context (YYYY-MM-DD).
- `branch` / `commit` / `commitFull` — from Step 2.
- `tag` — nearest tag from `git describe --tags --abbrev=0`; omit the key (or set `null`) if the repo has no tags.
- `dirty: true` — set only when the working tree had uncommitted changes at generation time, so a reader knows the recorded commit is an approximation.

On an **update**, overwrite all of these with the new run's values.

### 6b: Changelog

The last section of the doc is always `## Changelog`: a reverse-chronological list (newest first) of what each generation run changed. It tells a reader whether the doc has kept pace with the code, and tells the next run what the previous one already covered.

One entry per run, in this shape:

```markdown
## Changelog

- **2026-08-14** (`51b27c9..90172b9`, 116 commits): Added provenance frontmatter and a repository/crate layout table. New sections for Want to Read / Collections / Read Lists, instance Export-Import-Copy, and read history. Rewrote Observability around OpenTelemetry. Updated CLI commands, bundled plugin table, task types, config sections, and the data model.
- **2026-06-26** (initial): First generation at `v1.38.0`.
```

Entry rules:

- **Date** in bold, matching the `generated` frontmatter field.
- **Commit range** in backticks (`<prev_short>..<new_short>`) plus the commit count, so the reader can reproduce the diff. On a create, write `(initial)` and name the version or tag generated from.
- **Body** names the sections added, rewritten, and updated, in that order of significance. Name actual section titles: "Rewrote Observability" is useful, "updated various sections" is not. Two to four sentences; this is a footnote, not a second copy of the doc.
- On a **create**, seed the section with the single initial entry. Do not skip it because there is no history yet, since that is what makes the second run's append trivial.
- On an **update**, prepend the new entry and **keep the existing ones**. Never rewrite history: if a past entry is now inaccurate, that is still what that run did.
- Cap the list at roughly the 10 most recent entries. When it grows past that, drop the oldest, replacing them with a single `- **Earlier**: initial generation and N intermediate updates.` line so the trail's depth is still visible.
- If a run finds the doc already up to date, add nothing. The changelog records changes, not visits.

---

## Step 7: Report back

Tell the user concisely:

- Path of the doc, and whether it was **created**, **updated**, or **already up to date**.
- The provenance stamped: date / branch / commit / tag.
- For an update: the commit range diffed and which sections were revised. If the range was inferred from the doc's own git history rather than a recorded stamp, say so.
- Any contradictions between docs and code you found, or facts you could not verify.
- If the doc landed in a gitignored directory, remind the user it will not be committed.

Do not commit the doc unless the user explicitly asks.
