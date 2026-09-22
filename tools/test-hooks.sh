#!/usr/bin/env bash
# Drives spec-repo-guard.sh with the JSON it expects on stdin and asserts the
# exit code and emitted decision.
#
# Scratch repos are built from nothing on every run, so the assertions keep
# testing real git behaviour rather than a snapshot of it. The checked-in
# fixtures carry a __CWD__ placeholder because a cwd is machine-specific.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/plugin-root.sh
. "$here/plugin-root.sh"
guard="$SDD_PLUGIN/hooks/spec-repo-guard.sh"
fixtures="$here/fixtures"
[ -x "$guard" ] || { echo "FAIL: $guard is not executable"; exit 1; }

lab=$(mktemp -d)
trap 'rm -rf "$lab"' EXIT
pass=0; fail=0

. "$here/lib-lab.sh"

# run <name> <fixture> <cwd> <expect: silent|block>
run() {
  local name="$1" fixture="$2" cwd="$3" expect="$4"
  local json out rc
  json=$(sed "s|__CWD__|$cwd|" "$fixtures/$fixture")
  out=$(printf '%s' "$json" | "$guard" 2>&1); rc=$?
  local decision=""
  [ -n "$out" ] && decision=$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null)
  if [ "$expect" = silent ]; then
    if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
      echo "  PASS  $name (exit 0, no output)"; pass=$((pass+1))
    else
      echo "  FAIL  $name: expected exit 0 and no output, got rc=$rc out='${out:0:120}'"; fail=$((fail+1))
    fi
  else
    if [ "$decision" = block ]; then
      echo "  PASS  $name (decision: block)"; pass=$((pass+1))
    else
      echo "  FAIL  $name: expected decision=block, got rc=$rc decision='$decision'"; fail=$((fail+1))
    fi
  fi
}

echo "spec-repo-guard.sh"

r=$(mkrepo plain)
run "no .specs at all"          no-specs.json        "$r" silent

# A repeated Stop re-checks and blocks again while the work is still outstanding, then gives up
# visibly. The short-circuit this replaces made the guard a one-shot nudge: a second Stop always
# succeeded, whatever the turn did in between.
r=$(mkrepo active); mkspecs "$r" noremote dirty
sgsid="test-$$-specguard"
rm -f "${TMPDIR:-/tmp}/sdd-specguard-$sgsid".* 2>/dev/null
sgactive() { # sgactive <label> <cwd> <session> <expect block|warn>
  local label="$1" cwd="$2" sid="$3" expect="$4" out decision sysmsg
  out=$(jq -n --arg c "$cwd" --arg s "$sid" '{cwd:$c,stop_hook_active:true,session_id:$s}' | "$guard" 2>&1)
  decision=$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null)
  sysmsg=$(printf '%s' "$out" | jq -r '.systemMessage // empty' 2>/dev/null)
  case "$expect" in
    block) if [ "$decision" = block ]; then echo "  PASS  $label"; pass=$((pass+1))
           else echo "  FAIL  $label: expected block, got '$(printf '%s' "$out" | tr -d '\n' | cut -c1-90)'"; fail=$((fail+1)); fi ;;
    warn)  if [ -n "$sysmsg" ] && [ "$decision" != block ]; then echo "  PASS  $label"; pass=$((pass+1))
           else echo "  FAIL  $label: expected a systemMessage and no block, got '$(printf '%s' "$out" | tr -d '\n' | cut -c1-90)'"; fail=$((fail+1)); fi ;;
  esac
}
sgactive "stop_hook_active, 1st re-check" "$r" "$sgsid" block
sgactive "stop_hook_active, 2nd re-check" "$r" "$sgsid" block
sgactive "stop_hook_active, 3rd"          "$r" "$sgsid" warn

# A clean spec repo is silent on a repeated Stop too: the cap only applies to real outstanding work.
r=$(mkrepo active-clean); mkspecs "$r" noremote clean
out=$(jq -n --arg c "$r" '{cwd:$c,stop_hook_active:true,session_id:"x"}' | "$guard" 2>&1)
if [ -z "$out" ]; then echo "  PASS  stop_hook_active with nothing outstanding -> silent"; pass=$((pass+1))
else echo "  FAIL  stop_hook_active with nothing outstanding: got '${out:0:80}'"; fail=$((fail+1)); fi

r=$(mkrepo clean);  mkspecs "$r" noremote clean
run "clean .specs, no remote"   clean-specs.json     "$r" silent

r=$(mkrepo clean2); mkspecs "$r" remote   clean
run "clean .specs, pushed"      clean-specs.json     "$r" silent

r=$(mkrepo dirty);  mkspecs "$r" noremote dirty
run "uncommitted .specs"        dirty-specs.json     "$r" block

r=$(mkrepo ahead);  mkspecs "$r" remote   unpushed
run "unpushed .specs commits"   unpushed-specs.json  "$r" block

# The -e test is on .specs/.git, which resolves through a symlink. Phase 4's
# link mode depends on this, so pin it here rather than discovering it later.
r=$(mkrepo viasym); mkspecs "$r" noremote dirty
real="$lab/viasym/.specs"; mv "$real" "$lab/specs-real"; ln -s "$lab/specs-real" "$real"
run "dirty .specs via symlink"  dirty-specs.json     "$r" block

# --- emit-practice-rules.sh -------------------------------------------------
emitter="$SDD_PLUGIN/hooks/emit-practice-rules.sh"
echo
echo "emit-practice-rules.sh"
# Run from a scratch repo that HAS a spec repo, never from the harness's own cwd.
#
# This section used to invoke the emitter in place. On the author's Mac that cwd is this
# repository, which has .specs/.git, so the spec-repo half of the emission was present and the
# assertions passed. Run anywhere else (a copied tree, CI, a clone without .specs) the emitter
# correctly emits only the universal rules, 879 chars instead of 2042, and the commit-obligation
# assertion failed. The emitter was right on both platforms; the test was reading ambient state
# and calling it a result. Found by running this suite on Linux for the first time.
epr=$(mkrepo emit-practice); mkspecs "$lab/emit-practice" noremote clean
if [ -x "$emitter" ]; then
  out=$( cd "$lab/emit-practice" && "$emitter" < /dev/null 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL  exits 0: got rc=$rc"; fail=$((fail+1))
  else
    echo "  PASS  exits 0"; pass=$((pass+1))
  fi
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1; then
    echo "  PASS  emits hookSpecificOutput.hookEventName = SessionStart"; pass=$((pass+1))
  else
    echo "  FAIL  wrong JSON shape for a Claude Code SessionStart hook"; fail=$((fail+1))
  fi
  ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
  # The full command is printed by the guard when it blocks, so the ambient text only has
  # to establish the obligation and the -C form.
  if printf '%s' "$ctx" | grep -q -- '-C .specs'; then
    echo "  PASS  context carries the spec-repo commit obligation"; pass=$((pass+1))
  else
    echo "  FAIL  context is missing the spec-repo commit obligation"; fail=$((fail+1))
  fi
  # This asserted a 2,048-character truncation cap, on the belief that the channel cut anything
  # larger down to a preview. Measured 2026-09-16 by quote-back and it is not true: a marker at
  # byte 12,060 of a 12,080-character emission came back verbatim, as did one at the end of a
  # 6,581-byte plugin emission. The 2KB figure is almost certainly the transcript UI's preview,
  # mistaken for the context. See docs/analysis/2026-09-16-context-emission-cap.md.
  #
  # The budget stays, for the reason that actually applies: this text is paid for on every
  # session in every project, and sdd's always-on cost was measured at 1,237 tokens. 4,000
  # characters is roughly 1,000 tokens of ambient rules, which is as much as always-on guidance
  # can justify. Exceeding it is a cost decision to argue for, not a silent failure.
  if [ "${#ctx}" -le 4000 ]; then
    echo "  PASS  the emission stays inside its token budget (${#ctx} chars)"; pass=$((pass+1))
  else
    echo "  FAIL  the emission is ${#ctx} chars; over the 4,000-char always-on budget"; fail=$((fail+1))
  fi
  # These sections stay in the personal layer and must not ship in the plugin.
  leaked=""
  for s in "Writing Style" "Be Honest and Critical" "Web Access" "## Delegation"; do
    printf '%s' "$ctx" | grep -qi "$s" && leaked="$leaked '$s'"
  done
  if [ -z "$leaked" ]; then
    echo "  PASS  no personal-layer section leaked into the plugin's rules"; pass=$((pass+1))
  else
    echo "  FAIL  leaked:$leaked"; fail=$((fail+1))
  fi
  # A plugin that must install alone cannot name a specific agent.
  if printf '%s' "$ctx" | grep -qE '\b(scout|test-runner|code-reviewer|architect)\b'; then
    echo "  FAIL  names a specific agent; sdd must describe delegation generically"; fail=$((fail+1))
  else
    echo "  PASS  names no specific agent"; pass=$((pass+1))
  fi
  # Absolute paths into the dotfile layer would break a standalone install.
  if printf '%s' "$ctx" | grep -q '~/\.claude/'; then
    echo "  FAIL  names a path under ~/.claude"; fail=$((fail+1))
  else
    echo "  PASS  names no path under ~/.claude"; pass=$((pass+1))
  fi
else
  echo "  FAIL  $emitter is not executable"; fail=$((fail+1))
fi

# --- emit-practice-rules.sh: conditional spec-repo section -----------------
# The spec-repo rules are the bulk of the text and apply only where a nested spec
# repo exists. Emitting them elsewhere is paid for on every message of every
# session, so both branches are pinned here.
echo
echo "emit-practice-rules.sh: conditional emission"
r=$(mkrepo nospecs)
with=$( (cd "$lab/nospecs" && "$emitter" < /dev/null) | jq -r '.hookSpecificOutput.additionalContext')
if printf '%s' "$with" | grep -qi 'development workflow'; then
  echo "  PASS  universal rules emitted without a spec repo"; pass=$((pass+1))
else
  echo "  FAIL  universal rules missing without a spec repo"; fail=$((fail+1))
fi
if printf '%s' "$with" | grep -q 'Spec Repo Rules'; then
  echo "  FAIL  spec-repo rules emitted in a repo with no .specs: pure tax"; fail=$((fail+1))
else
  echo "  PASS  spec-repo rules withheld where there is no spec repo"; pass=$((pass+1))
fi

r=$(mkrepo hasspecs); mkspecs "$lab/hasspecs" noremote clean
both=$( (cd "$lab/hasspecs" && "$emitter" < /dev/null) | jq -r '.hookSpecificOutput.additionalContext')
if printf '%s' "$both" | grep -q 'Spec Repo Rules' && printf '%s' "$both" | grep -qi 'development workflow'; then
  echo "  PASS  both sections emitted where a spec repo exists"; pass=$((pass+1))
else
  echo "  FAIL  a section is missing where a spec repo exists"; fail=$((fail+1))
fi
if [ "${#both}" -gt "${#with}" ]; then
  echo "  PASS  the conditional section is the larger part (${#with} -> ${#both} chars)"; pass=$((pass+1))
else
  echo "  FAIL  conditional section did not add anything"; fail=$((fail+1))
fi

# The worktree rules were rewritten from one avoidance rule to three modes. These pin the
# rewrite so it cannot regress, and pin that the placeholder is substituted: a literal
# ${CLAUDE_PLUGIN_ROOT} or @PLUGIN_ROOT@ reaching the model is a path it cannot use.
# The modes and the full rubric moved out of the ambient emission into an on-demand skill,
# because the channel drops anything past 2KB. Assert them where they now live.
prac="$SDD_PLUGIN/skills/practices/SKILL.md"
if [ -r "$prac" ]; then
  grep -qF -- '--specs=none|link|worktree' "$prac" \
    && { echo "  PASS  the practices skill gives the three-mode usage line"; pass=$((pass+1)); } \
    || { echo "  FAIL  the practices skill lost the three-mode usage line"; fail=$((fail+1)); }
  grep -qi 'unsafe for two writers' "$prac" \
    && { echo "  PASS  the practices skill warns that link is unsafe for writers"; pass=$((pass+1)); } \
    || { echo "  FAIL  the practices skill lost the concurrency warning"; fail=$((fail+1)); }
  grep -q 'scripts/sdd-worktree' "$prac" \
    && { echo "  PASS  the practices skill names the worktree script"; pass=$((pass+1)); } \
    || { echo "  FAIL  the practices skill does not name sdd-worktree"; fail=$((fail+1)); }
else
  echo "  FAIL  the practices skill is missing"; fail=$((fail+1))
fi

# The rules must state that the hooks require the directory to be named .specs. The
# skill that resolves paths accepts a project-named directory, so without this the
# suite claims support its enforcement does not have.
if printf '%s' "$both" | grep -q 'hooks test for that exact name'; then
  echo "  PASS  the rules say the spec directory must be named .specs"; pass=$((pass+1))
else
  echo "  FAIL  the rules do not state that the hooks require .specs"; fail=$((fail+1))
fi

# The fitness rubric belongs in the conditional rules: it is about whether a change
# earns a spec and a task file, which means nothing without a spec repo. In the
# universal rules it would be paid for on every project that has none.
if printf '%s' "$both" | grep -q 'Which lane does this change take'; then
  echo "  PASS  the fitness rubric is emitted where a spec repo exists"; pass=$((pass+1))
else
  echo "  FAIL  the fitness rubric is missing from the spec-repo rules"; fail=$((fail+1))
fi
if printf '%s' "$with" | grep -q 'Which lane does this change take'; then
  echo "  FAIL  the fitness rubric leaked into the universal rules: paid everywhere"; fail=$((fail+1))
else
  echo "  PASS  the fitness rubric is withheld where there is no spec repo"; pass=$((pass+1))
fi
if printf '%s' "$both" | grep -q 'nothing enforces it'; then
  echo "  PASS  the rubric says plainly that it is not enforced"; pass=$((pass+1))
else
  echo "  FAIL  the rubric does not admit it is unenforced"; fail=$((fail+1))
fi

# --- emit-delegation-rules.sh ----------------------------------------------
demit="$SDD_DELEGATION/hooks/emit-delegation-rules.sh"
if [ -z "$SDD_DELEGATION" ]; then
  echo "  skip  emit-delegation-rules.sh: the delegation plugin is not in this tree"
else
echo
echo "emit-delegation-rules.sh"
if [ -x "$demit" ]; then
  out=$("$demit" < /dev/null 2>&1); rc=$?
  [ "$rc" -eq 0 ] && { echo "  PASS  exits 0"; pass=$((pass+1)); } || { echo "  FAIL  rc=$rc"; fail=$((fail+1)); }
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1; then
    echo "  PASS  emits hookSpecificOutput.hookEventName = SessionStart"; pass=$((pass+1))
  else
    echo "  FAIL  wrong JSON shape"; fail=$((fail+1))
  fi
  ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
  # The probe token was temporary; a released version must not carry it.
  if printf '%s' "$ctx" | grep -q 'DELEGATION-CONTEXT-REACHED'; then
    echo "  FAIL  still carries the temporary subagent-reach probe token"; fail=$((fail+1))
  else
    echo "  PASS  no leftover probe token"; pass=$((pass+1))
  fi
  # The rules are useless if they do not name the agents they are about.
  if printf '%s' "$ctx" | grep -q 'delegation:scout'; then
    echo "  PASS  names agents in their dispatchable form"; pass=$((pass+1))
  else
    echo "  FAIL  does not name agents as delegation:<name>"; fail=$((fail+1))
  fi
  if printf '%s' "$ctx" | grep -q '~/\.claude/'; then
    echo "  FAIL  names a path under ~/.claude"; fail=$((fail+1))
  else
    echo "  PASS  names no path under ~/.claude"; pass=$((pass+1))
  fi
else
  echo "  FAIL  $demit is not executable"; fail=$((fail+1))
fi

fi  # emit-delegation-rules.sh (first block): skipped when delegation is not in this tree
# --- check-agy-grants.sh ---------------------------------------------------
# The important assertions here are the SILENT ones. A grant check that fires in every project
# is noise, and noise is how a real warning gets ignored, so "says nothing when irrelevant" is
# the behaviour most worth pinning.
#
# HOME and the cwd are both redirected per case, because the hook reads the user settings layer
# and the project one and must be tested without touching the real ones.
grants="$SDD_DELEGATION/hooks/check-agy-grants.sh"
if [ -z "$SDD_DELEGATION" ]; then
  echo "  skip  check-agy-grants.sh: the delegation plugin is not in this tree"
else
echo
echo "check-agy-grants.sh"

# agrant <name> <user-settings-json|-> <project-settings-json|-> <expect: silent|warn> [needle]
agrant() {
  local name="$1" usr="$2" proj="$3" expect="$4" needle="${5:-}"
  local d out rc ctx
  d=$(mktemp -d "$lab/grant.XXXXXX")
  mkdir -p "$d/home/.claude" "$d/repo/.claude"
  ( cd "$d/repo" && git init -q . && git commit -q --allow-empty -m init ) >/dev/null 2>&1
  [ "$usr" != "-" ] && printf '%s' "$usr" > "$d/home/.claude/settings.json"
  [ "$proj" != "-" ] && printf '%s' "$proj" > "$d/repo/.claude/settings.json"
  out=$( cd "$d/repo" && HOME="$d/home" "$grants" < /dev/null 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL  $name: exited $rc; this hook must always exit 0"; fail=$((fail+1)); return
  fi
  if [ "$expect" = silent ]; then
    if [ -z "$out" ]; then
      echo "  PASS  $name -> silent"; pass=$((pass+1))
    else
      echo "  FAIL  $name: expected silence, got '${out:0:140}'"; fail=$((fail+1))
    fi
    return
  fi
  ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  if [ -z "$ctx" ]; then
    echo "  FAIL  $name: expected a warning, got '${out:0:140}'"; fail=$((fail+1)); return
  fi
  if [ -n "$needle" ] && ! printf '%s' "$ctx" | grep -qF "$needle"; then
    echo "  FAIL  $name: warning does not mention '$needle'"; fail=$((fail+1)); return
  fi
  echo "  PASS  $name -> warns${needle:+, naming $needle}"; pass=$((pass+1))
}

# Correct is the consult script's rule plus the escape-flag deny. The adapter runs agy-consult, and a
# permission rule matches only the command the Bash tool runs, never what that command starts, so
# agy itself needs no grant. Earlier fixtures here encoded `Bash(agy:*)` and then an absolute path,
# and each time the fixtures kept the old rule rather than the intent.
correct='{"permissions":{"allow":["Bash(agy-consult:*)"],"deny":["Bash(agy --dangerously-skip-permissions:*)"]}}'

# No settings at all, and no mention of agy: the common case, and it must cost nothing.
agrant "no settings anywhere" - - silent
agrant "settings with unrelated grants only" '{"permissions":{"allow":["Bash(git:*)"]}}' - silent
agrant "correct grants in project settings" - "$correct" silent
agrant "correct grants in user settings" "$correct" - silent

# Intent present, grants incomplete. Each of these is a dispatch that fails later.
agrant "allow without the escape-flag deny" - \
  '{"permissions":{"allow":["Bash(agy-consult:*)"]}}' warn 'dangerously-skip-permissions'
# An allow rule matches the command that runs, so this grants nothing the adapter does.
agrant "mis-patterned allow (command -v agy)" - \
  '{"permissions":{"allow":["Bash(command -v agy:*)"],"deny":["Bash(agy --dangerously-skip-permissions:*)"]}}' warn 'Bash(agy-consult:*)'
# The grant this suite used to recommend. It does not cover agy-consult, and it admits piping a
# file into agy, so the warning must say to replace it rather than merely to add a rule beside it.
agrant "the old broad agy grant alone" - \
  '{"permissions":{"allow":["Bash(agy:*)"],"deny":["Bash(agy --dangerously-skip-permissions:*)"]}}' warn 'Replace it'
# Someone who keeps agy for their own use and has added the consult rule has made a choice. Saying
# so every session would be the noise this hook exists to avoid.
agrant "the broad grant kept beside the consult rule" - \
  '{"permissions":{"allow":["Bash(agy:*)","Bash(agy-consult:*)"],"deny":["Bash(agy --dangerously-skip-permissions:*)"]}}' silent
# Rules in force are the union of the layers, so a deny in user settings covers a project allow.
agrant "allow in project, deny in user settings" \
  '{"permissions":{"deny":["Bash(agy --dangerously-skip-permissions:*)"]}}' \
  '{"permissions":{"allow":["Bash(agy-consult:*)"]}}' silent
# The warning is useless if it does not say what to write.
agrant "warning names the JSON to add" - '{"permissions":{"allow":["Bash(agy-consult:*)"]}}' warn '"permissions"'
agrant "the JSON shown is the consult rule, not an absolute path" - '{"permissions":{"allow":["Bash(agy-consult:*)"]}}' warn '"allow": ["Bash(agy-consult:*)"]'

# An absolute-path rule cannot travel: agy is at ~/.local/bin/agy on macOS and
# /home/<user>/.local/bin/agy on Linux. This repo shipped a macOS path that matched nothing on the
# Arch box, and an earlier version of this hook REQUIRED such a rule, so it was silent about a
# grant that permitted nothing.
agrant "a stale absolute-path rule from another machine" - \
  '{"permissions":{"allow":["Bash(agy-consult:*)","Bash(/nonexistent/machine/bin/agy:*)"],"deny":["Bash(agy --dangerously-skip-permissions:*)"]}}' \
  warn 'does not exist on this machine'

# Written is not in force. A project's permissions.allow is ignored outright until the workspace
# has been trusted once interactively, and the session says so in a warning a model need not
# surface. Measured on a second machine; invisible on the one where the trust entry was months old.
# trust <name> <claude.json or -> <expect: silent|warn>
trust_case() {
  local name="$1" cj="$2" expect="$3" d out rc ctx
  d=$(mktemp -d "$lab/trust.XXXXXX")
  mkdir -p "$d/home/.claude" "$d/repo/.claude"
  ( cd "$d/repo" && git init -q . ) >/dev/null 2>&1
  printf '%s' '{"permissions":{"allow":["Bash(agy-consult:*)"],"deny":["Bash(agy --dangerously-skip-permissions:*)"]}}' \
    > "$d/repo/.claude/settings.json"
  if [ "$cj" != "-" ]; then
    # The hook keys on the resolved repo root, which on macOS differs from $TMPDIR's symlink form.
    real=$( cd "$d/repo" && git rev-parse --show-toplevel )
    printf '%s' "$cj" | sed "s|__ROOT__|$real|" > "$d/home/.claude.json"
  fi
  out=$( cd "$d/repo" && HOME="$d/home" "$grants" < /dev/null 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL  $name: exited $rc"; fail=$((fail+1)); return
  fi
  ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  if [ "$expect" = silent ]; then
    if [ -z "$out" ]; then echo "  PASS  $name -> silent"; pass=$((pass+1))
    else echo "  FAIL  $name: expected silence, got '${ctx:0:110}'"; fail=$((fail+1)); fi
  else
    if printf '%s' "$ctx" | grep -qF 'never been trusted'; then
      echo "  PASS  $name -> warns that the rules are ignored"; pass=$((pass+1))
    else echo "  FAIL  $name: expected the trust warning, got '${ctx:0:110}'"; fail=$((fail+1)); fi
  fi
}

trust_case "no ~/.claude.json, so trust is unknowable"  -                                                               silent
trust_case "workspace trusted"      '{"projects":{"__ROOT__":{"hasTrustDialogAccepted":true}}}'                          silent
trust_case "workspace NOT trusted"  '{"projects":{"__ROOT__":{"hasTrustDialogAccepted":false}}}'                         warn
trust_case "no entry for this path" '{"projects":{"/some/other/path":{"hasTrustDialogAccepted":true}}}'                  warn

fi  # check-agy-grants.sh: skipped when delegation is not in this tree
# --- sdd-bootstrap ---------------------------------------------------------
# Prepares a project with the two things a plugin cannot ship: a CLAUDE.md carrying the Task
# Workflow keys, and the permissions the spec-repo commit policy needs. The assertions that matter
# are idempotence and non-destruction: the failure worth preventing is a script that doubles entries
# or eats a hand-written config.
boot="$SDD_PLUGIN/scripts/sdd-bootstrap"
echo
echo "sdd-bootstrap"

bootrepo() { # -> prints a fresh repo path
  local d; d=$(mktemp -d "$lab/boot.XXXXXX")
  ( cd "$d" && git init -q . && git remote add origin gitea@example.com:o/proj.git ) >/dev/null 2>&1
  printf '%s' "$d"
}
bchk() { # bchk <got> <want> <label>
  if [ "$1" = "$2" ]; then echo "  PASS  $3"; pass=$((pass+1))
  else echo "  FAIL  $3: got '$1' want '$2'"; fail=$((fail+1)); fi
}

d=$(bootrepo)
( cd "$d" && "$boot" ) >/dev/null 2>&1
bchk "$(cd "$d" && jq -r '.permissions.allow | length' .claude/settings.json 2>/dev/null)" "1" \
  "first run adds exactly one allow rule"
bchk "$(cd "$d" && jq -r '.permissions.allow[0]' .claude/settings.json 2>/dev/null)" "Bash(git:*)" \
  "and it is the grant the commit policy needs"
# Derived from the project's own origin, so this works in a fork rather than hardcoding one host.
if grep -q 'gitea@example.com:o/proj-specs.git' "$d/CLAUDE.md"; then
  echo "  PASS  the spec remote is derived from the project's origin"; pass=$((pass+1))
else
  echo "  FAIL  spec remote not derived from origin"; fail=$((fail+1))
fi
if grep -q '^## Task Workflow' "$d/CLAUDE.md"; then
  echo "  PASS  CLAUDE.md carries the keys path resolution reads"; pass=$((pass+1))
else
  echo "  FAIL  CLAUDE.md has no Task Workflow section"; fail=$((fail+1))
fi

# Idempotence. A second run must change nothing at all, byte for byte.
before=$(cat "$d/.claude/settings.json"; cat "$d/CLAUDE.md")
( cd "$d" && "$boot" ) >/dev/null 2>&1
after=$(cat "$d/.claude/settings.json"; cat "$d/CLAUDE.md")
bchk "$([ "$before" = "$after" ] && echo same || echo changed)" "same" \
  "a second run changes nothing, byte for byte"

# Existing entries keep their place and unrelated keys survive.
d=$(bootrepo)
mkdir -p "$d/.claude"
printf '%s' '{"permissions":{"allow":["Bash(cargo:*)"]},"other":"keep me"}' > "$d/.claude/settings.json"
( cd "$d" && "$boot" --with-agy ) >/dev/null 2>&1
bchk "$(jq -r '.permissions.allow[0]' "$d/.claude/settings.json")" "Bash(cargo:*)" \
  "an existing allow rule keeps its position"
bchk "$(jq -r '.other' "$d/.claude/settings.json")" "keep me" \
  "unrelated keys survive"
bchk "$(jq -r '.permissions.deny[0]' "$d/.claude/settings.json")" "Bash(agy --dangerously-skip-permissions:*)" \
  "--with-agy adds the escape-flag deny, not just the allow"
bchk "$(jq -r '.permissions.allow | index("Bash(agy-consult:*)") != null' "$d/.claude/settings.json")" "true" \
  "--with-agy grants the consult script"
bchk "$(jq -r '.permissions.allow | index("Bash(agy:*)") != null' "$d/.claude/settings.json")" "false" \
  "--with-agy does not grant agy itself, which would admit piping a file into it"
# No absolute path: agy is at a different path on macOS and Linux, so a rule naming one travels badly.
if jq -r '.permissions.allow[]' "$d/.claude/settings.json" | grep -q '/agy'; then
  echo "  FAIL  --with-agy wrote an absolute path, which is wrong on the other platform"; fail=$((fail+1))
else
  echo "  PASS  --with-agy grants the bare name only"; pass=$((pass+1))
fi

# A hand-written CLAUDE.md must never be overwritten. This is the destructive failure.
d=$(bootrepo)
printf 'my own notes\n' > "$d/CLAUDE.md"
( cd "$d" && "$boot" ) >/dev/null 2>&1
bchk "$(cat "$d/CLAUDE.md")" "my own notes" "a non-empty CLAUDE.md is never overwritten"

# A malformed settings file is refused, and nothing at all is written: the validity check runs
# before the CLAUDE.md write, so a refusal leaves the project exactly as it was.
d=$(bootrepo)
mkdir -p "$d/.claude"
printf '%s' '{ "permissions": { "allow": [ ' > "$d/.claude/settings.json"
mal_before=$(cat "$d/.claude/settings.json")
( cd "$d" && "$boot" ) >/dev/null 2>&1; rc=$?
bchk "$rc" "1" "a malformed settings file is refused with a non-zero exit"
bchk "$(cat "$d/.claude/settings.json")" "$mal_before" "and the malformed file is left untouched"
bchk "$([ -e "$d/CLAUDE.md" ] && echo written || echo none)" "none" \
  "and nothing else is written either, so a refusal is not a partial change"

# Outside a repository there is no project to prepare.
d=$(mktemp -d "$lab/boot.XXXXXX")
( cd "$d" && "$boot" ) >/dev/null 2>&1; rc=$?
bchk "$rc" "1" "refused outside a git repository"
bchk "$(ls -A "$d" | wc -l | tr -d ' ')" "0" "and it created nothing there"

# --- check-spec-ignore.sh --------------------------------------------------
# Guards ambient state that was correct on the author's machine for so long it stopped being
# checked. On a fresh machine `core.excludesFile` was unset, so `.specs` was visible to every code
# repo and one `git add -A` would have committed the whole spec repo into the main one.
#
# `core.excludesFile` is forced per fixture so these assertions never read the real environment,
# which is the mistake that made the defect invisible in the first place.
specign="$SDD_PLUGIN/hooks/check-spec-ignore.sh"
echo
echo "check-spec-ignore.sh"

# specign <name> <ignored: yes|no|nospecs|norepo> <expect: silent|warn>
specign_case() {
  local name="$1" setup="$2" expect="$3" d out rc ctx
  d=$(mktemp -d "$lab/ign.XXXXXX")
  if [ "$setup" != norepo ]; then
    ( cd "$d" && git init -q . && git config --local core.excludesFile /dev/null ) >/dev/null 2>&1
  fi
  if [ "$setup" != nospecs ] && [ "$setup" != norepo ]; then
    mkdir -p "$d/.specs" && ( cd "$d/.specs" && git init -q . ) >/dev/null 2>&1
  fi
  # core.excludesFile is forced to /dev/null for EVERY fixture above, so no case can be decided by
  # the real machine's global ignore. Two of these cases silently were: on this laptop
  # ~/.gitignore_global contains `.specs`, so the no-spec-repo case passed because check-ignore
  # returned 0 rather than because the hook's gate fired. A fall-back proof caught it: removing the
  # gate left the suite green.
  case "$setup" in
    yes) printf '.specs\n' > "$d/.gitignore" ;;
  esac
  out=$( cd "$d" && "$specign" < /dev/null 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL  $name: exited $rc; this hook must always exit 0"; fail=$((fail+1)); return
  fi
  if [ "$expect" = silent ]; then
    if [ -z "$out" ]; then echo "  PASS  $name -> silent"; pass=$((pass+1))
    else echo "  FAIL  $name: expected silence, got '${out:0:120}'"; fail=$((fail+1)); fi
    return
  fi
  ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  # The warning is worthless unless it names the operation that causes the damage.
  if [ -n "$ctx" ] && printf '%s' "$ctx" | grep -qF 'git add -A'; then
    echo "  PASS  $name -> warns, naming the dangerous operation"; pass=$((pass+1))
  else
    echo "  FAIL  $name: expected a warning naming \`git add -A\`, got '${out:0:120}'"; fail=$((fail+1))
  fi
}

specign_case "not a git repo at all"                  norepo  silent
specign_case "a repo with no spec repo"               nospecs silent
specign_case "spec repo present and ignored"          yes     silent
specign_case "spec repo present and NOT ignored"      no      warn

# --- delegate-telemetry.sh ------------------------------------------------------
# This hook runs after EVERY Bash call, so the assertions it most needs are the ones proving it
# does nothing the rest of the time, and that its one network call is bounded.
#
# The payload is captured with a stub `curl` placed earlier on PATH rather than by rebuilding
# the JSON here. A test that constructs the expected body tests itself; capturing what the hook
# actually sent means the body can then be offered to a real collector, which is the only thing
# that can tell acceptance from a silent drop.
tel="$SDD_DELEGATION/hooks/delegate-telemetry.sh"
if [ -z "$SDD_DELEGATION" ]; then
  echo "  skip  delegate-telemetry.sh: the delegation plugin is not in this tree"
else
echo
echo "delegate-telemetry.sh"

mkdir -p "$lab/stub"
cat > "$lab/stub/curl" <<'STUB'
#!/usr/bin/env bash
url=""; body=""
while [ $# -gt 0 ]; do
  case "$1" in
    -d) body="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
printf '%s' "$url"  > "$CAPTURE_DIR/url"
printf '%s' "$body" > "$CAPTURE_DIR/body"
STUB
chmod +x "$lab/stub/curl"

# tel_payload <command> <stdout> <stderr> <duration_ms>
tel_payload() {
  jq -nc --arg c "$1" --arg o "$2" --arg e "$3" --argjson d "$4" \
    '{tool_name:"Bash",cwd:"/tmp",duration_ms:$d,tool_input:{command:$c},
      tool_response:{stdout:$o,stderr:$e,interrupted:false,isImage:false}}'
}

# tel <name> <command> <expect: quiet|sent> [outcome] [mode]
tel() {
  local name="$1" cmd="$2" expect="$3" want_outcome="${4:-}" want_mode="${5:-}" stdout="${6:-answer text}"
  local cap out rc body
  cap=$(mktemp -d "$lab/tel.XXXXXX")
  out=$(tel_payload "$cmd" "$stdout" "" 4172 \
        | CAPTURE_DIR="$cap" PATH="$lab/stub:$PATH" \
          OTEL_EXPORTER_OTLP_ENDPOINT=http://collector.invalid:4318 "$tel" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] || [ -n "$out" ]; then
    echo "  FAIL  $name: must exit 0 silently, got rc=$rc out='${out:0:100}'"; fail=$((fail+1)); return
  fi
  if [ "$expect" = quiet ]; then
    if [ -f "$cap/body" ]; then
      echo "  FAIL  $name: sent a metric when it should not have"; fail=$((fail+1))
    else
      echo "  PASS  $name -> no metric sent"; pass=$((pass+1))
    fi
    return
  fi
  if [ ! -f "$cap/body" ]; then
    echo "  FAIL  $name: sent nothing"; fail=$((fail+1)); return
  fi
  body=$(cat "$cap/body")
  if [ "$(cat "$cap/url")" != "http://collector.invalid:4318/v1/metrics" ]; then
    echo "  FAIL  $name: wrong URL '$(cat "$cap/url")'"; fail=$((fail+1)); return
  fi
  # duration must come from duration_ms, not from anything the hook timed itself
  if ! printf '%s' "$body" | jq -e '[.. | objects | select(.name? == "delegate.duration")
        | .gauge.dataPoints[0].asInt] == ["4172"]' >/dev/null 2>&1; then
    echo "  FAIL  $name: duration is not the payload's duration_ms"; fail=$((fail+1)); return
  fi
  if [ -n "$want_outcome" ] && ! printf '%s' "$body" | grep -qF "\"stringValue\": \"$want_outcome\"" \
     && ! printf '%s' "$body" | jq -e --arg v "$want_outcome" '[.. | objects | select(.key? == "outcome") | .value.stringValue] | index($v) != null' >/dev/null 2>&1; then
    echo "  FAIL  $name: outcome is not '$want_outcome'"; fail=$((fail+1)); return
  fi
  if [ -n "$want_mode" ] && ! printf '%s' "$body" | jq -e --arg v "$want_mode" '[.. | objects | select(.key? == "mode") | .value.stringValue] | index($v) != null' >/dev/null 2>&1; then
    echo "  FAIL  $name: mode is not '$want_mode'"; fail=$((fail+1)); return
  fi
  echo "  PASS  $name -> metric sent${want_outcome:+ (outcome=$want_outcome${want_mode:+, mode=$want_mode})}"; pass=$((pass+1))
}

# telr <name> <command> <first line of stdout> <expected outcome> [expected mode]
# For the adapters that print their own status line, including every refusal.
telr() { tel "$1" "$2" sent "$4" "${5:-}" "$3"; }

# --- the new lanes -------------------------------------------------------
# Refusals are the reason these are covered at all. ALT-BUDGET, ALT-LOCKED and LOCAL-REFUSED all
# start no session, so Claude Code's own telemetry records nothing for them, and the question the
# caps exist to answer, how often the reserve actually refuses, would have no data behind it.

telr "alt consult ran"        "alt-consult 'q'"   "ALT-RAN denials=0"                        ran
telr "alt refused by the cap" "alt-consult 'q'"   "ALT-BUDGET seven_day=72% reserve=40%"     refused-budget
telr "alt locked by Anthropic" "alt-consult 'q'"  "ALT-LOCKED reason=usage_limit_reached"    refused-locked
telr "alt not signed in"      "alt-consult 'q'"   "ALT-LOGGEDOUT"                            loggedout
telr "alt lane switched off"  "alt-consult 'q'"   "ALT-DISABLED"                             disabled
telr "alt quota unreadable"   "alt-consult 'q'"   "ALT-UNKNOWN reason=refresh-failed"        unknown-refresh-failed
telr "alt recursion refused"  "alt-consult 'q'"   "ALT-FAILED reason=recursion"              failed-recursion

telr "local ran"              "local-consult --checker t 'x'" "LOCAL-RAN model=qwen"         ran
telr "local had no checker"   "local-consult 'x'" "LOCAL-REFUSED reason=no-checker"          refused-no-checker
telr "local refused a path"   "local-consult --checker t --file .env 'x'" \
                                                  "LOCAL-REFUSED reason=denied path=.env"    refused-denied
telr "local refused untracked" "local-consult --checker t --file s 'x'" \
                                                  "LOCAL-REFUSED reason=untracked path=s"    refused-untracked
telr "local unreachable"      "local-consult --checker t 'x'" "LOCAL-ABSENT"                 absent
telr "local unconfigured"     "local-consult --checker t 'x'" "LOCAL-ABSENT reason=unconfigured" absent-unconfigured

# The one caller decision that widens what leaves the machine is worth counting in aggregate.
telr "the untracked override is labelled" "local-consult --checker t --allow-untracked --file s 'x'" \
                                          "LOCAL-RAN model=qwen untracked=1" ran allow-untracked

# The refusals must stay distinguishable from each other, or the metric cannot answer the
# question it exists for: a cap the operator can change is not a provider refusing.
budget_body=$(tel_payload "alt-consult 'q'" "ALT-BUDGET seven_day=72% reserve=40%" "" 1 \
  | CAPTURE_DIR="$lab/telx" PATH="$lab/stub:$PATH" \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://collector.invalid:4318 "$tel" >/dev/null 2>&1; cat "$lab/telx/body" 2>/dev/null)
mkdir -p "$lab/telx"
if printf '%s' "$budget_body" | grep -q 'refused-locked'; then
  echo "  FAIL  a budget refusal must not be labelled as a provider lock"; fail=$((fail+1))
else
  echo "  PASS  a budget refusal is not labelled as a provider lock"; pass=$((pass+1))
fi

# Every adapter lands in one series, so the lanes are comparable and a new one needs no dashboard.
adp=$(mktemp -d "$lab/adp.XXXXXX")
tel_payload "alt-consult 'q'" "ALT-RAN" "" 1 \
  | CAPTURE_DIR="$adp" PATH="$lab/stub:$PATH" \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://collector.invalid:4318 "$tel" >/dev/null 2>&1
if jq -e '[.. | objects | select(.key? == "adapter") | .value.stringValue] | index("alt") != null' \
     "$adp/body" >/dev/null 2>&1; then
  echo "  PASS  the adapter is an attribute, not a separate metric name"; pass=$((pass+1))
else
  echo "  FAIL  no adapter attribute on the metric"; fail=$((fail+1))
fi
if jq -e '[.. | objects | select(.name? == "delegate.invocations")] | length == 1' \
     "$adp/body" >/dev/null 2>&1; then
  echo "  PASS  one unified series for every lane"; pass=$((pass+1))
else
  echo "  FAIL  delegate.invocations missing"; fail=$((fail+1))
fi
# The pre-existing agy series is kept for agy only, so a dashboard built on it keeps working.
if jq -e '[.. | objects | select(.name? == "agy.invocations")] | length == 0' \
     "$adp/body" >/dev/null 2>&1; then
  echo "  PASS  and the legacy agy series is not emitted for other lanes"; pass=$((pass+1))
else
  echo "  FAIL  legacy agy metric emitted for a non-agy adapter"; fail=$((fail+1))
fi

# Almost every Bash call looks like this and must cost nothing beyond the pre-filter.
tel "an unrelated command" "git status --porcelain" quiet
# The pre-filter matches these and the precise check must reject them. This is the assertion
# that keeps the pre-filter allowed to be loose.
tel "agy inside another command name" "agyrate --foo" quiet
tel "agy as an argument, not the command" "echo agy" quiet
tel "agy in a path that is not the binary" "cat /var/log/agysomething.log" quiet
# The real shapes.
tel "a consult" 'agy --add-dir /r -p "q"' sent answered consult
tel "an availability check" "agy --version" sent answered availability-check
tel "by absolute path" "/home/u/.local/bin/agy -p q" sent answered consult
# Worth labelling distinctly: if this ever appears, the deny rule did not hold.
tel "the escape flag is labelled as such" "agy --dangerously-skip-permissions -p q" sent answered escape-flag
# The consult script reports its own status as the first line of its output, so the metric can
# carry what actually happened rather than a guess from stdout and stderr being empty or not.
tel "a consult through agy-consult" 'agy-consult --repo /r "q"' sent ran consult $'ANTIGRAVITY-RAN conversation_id=abc\n\n4'
tel "agy-consult timed out" 'agy-consult "q"' sent failed-timeout consult $'ANTIGRAVITY-FAILED reason=timeout\n\npartial'
tel "agy-consult refused a tool" 'agy-consult "q"' sent denied consult $'ANTIGRAVITY-DENIED tools=read_url\n'
tel "agy-consult by absolute path" '/x/bin/agy-consult "q"' sent ran consult $'ANTIGRAVITY-RAN conversation_id=abc\n'
tel "a name that only starts with agy-consult" "agy-consultant q" quiet

# No endpoint configured anywhere is the normal state without telemetry, not an error.
cap=$(mktemp -d "$lab/tel.XXXXXX")
out=$(tel_payload "agy -p q" "a" "" 10 \
      | CAPTURE_DIR="$cap" PATH="$lab/stub:$PATH" HOME="$lab/nohome" \
        env -u OTEL_EXPORTER_OTLP_ENDPOINT "$tel" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ ! -f "$cap/body" ]; then
  echo "  PASS  no endpoint configured -> silent, nothing sent"; pass=$((pass+1))
else
  echo "  FAIL  no endpoint configured: rc=$rc out='${out:0:80}' sent=$([ -f "$cap/body" ] && echo yes || echo no)"; fail=$((fail+1))
fi

# A refused connection must cost nothing and say nothing. Uses the REAL curl.
st=$(date +%s)
out=$(tel_payload "agy -p q" "a" "" 10 | OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:9 "$tel" 2>&1); rc=$?
el=$(( $(date +%s) - st ))
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ "$el" -le 4 ]; then
  echo "  PASS  refused connection -> silent, exited in ${el}s"; pass=$((pass+1))
else
  echo "  FAIL  refused connection: rc=$rc elapsed=${el}s out='${out:0:80}'"; fail=$((fail+1))
fi

# A collector that BLACKHOLES packets is the case that actually exercises --max-time, and it is
# a different test from the one above. 127.0.0.1:9 refuses instantly, so with that address the
# assertion passes even if the timeout is raised to 30s: it was measuring connection refusal and
# reporting it as a bound. 192.0.2.1 is TEST-NET-1 and drops, so the timeout is what ends the
# call. Found by deliberately raising --max-time and watching this assertion stay green.
st=$(python3 -c 'import time;print(time.time())')
out=$(tel_payload "agy -p q" "a" "" 10 | OTEL_EXPORTER_OTLP_ENDPOINT=http://192.0.2.1:4318 "$tel" 2>&1); rc=$?
el=$(python3 -c "import time;print(time.time() - $st)")
if [ "$rc" -eq 0 ] && [ -z "$out" ] && python3 -c "import sys; sys.exit(0 if $el <= 4 else 1)"; then
  echo "  PASS  blackholed collector -> silent, bounded by --max-time ($(printf '%.1f' "$el")s)"; pass=$((pass+1))
else
  echo "  FAIL  blackholed collector: rc=$rc elapsed=${el}s out='${out:0:80}'"; fail=$((fail+1))
fi

# The metric must not borrow the adapter's status tokens. PostToolUse has no exit code, so a
# payload claiming ANTIGRAVITY-DENIED would be asserting something the data cannot support.
cap=$(mktemp -d "$lab/tel.XXXXXX")
tel_payload "agy -p q" "" "permission auto-denied" 10 \
  | CAPTURE_DIR="$cap" PATH="$lab/stub:$PATH" \
    OTEL_EXPORTER_OTLP_ENDPOINT=http://collector.invalid:4318 "$tel" >/dev/null 2>&1
if [ -f "$cap/body" ] && ! grep -q 'ANTIGRAVITY-' "$cap/body"; then
  echo "  PASS  does not claim the adapter's status tokens, which need an exit code"; pass=$((pass+1))
else
  echo "  FAIL  borrows the adapter's status tokens without an exit code to justify them"; fail=$((fail+1))
fi

fi  # delegate-telemetry.sh and the lane cases: skipped when delegation is not in this tree
# --- capture-learning.sh ---------------------------------------------------
# Explicit capture: a marked line is kept and nothing else is. Capturing everything
# would produce a file nobody reads; judging at capture time is the hard problem
# moved rather than solved.
cap="$SDD_PLUGIN/hooks/capture-learning.sh"
echo
echo "capture-learning.sh"
# The hook now also writes a central stream outside every repository. Point it at the lab, or
# these tests append to the developer's own ~/.local/state.
export XDG_STATE_HOME="$lab/state"
central="$XDG_STATE_HOME/sdd/learnings.jsonl"

r=$(mkrepo cap); mkspecs "$lab/cap" noremote clean
log="$lab/cap/.specs/docs/learnings.md"

jq -n --arg c "$lab/cap" '{cwd:$c,session_id:"deadbeef-1",prompt:"do the thing\nTIL: grade the artefact, not the transcript\nand then stop"}' | "$cap"
if [ -f "$log" ] && grep -q 'grade the artefact, not the transcript' "$log"; then
  echo "  PASS  a marked line is captured"; pass=$((pass+1))
else
  echo "  FAIL  the marked line was not captured"; fail=$((fail+1))
fi
if [ -f "$log" ] && ! grep -q 'do the thing' "$log" && ! grep -q 'and then stop' "$log"; then
  echo "  PASS  the unmarked lines around it are not captured"; pass=$((pass+1))
else
  echo "  FAIL  unmarked text leaked into the log"; fail=$((fail+1))
fi
before=$(wc -l < "$log")
jq -n --arg c "$lab/cap" '{cwd:$c,session_id:"x",prompt:"no marker here at all"}' | "$cap"
if [ "$(wc -l < "$log")" = "$before" ]; then
  echo "  PASS  an unmarked prompt writes nothing"; pass=$((pass+1))
else
  echo "  FAIL  an unmarked prompt appended to the log"; fail=$((fail+1))
fi
r=$(mkrepo cap-nospecs)
out=$(jq -n --arg c "$lab/cap-nospecs" '{cwd:$c,session_id:"x",prompt:"TIL: something"}' | "$cap" 2>&1)
if [ -z "$out" ] && [ ! -f "$lab/cap-nospecs/.specs/docs/learnings.md" ]; then
  echo "  PASS  silent with no spec repo, and writes no project log"; pass=$((pass+1))
else
  echo "  FAIL  it wrote or spoke where there is no spec repo"; fail=$((fail+1))
fi

# --- the central stream ------------------------------------------------------
# The improver edits skills in this marketplace and can never read a note captured in another
# project's spec repo, which is why the log had six entries from one day. The central file is the
# only path by which a learning from anywhere else reaches it.
if [ -f "$central" ] && grep -q '"project":"cap-nospecs"' "$central"; then
  echo "  PASS  a project with no spec repo still reaches the central stream"; pass=$((pass+1))
else
  echo "  FAIL  the central stream missed a project with no spec repo"; fail=$((fail+1))
fi
if [ "$(jq -r 'select(.project=="cap") | .text' "$central" 2>/dev/null | head -1)" = "grade the artefact, not the transcript" ]; then
  echo "  PASS  the central entry carries the marked text"; pass=$((pass+1))
else
  echo "  FAIL  the central entry lost or mangled its text"; fail=$((fail+1))
fi
if ! grep -q 'do the thing\|and then stop\|no marker here' "$central"; then
  echo "  PASS  unmarked text never reaches the central stream"; pass=$((pass+1))
else
  echo "  FAIL  unmarked prompt text leaked into the central stream"; fail=$((fail+1))
fi
if [ "$(wc -l < "$central")" = "$(jq -s length "$central" 2>/dev/null)" ]; then
  echo "  PASS  the central stream is one JSON object per line"; pass=$((pass+1))
else
  echo "  FAIL  the central stream is not valid JSONL"; fail=$((fail+1))
fi
# Two marked lines in one prompt are two entries, so a count means something.
jq -n --arg c "$lab/cap" '{cwd:$c,session_id:"multi1234",prompt:"TIL: first thing\nTIL: second thing"}' | "$cap"
if [ "$(jq -r 'select(.session=="multi123") | .text' "$central" | wc -l)" = "2" ]; then
  echo "  PASS  two marked lines are two central entries"; pass=$((pass+1))
else
  echo "  FAIL  multiple marked lines did not become separate entries"; fail=$((fail+1))
fi
unset XDG_STATE_HOME

# --- the two plugins must not duplicate each other's rules -----------------
echo
echo "plugin separation"
# The plugin's own prose only. In a published copy SDD_PLUGIN is the repository root, so sweeping
# it also reads tools/, where this very list of agent names is written down: the check then reports
# itself, every time, in the only tree where the claim it makes actually matters.
sep_scan=()
for sd in commands skills hooks; do
  [ -d "$SDD_PLUGIN/$sd" ] && sep_scan+=("$SDD_PLUGIN/$sd")
done
if [ ${#sep_scan[@]} -gt 0 ] && grep -rqE '\b(scout|test-runner|code-reviewer|architect|antigravity)\b' "${sep_scan[@]}" 2>/dev/null; then
  echo "  FAIL  sdd names a specific agent; it must install alone"; fail=$((fail+1))
else
  echo "  PASS  sdd names no specific agent"; pass=$((pass+1))
fi

# The avoidance rule it replaced must be gone from every plugin, or two contradictory
# rules are in force and the stronger-sounding one wins. Matched on the rule itself, not
# on the phrase "never worktree": a legitimate new rule forbids worktreeing a read-only
# agent, and a looser pattern fires on that instead. Fifth time a broad pattern has
# caught something legitimate in this project; anchor to the claim, not the words.
if grep -rqiE 'worktree an agent that needs|never worktree.*\.specs' "$here/../plugins/" 2>/dev/null; then
  echo "  FAIL  the old avoidance rule survives somewhere in the plugins"; fail=$((fail+1))
else
  echo "  PASS  the old avoidance rule is gone from the plugins"; pass=$((pass+1))
fi

# --- verification-guard.sh -------------------------------------------------
# Refuses a turn when a task BECAME Complete this session and its Verification command did not
# run as its own command. Driven by synthetic transcripts and real git state, because those are
# the two things the hook reads.
vguard="$SDD_PLUGIN/hooks/verification-guard.sh"
echo
echo "verification-guard.sh"

# Every case gets its own project. Scope is now "every task that became Complete this session",
# so one leftover Complete fixture would be in scope for every later case in a shared lab, which
# is exactly what happened the first time these were run.
#
# vlab <name> <status-at-last-commit|absent> <status-now> <verification|none> -> prints the path
vlab() {
  local name="$1" was="$2" now="$3" verif="$4"
  local p="$lab/$name" f
  mkdir -p "$p/.specs/docs/tasks/phase-1"
  g "$p" init -q; echo x > "$p/f.txt"; g "$p" add -A; g "$p" commit -qm init
  g "$p/.specs" init -q
  f="$p/.specs/docs/tasks/phase-1/1.01-t.md"
  _wt() {
    {
      echo "# Task 1.01: Fixture"
      echo
      echo "**Status:** $1"
      [ "$verif" != none ] && echo "**Verification:** \`$verif\`"
      echo "**Created:** 2026-09-10"
    } > "$f"
  }
  if [ "$was" = absent ]; then echo placeholder > "$p/.specs/docs/note.md"; else _wt "$was"; fi
  g "$p/.specs" add -A; g "$p/.specs" commit -qm base
  _wt "$now"
  echo "$p"
}

# tr_bash <out> <command>... -> a transcript of successful Bash calls
tr_bash() {
  local out="$1"; shift
  : > "$out"
  local i=0 c
  for c in "$@"; do
    i=$((i+1))
    jq -cn --arg c "$c" --arg id "b$i" '{type:"assistant",message:{content:[{type:"tool_use",id:$id,name:"Bash",input:{command:$c}}]}}' >> "$out"
    jq -cn --arg id "b$i" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:$id,is_error:false,content:"ok"}]}}' >> "$out"
  done
  jq -cn '{type:"user",message:{content:"hello"}}' >> "$out"
}

vrun() { # vrun <name> <cwd> <transcript> <expect silent|block>
  local name="$1" cwd="$2" tr="$3" expect="$4" out rc decision
  out=$(jq -n --arg c "$cwd" --arg t "$tr" '{cwd:$c,transcript_path:$t,stop_hook_active:false}' | "$vguard" 2>&1); rc=$?
  decision=$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null)
  if [ "$expect" = silent ]; then
    if [ "$rc" -eq 0 ] && [ -z "$out" ]; then echo "  PASS  $name"; pass=$((pass+1))
    else echo "  FAIL  $name: expected silence, got rc=$rc '$(printf '%s' "$out" | tr -d '\n' | cut -c1-110)'"; fail=$((fail+1)); fi
  else
    if [ "$decision" = block ]; then echo "  PASS  $name"; pass=$((pass+1))
    else echo "  FAIL  $name: expected block, got rc=$rc decision='$decision'"; fail=$((fail+1)); fi
  fi
}

C='./scripts/check.sh'

# --- scope: what became Complete this session -------------------------------
p=$(vlab vg-ran "In Progress" "Complete" "$C"); tr_bash "$lab/tr-ran.jsonl" "$C"
vrun "became Complete, command ran     -> silent" "$p" "$lab/tr-ran.jsonl" silent

p=$(vlab vg-notrun "In Progress" "Complete" "$C"); tr_bash "$lab/tr-notrun.jsonl" "echo something else"
vrun "became Complete, command not run -> block"  "$p" "$lab/tr-notrun.jsonl" block

# Already Complete before the session: an earlier session's verification is not in this
# transcript, and blocking on it would make every later turn in the repo impossible.
p=$(vlab vg-was "Complete" "Complete" "$C"); tr_bash "$lab/tr-was.jsonl" "echo unrelated"
vrun "Complete before this session     -> silent" "$p" "$lab/tr-was.jsonl" silent

p=$(vlab vg-wip "In Progress" "In Progress" "$C"); tr_bash "$lab/tr-wip.jsonl" "echo nope"
vrun "still In Progress                -> silent" "$p" "$lab/tr-wip.jsonl" silent

p=$(vlab vg-new absent "Complete" "$C"); tr_bash "$lab/tr-new.jsonl" "$C"
vrun "new task file, command ran       -> silent" "$p" "$lab/tr-new.jsonl" silent

p=$(vlab vg-noverif "In Progress" "Complete" none); tr_bash "$lab/tr-nov.jsonl" "echo nope"
vrun "Complete with no Verification    -> block"  "$p" "$lab/tr-nov.jsonl" block

p=$(vlab vg-ph "In Progress" "Complete" "[one runnable command]"); tr_bash "$lab/tr-ph.jsonl" "echo nope"
vrun "Verification still a placeholder -> block"  "$p" "$lab/tr-ph.jsonl" block

r=$(mkrepo vg-nospecs); tr_bash "$lab/tr-ns.jsonl" "echo nope"
vrun "no spec repo                     -> silent" "$lab/vg-nospecs" "$lab/tr-ns.jsonl" silent

# A command that ran and failed has verified nothing, and the block message promises it passed.
p=$(vlab vg-failed "In Progress" "Complete" "$C")
{
  jq -cn --arg c "$C" '{type:"assistant",message:{content:[{type:"tool_use",id:"b1",name:"Bash",input:{command:$c}}]}}'
  jq -cn '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"b1",is_error:true,content:"Exit code 1"}]}}'
} > "$lab/tr-failedcmd.jsonl"
vrun "command ran but FAILED           -> block"  "$p" "$lab/tr-failedcmd.jsonl" block

# --- command shapes: "mentioned" is not "ran" --------------------------------
# The released gate flattened every successful command into one string and asked grep -F whether
# the Verification command appeared anywhere in it. These are the shapes an agent actually
# produces. The lab is constant across them; only the transcript changes.
pshape=$(vlab vg-shapes "In Progress" "Complete" "$C")
shape_n=0
vshape() { # vshape <label> <bash-command> <expect>
  shape_n=$((shape_n+1))
  tr_bash "$lab/tr-shape-$shape_n.jsonl" "$2"
  vrun "$1" "$pshape" "$lab/tr-shape-$shape_n.jsonl" "$3"
}

# Accepted: the command ran and its exit status is its own.
vshape "bare command                     -> silent" "$C" silent
vshape "cd then the command              -> silent" "cd sub && $C" silent
vshape "stderr redirected, no pipe       -> silent" "$C 2>&1" silent
vshape "redirected to a file             -> silent" "$C > out.txt 2>&1" silent

# Refused: the status reaching the shell is no longer the command's.
vshape "piped to tail                    -> block" "$C | tail -5" block
vshape "|| true                          -> block" "$C || true" block
vshape "|| :                             -> block" "$C || :" block
vshape "; true                           -> block" "$C ; true" block
vshape "&& another command               -> block" "$C && echo done" block

# Refused: it was written down, not run.
vshape "echoed, not run                  -> block" "echo \"will run $C later\"" block
vshape "commented out                    -> block" "# $C" block
vshape "printed by printf                -> block" "printf 'remember: $C'" block
vshape "inside a heredoc                 -> block" "cat <<'EOF' > notes.txt
$C
EOF" block
# A different command that merely starts with the same text.
vshape "a longer command name            -> block" "$C.bak" block

# --- a status flipped by the shell -------------------------------------------
# Edit detection used to filter on the tool name, so sed -i and a redirect were invisible and the
# task was never even considered. Scope comes from git state now, so how it was written is moot.
for tool in sed printf; do
  p=$(vlab "vg-flip-$tool" "In Progress" "Complete" "$C")
  case $tool in
    sed)    flip="sed -i 's/In Progress/Complete/' .specs/docs/tasks/phase-1/1.01-t.md" ;;
    printf) flip="printf '**Status:** Complete\n' > .specs/docs/tasks/phase-1/1.01-t.md" ;;
  esac
  tr_bash "$lab/tr-flip-$tool.jsonl" "$flip" "echo unrelated"
  vrun "status flipped by $tool$(printf '%*s' $((16-${#tool})) '')-> block" "$p" "$lab/tr-flip-$tool.jsonl" block
done

# --- a subagent's command counts ---------------------------------------------
# Measured 2026-09-16: a subagent's Bash tool_use is absent from the parent transcript and lives
# under <transcript>/subagents/. A task verified by a subagent used to look exactly like one
# never verified at all.
p=$(vlab vg-subagent "In Progress" "Complete" "$C")
tr_bash "$lab/tr-parent.jsonl" "echo dispatching a subagent"
mkdir -p "$lab/tr-parent/subagents"
tr_bash "$lab/tr-parent/subagents/agent-abc.jsonl" "$C"
vrun "subagent ran the command         -> silent" "$p" "$lab/tr-parent.jsonl" silent

p=$(vlab vg-subagent-piped "In Progress" "Complete" "$C")
tr_bash "$lab/tr-parent2.jsonl" "echo dispatching a subagent"
mkdir -p "$lab/tr-parent2/subagents"
tr_bash "$lab/tr-parent2/subagents/agent-abc.jsonl" "$C | tail -1"
vrun "subagent piped it                -> block"  "$p" "$lab/tr-parent2.jsonl" block

# --- repeated stops are capped, not abandoned --------------------------------
# Exiting on stop_hook_active made the gate a one-shot nudge: a second Stop always succeeded,
# whatever the session did in between.
vactive() { # vactive <label> <cwd> <transcript> <session> <expect block|warn>
  local label="$1" cwd="$2" tr="$3" sid="$4" expect="$5" out decision sysmsg
  out=$(jq -n --arg c "$cwd" --arg t "$tr" --arg s "$sid" \
        '{cwd:$c,transcript_path:$t,stop_hook_active:true,session_id:$s}' | "$vguard" 2>&1)
  decision=$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null)
  sysmsg=$(printf '%s' "$out" | jq -r '.systemMessage // empty' 2>/dev/null)
  case "$expect" in
    block) if [ "$decision" = block ]; then echo "  PASS  $label"; pass=$((pass+1))
           else echo "  FAIL  $label: expected block, got '$(printf '%s' "$out" | tr -d '\n' | cut -c1-90)'"; fail=$((fail+1)); fi ;;
    warn)  if [ -n "$sysmsg" ] && [ "$decision" != block ]; then echo "  PASS  $label"; pass=$((pass+1))
           else echo "  FAIL  $label: expected a systemMessage and no block, got '$(printf '%s' "$out" | tr -d '\n' | cut -c1-90)'"; fail=$((fail+1)); fi ;;
  esac
}

pcap=$(vlab vg-capped "In Progress" "Complete" "$C"); tr_bash "$lab/tr-cap.jsonl" "echo nope"
sid="test-$$-capped"
rm -f "${TMPDIR:-/tmp}/sdd-vguard-$sid".* 2>/dev/null
vactive "stop_hook_active, 1st re-check  -> block" "$pcap" "$lab/tr-cap.jsonl" "$sid" block
vactive "stop_hook_active, 2nd re-check  -> block" "$pcap" "$lab/tr-cap.jsonl" "$sid" block
vactive "stop_hook_active, 3rd           -> warn"  "$pcap" "$lab/tr-cap.jsonl" "$sid" warn
vactive "stop_hook_active, 4th           -> warn"  "$pcap" "$lab/tr-cap.jsonl" "$sid" warn

# A different violation in the same session gets its own allowance, rather than inheriting a
# count spent on a task that has since been fixed.
pcap2=$(vlab vg-capped2 "In Progress" "Complete" "./scripts/other.sh"); tr_bash "$lab/tr-cap2.jsonl" "echo different"
vactive "a new violation, same session   -> block" "$pcap2" "$lab/tr-cap2.jsonl" "$sid" block

# --- check-delegates.sh ----------------------------------------------------
# Same discipline as check-agy-grants.sh: the SILENT cases are the important assertions. This
# hook fires at every session start, so a false positive is how it gets turned off, and a hook
# that has been turned off is not a control.
#
# It must also never reach the network. A curl shim that fails the test proves that, rather than
# a comment claiming it.
deleg="$SDD_DELEGATION/hooks/check-delegates.sh"
if [ -z "$SDD_DELEGATION" ]; then
  echo "  skip  check-delegates.sh: the delegation plugin is not in this tree"
else
echo
echo "check-delegates.sh"

# dcase <name> <user json|-> <project json|-> <setup: none|dir|full|legacy> <expect: silent|warn> [needle]
dcase() {
  local name="$1" usr="$2" proj="$3" setup="$4" expect="$5" needle="${6:-}"
  local d out rc
  d=$(mktemp -d "$lab/deleg.XXXXXX")
  mkdir -p "$d/home/.claude" "$d/repo/.claude" "$d/shim"
  ( cd "$d/repo" && git init -q . && git commit -q --allow-empty -m init ) >/dev/null 2>&1
  [ "$usr"  != "-" ] && printf '%s' "$usr"  > "$d/home/.claude/settings.json"
  [ "$proj" != "-" ] && printf '%s' "$proj" > "$d/repo/.claude/settings.json"

  local st="$d/home/.local/state/delegation"
  case "$setup" in
    dir)    mkdir -p "$st/consult" ;;
    full)   mkdir -p "$st/consult" "$st/alt"
            printf 'tok\n' > "$st/consult/.credentials.json"
            printf '{"env":{"OTEL_RESOURCE_ATTRIBUTES":"service.name=claude-code,deployment.environment=alt"}}\n' \
              > "$st/alt/settings.local.json" ;;
    legacy) mkdir -p "$st/consult" "$d/home/.claude-worker"
            printf 'tok\n' > "$st/consult/.credentials.json"
            ln -sfn "$d/home/.claude/settings.json" "$d/home/.claude-worker/settings.json" ;;
  esac

  # Any network call fails the case outright.
  printf '#!/usr/bin/env bash\nexit 99\n' > "$d/shim/curl"; chmod +x "$d/shim/curl"
  printf '#!/usr/bin/env bash\nexit 99\n' > "$d/shim/wget"; chmod +x "$d/shim/wget"

  out=$( cd "$d/repo" && HOME="$d/home" XDG_STATE_HOME="$d/home/.local/state" \
         PATH="$d/shim:$PATH" "$deleg" < /dev/null 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL  $name: exited $rc; this hook must always exit 0"; fail=$((fail+1)); return
  fi
  if [ "$expect" = silent ]; then
    if [ -z "$out" ]; then echo "  PASS  $name -> silent"; pass=$((pass+1))
    else echo "  FAIL  $name: expected silence, got '${out:0:140}'"; fail=$((fail+1)); fi
    return
  fi
  if [ -z "$out" ]; then
    echo "  FAIL  $name: expected a warning, got silence"; fail=$((fail+1)); return
  fi
  if [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF -- "$needle"; then
    echo "  FAIL  $name: warning lacks '$needle': ${out:0:160}"; fail=$((fail+1)); return
  fi
  echo "  PASS  $name -> warns"; pass=$((pass+1))
}

ALT_GRANT='{"permissions":{"allow":["Bash(alt-consult:*)"]}}'
LOC_GRANT='{"permissions":{"allow":["Bash(local-consult:*)"]}}'
NO_GRANT='{"permissions":{"allow":["Bash(ls:*)"]}}'

# The silent cases, which matter most.
dcase "no settings at all"            -           -           none silent
dcase "grants nothing delegate-shaped" "$NO_GRANT" -          none silent
dcase "granted and fully set up"      "$ALT_GRANT" -          full silent
dcase "lane deliberately switched off" \
      '{"permissions":{"allow":["Bash(alt-consult:*)"]},"env":{"DELEGATION_ALT":"off"}}' - none silent

# The real failure modes after the wrappers ship: setup not run, then not signed in.
dcase "granted but setup never run"   "$ALT_GRANT" -          none warn "delegate-setup"
dcase "set up but not signed in"      "$ALT_GRANT" -          dir  warn "auth login"
dcase "the login command is fish-safe" "$ALT_GRANT" -         dir  warn "env CLAUDE_CONFIG_DIR"

# The local lane, granted with nowhere to reach.
dcase "local granted, no endpoint"    "$LOC_GRANT" -          full warn "LITELLM_BASE_URL"
dcase "local granted and configured"  \
      '{"permissions":{"allow":["Bash(local-consult:*)"]},"env":{"LITELLM_BASE_URL":"http://x:4000"}}' \
      - full silent
dcase "local off is not a problem"    \
      '{"permissions":{"allow":["Bash(local-consult:*)"]},"env":{"DELEGATION_LOCAL":"off"}}' \
      - full silent

# A project grant is intent too, not just the user layer.
dcase "project-level grant counts"    -            "$ALT_GRANT" none warn "delegate-setup"

echo
echo "  (check-delegates.sh: OTel collision)"

# The alt dir symlinks the primary's settings.json on purpose, so comparing files would warn on
# every correct machine. What resolves the collision is the override delegate-alt passes.
OTEL_USR='{"permissions":{"allow":["Bash(alt-consult:*)"]},"env":{"OTEL_RESOURCE_ATTRIBUTES":"service.name=claude-code,host.name=h,deployment.environment=laptop"}}'
dcase "override present, no collision" "$OTEL_USR" -          full   silent
dcase "legacy dir with no override"    "$OTEL_USR" -          legacy warn "delegate-setup --check"

fi  # check-delegates.sh: skipped when delegation is not in this tree
# --- emit-delegation-rules.sh ----------------------------------------------
# Layer 1 of the three-layer lane switch: a session never told about a lane does not dispatch to
# it. The assertions that matter are the ABSENCE ones, because a lane described to a session that
# cannot use it produces a dispatch, a refusal and a confused retry.
#
# This hook fails OPEN, unlike every lane script here. It only describes, so describing a disabled
# lane costs one refused dispatch, while describing nothing costs the session every delegation
# rule the plugin has.
emitr="$SDD_DELEGATION/hooks/emit-delegation-rules.sh"
if [ -z "$SDD_DELEGATION" ]; then
  echo "  skip  emit-delegation-rules.sh: the delegation plugin is not in this tree"
else
echo
echo "emit-delegation-rules.sh"

# ecase <name> <user settings json|-> <check> <needle>
#   check: has | lacks | json | nonempty
ecase() {
  local name="$1" usr="$2" check="$3" needle="${4:-}"
  local d out rc ctx
  d=$(mktemp -d "$lab/emit.XXXXXX")
  mkdir -p "$d/home/.claude" "$d/repo"
  ( cd "$d/repo" && git init -q . ) >/dev/null 2>&1
  [ "$usr" != "-" ] && printf '%s' "$usr" > "$d/home/.claude/settings.json"
  out=$( cd "$d/repo" && HOME="$d/home" "$emitr" < /dev/null 2>&1 ); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  FAIL  $name: exited $rc; a SessionStart hook must always exit 0"; fail=$((fail+1)); return
  fi
  ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
  case "$check" in
    json)
      if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null 2>&1
      then echo "  PASS  $name -> valid hook JSON"; pass=$((pass+1))
      else echo "  FAIL  $name: not valid hook JSON: ${out:0:120}"; fail=$((fail+1)); fi ;;
    has)
      if printf '%s' "$ctx" | grep -qF -- "$needle"
      then echo "  PASS  $name -> describes '$needle'"; pass=$((pass+1))
      else echo "  FAIL  $name: context lacks '$needle'"; fail=$((fail+1)); fi ;;
    lacks)
      if printf '%s' "$ctx" | grep -qF -- "$needle"
      then echo "  FAIL  $name: context still mentions '$needle'"; fail=$((fail+1))
      else echo "  PASS  $name -> silent about '$needle'"; pass=$((pass+1)); fi ;;
    nonempty)
      if [ -n "$ctx" ]
      then echo "  PASS  $name -> still emits the always-on rules"; pass=$((pass+1))
      else echo "  FAIL  $name: emitted nothing at all"; fail=$((fail+1)); fi ;;
  esac
}

ALT_OFF='{"env":{"DELEGATION_ALT":"off"}}'
LOC_OFF='{"env":{"DELEGATION_LOCAL":"off"}}'
BOTH_OFF='{"env":{"DELEGATION_ALT":"off","DELEGATION_LOCAL":"off"}}'

ecase "both lanes on: alt described"   - has   "alt-consult"
ecase "both lanes on: local described" - has   "local-consult"
ecase "always-on rules survive"        - has   "delegation:architect"
ecase "emits valid hook JSON"          - json

ecase "alt off: no alt-consult"        "$ALT_OFF" lacks "alt-consult"
ecase "alt off: no ALT- status names"  "$ALT_OFF" lacks "ALT-BUDGET"
ecase "alt off: local survives"        "$ALT_OFF" has   "local-consult"

ecase "local off: no local-consult"    "$LOC_OFF" lacks "local-consult"
ecase "local off: no LOCAL- names"     "$LOC_OFF" lacks "LOCAL-REFUSED"
ecase "local off: alt survives"        "$LOC_OFF" has   "alt-consult"

ecase "both off: still emits rules"    "$BOTH_OFF" nonempty
ecase "both off: architect rule kept"  "$BOTH_OFF" has   "delegation:architect"
ecase "both off: no lane text"         "$BOTH_OFF" lacks "alt-consult"
ecase "both off: probe dropped too"    "$BOTH_OFF" lacks "delegate-probe"

# Fails open: describing a lane that is off costs one refused dispatch, describing nothing costs
# the session every rule this plugin has.
ecase "unparseable settings: opens"    '{"env":{"DELEGATION_ALT": oops' nonempty
ecase "unparseable settings: full doc" '{"env":{"DELEGATION_ALT": oops' has "alt-consult"

# The markers are an implementation detail and must never reach a session.
ecase "markers are stripped"           - lacks "<!-- lane:"
ecase "closing markers too"            "$ALT_OFF" lacks "lane:"
fi  # emit-delegation-rules.sh (second block): skipped when delegation is not in this tree

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
