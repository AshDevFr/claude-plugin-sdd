---
argument-hint: "[output-path] [--force]"
description: Generate or refresh a provenance-stamped project overview document
---

Generate (or refresh) a comprehensive project overview document for the current repository.

## Arguments

The arguments arrive as one string in `$ARGUMENTS`. Read them from there:

- **the output path** — all of `$ARGUMENTS` except any `--force` flag

**Do not rely on `$1` or `$2`.** Measured 2026-09-16: invoked through the Skill tool, `$1`
binds to the **second** token, and typed as a slash command it arrives as the literal text
`$1`. Neither is the first argument. `$ARGUMENTS` is correct on both paths.

**Output path (optional)**: from `$ARGUMENTS` — where the overview should live. If omitted, an existing generated overview is reused, or a sensible default is chosen.

Invoke the **`sdd:project-overview`** skill and follow it end to end. The skill:

1. Resolves the doc location/name (reuses an existing `*-overview.md` carrying the `generator: project-overview` frontmatter, else picks `docs/` → `tmp/` → repo root).
2. Snapshots git provenance (branch, commit, nearest tag, dirty state) and the harness date.
3. If a doc already exists: compares its stamped commit to `HEAD`. **Same commit + clean tree → reports "already up to date" and stops** (unless `--force` is passed). Otherwise diffs `prev_commit..HEAD` and updates only the sections the change implicates.
4. If no doc exists: reads the codebase, implementation docs (PRD/specs/tasks), CLI, API surface, data model, config, background work, frontend, and deployment, then writes a full overview.
5. Stamps the provenance frontmatter (`generated`, `branch`, `commit`, `commitFull`, `tag`, `dirty`) so the next run can diff.
6. Reports what it did (created / updated / up to date), the provenance, and any doc-vs-code contradictions it found.

**Arguments:**

- the path in `$ARGUMENTS` — explicit output path for the doc. Overrides auto-detection.
- `--force` (anywhere in `$ARGUMENTS`) — regenerate even if the doc is already current for `HEAD`.

Do not commit the doc unless explicitly asked.
