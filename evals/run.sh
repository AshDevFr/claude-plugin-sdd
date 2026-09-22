#!/usr/bin/env bash
# Run the eval cases under evals/cases/ and report pass rate, pass^N and cost.
#
# Why this exists rather than `claude plugin eval`: that command is native, takes
# evals/**/case.yaml, and its --ablation mode reports a with/without-plugin score
# delta, which is the question worth asking. It is gated behind early access and
# refuses on this account, so its case schema cannot even be learned. This is the
# fallback the practice atlas suggested. Port the cases if access arrives.
#
# pass^N is the honest number: 75% per trial is about 42% across three trials, so a
# single green run is not evidence. N defaults to 3, matching the native tool.
#
# Needs bash, git, jq and the claude CLI.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
RUNS=${RUNS:-3}
THRESHOLD=${THRESHOLD:-1.0}
FILTER=${FILTER:-}
SKIP_TAGS=${SKIP_TAGS-selftest}
# OUTDIR resumes an existing results directory instead of starting a new one. A full baseline is
# half an hour of paid runs, and losing all of it to one interruption has happened; a case that
# already has a .status file is skipped, so a killed run costs at most the case it was on.
if [ -n "${OUTDIR:-}" ]; then
  outdir="$OUTDIR"
  stamp=$(basename "$outdir")
else
  stamp=$(date +%Y%m%d-%H%M%S)
  outdir="$here/results/$stamp"
fi
mkdir -p "$outdir"

lab=$(mktemp -d)

# Each run is a fresh temp repo, and the CLI records a transcript directory per project under
# ~/.claude/projects keyed by the working directory. Those outlive the temp repo they describe.
# Measured 2026-09-16: 278 of 283 directories there were this suite's leavings, 1.4 GB in all,
# accumulated because nothing had ever removed them. Only paths under this run's own lab are
# touched, so a real project's transcripts cannot be caught by it.
cleanup_transcripts() {
  local base="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects" slug
  [ -d "$base" ] || return 0
  # The CLI flattens the working directory into a name, replacing both / and . with -, so
  # /tmp/tmp.0Lj2BT becomes -tmp-tmp-0Lj2BT. Getting only the slash wrong silently cleans nothing.
  slug=$(printf '%s' "$lab" | sed 's|[/.]|-|g')
  find "$base" -maxdepth 1 -type d -name "${slug}*" -exec rm -rf {} + 2>/dev/null || true
}
trap 'cleanup_transcripts; rm -rf "$lab"' EXIT

# Which plugin a case exercises, so the run loads THIS checkout rather than whatever is
# installed. Measured 2026-09-16: with commit-msg.md deliberately inverted in the working tree,
# a run without --plugin-dir passed, because the installed copy under
# ~/.claude/plugins/marketplaces/ is a separate clone. Every eval before this change graded the
# installed plugin, so "apply the edit, re-run the case" ran the same copy twice.
#
# The case may name its plugin; otherwise the longest prefix of its basename that names a
# command or a skill decides, which is how rust-bootstrap resolves to toolkit rather than sdd.
case_plugin() {
  local name=$1 d
  while [ -n "$name" ]; do
    for d in "$repo_root"/plugins/*/; do
      if [ -f "$d/commands/$name.md" ] || [ -d "$d/skills/$name" ]; then
        basename "$d"
        return 0
      fi
    done
    case "$name" in *-*) name=${name%-*} ;; *) break ;; esac
  done
  echo sdd
}

total_cost=0
suite_fail=0
ran_cases=0
summary=()
declare -A plugins_tested=()
declare -A plugin_cases=()
declare -A plugin_passed=()

for case_file in "$here"/cases/*.json; do
  name=$(jq -r '.name' "$case_file")
  tags=$(jq -r '(.tags // []) | join(",")' "$case_file")
  base=$(basename "$case_file" .json)

  if [ -n "$FILTER" ] && [[ "$base" != *"$FILTER"* ]]; then continue; fi
  if [ -n "$SKIP_TAGS" ] && [ -n "$tags" ]; then
    for t in ${SKIP_TAGS//,/ }; do
      [[ ",$tags," == *",$t,"* ]] && { echo "SKIP  $name (tag: $t)"; continue 2; }
    done
  fi

  fixture=$(jq -r '.fixture' "$case_file")
  prompt=$(jq -r '.prompt' "$case_file")
  case_runs=$(jq -r ".runs // $RUNS" "$case_file")
  mapfile -t tools < <(jq -r '.allowed_tools[]?' "$case_file")
  n_graders=$(jq -r '.graders | length' "$case_file")
  plugin=$(jq -r '.plugin // empty' "$case_file")
  [ -n "$plugin" ] || plugin=$(case_plugin "$base")
  plugin_dir="$repo_root/plugins/$plugin"
  # A published single plugin has no plugins/ directory: the repository root is the plugin. The
  # case files are unchanged either way, which is the point of resolving it here.
  [ -d "$plugin_dir" ] || plugin_dir="$repo_root"
  plugins_tested[$plugin]=1
  plugin_cases[$plugin]=$(( ${plugin_cases[$plugin]:-0} + 1 ))
  if [ ! -d "$plugin_dir" ]; then
    echo "FAIL  $name: no plugin directory at $plugin_dir"
    suite_fail=1
    continue
  fi

  if [ -f "$outdir/$base.status" ]; then
    echo "DONE  $name (already in $stamp)"
    continue
  fi

  ran_cases=$((ran_cases+1))
  echo
  echo "CASE  $name"
  echo "      $case_runs run(s), $n_graders grader(s)"

  all_runs_green=1
  green_runs=0
  declare -A grader_fails=()

  for run in $(seq 1 "$case_runs"); do
    repo="$lab/${base}-$run"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" -c user.name=eval -c user.email=eval@example.com commit -q --allow-empty -m "chore: initial commit"
    "$here/fixtures/$fixture" "$repo" >/dev/null 2>&1

    json="$outdir/${base}-run$run.json"
    # --strict-mcp-config: no case uses an MCP tool (allowed_tools are Read/Write/Edit/Glob/Grep/
    # Bash, plus Task where a command's own instructions say to delegate), so loading the
    # author's MCP stack into every run buys nothing and costs
    # startup time and memory. A full baseline once died to memory pressure from it. It also made
    # results depend on which servers the author happened to have configured, which is not a
    # property the suite should have.
    ( cd "$repo" && printf '%s' "$prompt" | claude -p --output-format json \
        --plugin-dir "$plugin_dir" --strict-mcp-config \
        ${tools[@]+--allowedTools "${tools[@]}"} ) > "$json" 2>"$json.err"

    if ! jq -e . "$json" >/dev/null 2>&1; then
      echo "      run $run: FAIL (no parseable result; see $json.err)"
      all_runs_green=0; continue
    fi

    cost=$(jq -r '.total_cost_usd // 0' "$json")
    total_cost=$(python3 -c "print($total_cost + $cost)")
    is_err=$(jq -r '.is_error' "$json")
    result=$(jq -r '.result // ""' "$json")

    if [ "$is_err" = "true" ] || [ -z "$result" ]; then
      echo "      run $run: FAIL (is_error=$is_err, empty=$([ -z "$result" ] && echo yes || echo no))"
      all_runs_green=0; continue
    fi

    run_green=1
    while IFS=$'\t' read -r gid verdict detail; do
      [ "$verdict" = ok ] && continue
      run_green=0
      grader_fails[$gid]=$(( ${grader_fails[$gid]:-0} + 1 ))
      echo "         grader '$gid': $verdict, $detail"
    done < <("$here/grade.py" "$case_file" "$json" "$repo")

    if [ "$run_green" = 1 ]; then
      green_runs=$((green_runs+1)); echo "      run $run: pass  (\$$cost)"
    else
      all_runs_green=0; echo "      run $run: FAIL  (\$$cost)"
      # The lab is deleted when the suite exits, so a failed artefact grader would otherwise
      # leave nothing to read: the reply is kept in the run json, but the file the graders
      # actually judged is gone. Keeping it is what makes "read the failure before touching the
      # grader" possible for artefact cases at all.
      artefact=$(jq -r '.artefact // empty' "$case_file")
      # The path may be a glob, for the reason grade.py's artefact_text explains: a command that
      # creates a dated directory writes today's date, so a case pinning a literal date grades a
      # file that exists only on the day the case was written.
      # shellcheck disable=SC2086
      found=$(ls -1 $repo/$artefact 2>/dev/null | head -1)
      if [ -n "$artefact" ] && [ -n "$found" ] && [ -f "$found" ]; then
        cp "$found" "$outdir/${base}-run$run.artefact" 2>/dev/null
      elif [ -n "$artefact" ]; then
        printf 'the run did not write %s\n' "$artefact" > "$outdir/${base}-run$run.artefact"
      fi
    fi
  done

  rate=$(python3 -c "print(f'{$green_runs/$case_runs:.2f}')")
  passN=$([ "$all_runs_green" = 1 ] && echo 1.00 || echo 0.00)
  echo "      pass rate $rate   pass^$case_runs $passN"
  for gid in "${!grader_fails[@]}"; do
    why=$(jq -r --arg g "$gid" '.graders[] | select(.id==$g) | .why' "$case_file")
    echo "      failed grader '$gid' in ${grader_fails[$gid]}/$case_runs runs: $why"
  done
  summary+=("$(printf '%-52s rate %s  pass^%s %s' "$name" "$rate" "$case_runs" "$passN")")
  if python3 -c "import sys; sys.exit(0 if $passN >= $THRESHOLD else 1)"; then
    printf '%s\t1\n' "$plugin" > "$outdir/$base.status"
  else
    printf '%s\t0\n' "$plugin" > "$outdir/$base.status"
  fi
  unset grader_fails
done

# What was tested, so a results directory is evidence rather than a timestamp. Written at the
# end on purpose: an interrupted run leaves no meta.json, and so cannot satisfy the release
# freshness gate that reads it.
write_meta() {
  local trees="{}" results="{}" p state f total=0 green=0
  declare -A seen_cases=() seen_passed=()
  for f in "$outdir"/*.status; do
    [ -f "$f" ] || continue
    IFS=$'\t' read -r p ok < "$f"
    [ -n "$p" ] || continue
    seen_cases[$p]=$(( ${seen_cases[$p]:-0} + 1 ))
    seen_passed[$p]=$(( ${seen_passed[$p]:-0} + ok ))
    total=$((total+1)); green=$((green+ok))
  done
  for p in "${!seen_cases[@]}"; do
    state="clean"
    tracked="plugins/$p"
    [ -d "$repo_root/$tracked" ] || tracked="."
    [ -n "$(git -C "$repo_root" status --porcelain -- "$tracked")" ] && state="dirty"
    trees=$(jq -c --arg k "$p" --arg v "$state" '. + {($k): $v}' <<<"$trees")
    # Per plugin, because one plugin's flaky case should not block another's release. A toolkit
    # case at 0.67 held up an sdd tag once; that is the gate asking the wrong question.
    results=$(jq -c --arg k "$p" --argjson c "${seen_cases[$p]}" --argjson n "${seen_passed[$p]}" \
      '. + {($k): {cases: $c, passed: $n}}' <<<"$results")
  done
  ran_cases=$total
  [ "$green" -eq "$total" ] || suite_fail=1
  jq -n \
    --arg stamp "$stamp" \
    --arg head "$(git -C "$repo_root" rev-parse HEAD 2>/dev/null)" \
    --arg cli "$(claude --version 2>/dev/null | head -1)" \
    --arg filter "$FILTER" \
    --argjson runs "$RUNS" \
    --argjson threshold "$THRESHOLD" \
    --argjson cases "$ran_cases" \
    --argjson failed "$suite_fail" \
    --argjson trees "$trees" \
    --argjson results "$results" \
    '{stamp: $stamp, head: $head, claude_version: $cli, runs: $runs, filter: $filter,
      threshold: $threshold, cases: $cases, suite_passed: ($cases > 0 and $failed == 0),
      plugin_trees: $trees, plugin_results: $results}' \
    > "$outdir/meta.json"
}
write_meta

echo
echo "=============================================================="
# A suite that runs nothing and reports success is the same false green as a grader whose
# pattern engine is missing. A filter that matches no case is an error, not a pass.
if [ "$ran_cases" -eq 0 ]; then
  echo "NO CASES RAN"
  [ -n "$FILTER" ] && echo "  FILTER='$FILTER' matched nothing. Case names are the file basenames without .json."
  echo "SUITE FAIL (nothing to run)"
  exit 2
fi
printf '%s\n' "${summary[@]}"
printf 'total cost  $%.4f\n' "$total_cost"
echo "results     $outdir"
echo "threshold   $THRESHOLD on pass^N"
[ "$suite_fail" = 0 ] && echo "SUITE PASS" || echo "SUITE FAIL"
exit "$suite_fail"
