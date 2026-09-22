# Evals

Regression tests for the plugins' behaviour. `commit-msg` had run 1,567 times with no
test that it still behaved; this is the first.

```sh
./evals/run.sh                      # every case, 3 runs each
RUNS=1 ./evals/run.sh               # cheaper smoke pass
FILTER=feature ./evals/run.sh       # one case
THRESHOLD=0.66 ./evals/run.sh       # tolerate one failing run
SKIP_TAGS= ./evals/run.sh           # include the self-test, which must fail
```

Exits non-zero when any case scores below the threshold, so it can gate a build.

## Why not `claude plugin eval`

That is the right tool. It is native, reads `evals/**/case.yaml`, and its
`--ablation with-without` mode reports the score delta against a no-plugin arm, which
answers "does this plugin help" rather than just "did it pass". It is **gated behind
early access** and refuses on this account, so its case schema cannot even be learned.

This runner is the fallback. **Port the cases if access arrives**; the ablation delta is
the one capability this cannot provide.

## pass^N, not pass rate

75% per trial is about 42% across three consecutive trials, so a single green run is not
evidence. `RUNS` defaults to 3 and the threshold gates on pass^N, matching the native
tool's default.

## Grading is deterministic and free

`grade.py` matches `must_match` and `must_not_match` patterns against the run's `result`, or
against the file the run wrote when the case sets `artefact`. A single grader can override that
with `"source": "reply"` or `"source": "artefact"`, which is how one case checks both what a
command said it found and what it actually wrote.

## Which copy of the plugin is tested

`run.sh` passes `--plugin-dir <repo>/plugins/<plugin>`, so a run loads **this checkout**. It did
not before 2026-09-16, and every run until then graded whatever was installed under
`~/.claude/plugins/`. That was measured rather than assumed: with `commands/commit-msg.md`
deliberately inverted in the working tree to demand a count, a run without the flag passed, and
the same run with it failed on `no-counts` finding "1 file".

The case may name its plugin with `"plugin": "toolkit"`. Otherwise the longest prefix of the case
filename that names a command or a skill decides, which is how `rust-bootstrap` resolves to
`toolkit` while `commit-msg-feature` resolves to `sdd`.

## What a results directory records

Each run writes `results/<stamp>/meta.json`: the commit tested, whether each plugin's tree was
clean, the CLI version, `RUNS`, `FILTER`, the threshold, how many cases ran, and whether the
suite passed. It is written only when the suite finishes, so an interrupted run leaves none and
cannot be mistaken for a baseline.

## Graders that cannot fail

`python3 evals/grade.py --lint evals/cases/*.json` reports a `must_match` that already matches the
case's own prompt, or the artefact as the fixture leaves it before any model runs, and a
`must_not_match` that cannot catch the `violating_example` the case supplies. Nine graders across
eight cases were in that state when it was first run.

Where a pre-run match is the point rather than a defect, say so in the grader with
`"lint_ignore": "<reason>"`: `implement-existing-summary`'s `log-not-renamed` checks that a
heading *survives*, so it must be there beforehand. The lint runs in `scripts/check-deployment.sh`
and costs no model call.

## The free layer underneath

`scripts/check-prompt-contracts.sh` greps every command, skill and rules file for the phrases
whose absence was a defect, listed with their reasons in `scripts/prompt-contracts.json`. It
takes no model call and no money, so it runs on every change while the suite here runs by hand.

The division of labour is worth stating, because the two can look like the same check. A
contract proves a sentence is still in the file. Only a run here proves the sentence still does
anything. What contracts actually buy is the regression this repository kept hitting: a
load-bearing line trimmed away while making room for something else, found weeks later by a paid
run, or not at all.

## Before a release

`scripts/check-evals-fresh.sh <plugin>` refuses a plugin whose files have changed since the last
run that tested them. It counts a results directory as a baseline only if the suite finished,
passed, ran unfiltered, and ran against a clean tree for that plugin.
No judge model, so grading costs nothing and cannot drift.

Python rather than grep because the patterns use inline flags like `(?i)` and `(?s)`.
macOS grep has no `-P` at all, and a grep-based grader silently reported every
`must_match` as missing and every `must_not_match` as ok. The second is a false green,
which is why the grader has its own unit checks that run without calling a model.

## Anchor every prohibition

A `must_not_match` pattern that looks for a bare phrase will fire on the model *discussing*
the thing it is forbidden from *doing*. This cost four paid runs before the pattern was
obvious:

| Pattern | Fired on | Which was |
|---|---|---|
| `co-authored-by` | "I left out the `Co-Authored-By` trailer" | compliance |
| `four tests` | "all four tests will fail with NameError" | code review |
| `docs/superpowers` | "none of `docs/superpowers/` exist, so nothing to migrate" | a preflight check |
| `marked Complete` | "Task 1.01 is marked Complete against this same script" | an observation |

Anchor to the **actor** (`^\s*co-authored-by`, `\bI (have )?marked\b`) or to the
**artefact** (grade the file, not the transcript). Never to the bare phrase.

## The self-test

`cases/SELFTEST-always-fails.json` carries a grader that cannot pass. It is tagged
`selftest` and skipped by default. Run it with `SKIP_TAGS=` to confirm the suite still
reports red: a suite that has never failed is one nobody knows works.

## Cost

Every run is a real model call, about $0.33 each. Three cases at three runs is roughly
$3. `RUNS=1` is the cheap pass while iterating on case definitions.

## Why this is not shipped inside the plugin

The practice atlas's W8 line proposed adding the eval suite to the plugin, so that anyone
installing `sdd` gets it. **Declined, deliberately.**

The suite needs the cases, the fixtures, the `claude` CLI and paid runs, and what it tests is
*this marketplace's own plugins*: whether `/sdd:quick` writes one dated entry, whether
`/sdd:implement` runs its Verification command. Shipping it inside `sdd` hands a colleague a
script that tests nothing of theirs, costs them money to discover that, and adds a directory of
fixtures to every install.

What is portable is the idea, and the pieces of it that are: `grade.py --lint` catches a grader
that cannot fail in any suite, and `check-evals-fresh.sh` gates a release on a measurement in any
repository that has one. Those are scripts in this repository that someone can copy. The cases
are not.

The cost of declining is real and worth naming: a colleague who edits an `sdd` skill on their own
machine has no way to measure the edit, and the improver tells them so and stops rather than
proposing something ungated.
