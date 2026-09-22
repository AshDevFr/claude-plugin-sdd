# Spec Repo Rules

This project has a nested spec repo, so the pipeline applies. Creating `.specs` is the act of
opting in, and the hooks test for that exact name.

**Commit `.specs/` in the same turn you edit it**, with `-C .specs` so the main repo's index
is untouched. A Stop hook refuses to end the turn otherwise and prints the command. **The
main repo stays manual**: never commit there unless asked.

**A Complete status means the verification command ran.** Each task file holds one runnable
`**Verification:**` command, and a Stop hook refuses a Complete status whose command did not run
**as its own command**: piped, behind `|| true`, or merely echoed all read as not run. It proves
the command ran, not that it still tests the task.

**Which lane does this change take?** Broken behaviour with a reproduction: `/sdd:bug`, which
diagnoses before it repairs. One sentence, one session, and done is obvious: `/sdd:quick`, one
dated entry and no task file. Otherwise the full pipeline. If you do not yet know what done looks
like, none of them: `/sdd:brainstorm` first, which ends at a design you approved and hands it on.
Guidance; nothing enforces it.

**For the layout, where artifacts go, the full rubric, and the worktree modes for giving an
agent the spec tree: `Skill("sdd:practices")`.**
