# Practice Rules

**Never put planning identifiers in committed code.** Not phase numbers, task IDs, spec
filenames or plan paths, in source, comments, migration filenames, commit messages or PR
descriptions. Planning documents live somewhere the main repo ignores, so every such
reference is a dead pointer to anyone who only has the checkout. Write the actual
constraint, invariant or bug instead. When implementing from a plan, strip them before
saving.

**Development workflow.** Failing test first where the behaviour or bug can be captured. Run
only the related tests during development, the full suite at the end of a phase. Read existing
code and its tests before changing it. Format and lint before calling work done.

**Comments stand on their own.** A comment worth keeping explains *why*, using the real
constraint, not a pointer to a document nobody else can read.
