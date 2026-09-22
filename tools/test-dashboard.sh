#!/usr/bin/env bash
# Assert the project dashboard: the report generator, the server and the refresh hook.
#
# Every case builds its own git repo, spec tree and dashboard directory under a scratch lab, and
# SDD_DASHBOARD_DIR points the scripts there, so no run touches a real project's dashboard or a
# server the developer already has running. The servers bind 127.0.0.1 on a port picked free for
# the run, never the default, for the same reason.
#
# Needs bash, git, python3 and curl.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/plugin-root.sh
. "$here/plugin-root.sh"
sdd="$SDD_PLUGIN"
report="$sdd/scripts/sdd-report"
dash="$sdd/scripts/sdd-dashboard"
hook="$sdd/hooks/dashboard-refresh.sh"
for f in "$report" "$dash" "$hook" "$sdd/hooks/dashboard-session-end.sh"; do
  [ -x "$f" ] || { echo "FAIL: $f is not executable"; exit 1; }
done

lab=$(mktemp -d)
servers=()
cleanup() {
  for d in "${servers[@]+"${servers[@]}"}"; do SDD_DASHBOARD_DIR="$d" "$dash" stop >/dev/null 2>&1; done
  rm -rf "$lab"
}
trap cleanup EXIT

pass=0; fail=0
ok()  { echo "  PASS  $1"; pass=$((pass+1)); return 0; }
bad() { echo "  FAIL  $1"; fail=$((fail+1)); return 0; }
chk() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$2', got '$1')"; fi; }
has() { if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else bad "$3 (no match for '$2')"; fi; }
hasnt(){ if printf '%s' "$1" | grep -qF -- "$2"; then bad "$3 (unexpected '$2')"; else ok "$3"; fi; }

. "$here/lib-lab.sh"

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'; }

# A project with a spec tree covering every artefact kind the generator reads.
mkproject() {
  local r; r=$(mkrepo "$1")
  mkdir -p "$r/.specs/docs/specs" "$r/.specs/docs/plans" "$r/.specs/docs/designs" \
           "$r/.specs/docs/tasks/phase-1"
  g "$r/.specs" init -q
  printf '# Phase 1: Foundation\n\n**Status:** 🟢 Complete\n' > "$r/.specs/docs/specs/phase-1_foundation.md"
  printf '# Phase 2: Widgets\n\n**Status:** 🟡 Partly built 2026-09-07\n' > "$r/.specs/docs/specs/phase-2_widgets.md"
  printf '# Phase 3: Polish\n\n**Status:** 🔵 Not Started\n' > "$r/.specs/docs/specs/phase-3_polish.md"
  printf '# Widget plan\n\n**Status:** 🟡 In Progress\n\n### Task 1: a\n\n### Task 2: b\n\n### Task 3: c\n\n### Task 4: d\n' \
    > "$r/.specs/docs/plans/2026-09-10-widget.md"
  printf '# Old plan\n\n**Status:** 🟢 Complete\n' > "$r/.specs/docs/plans/2026-08-01-old.md"
  printf '# Widget design\n\n- **Status**: Approved\n' > "$r/.specs/docs/designs/2026-09-01-widget.md"
  printf '# 1.01 Setup\n\n**Status:** Complete\n' > "$r/.specs/docs/tasks/phase-1/1.01-setup.md"
  printf '# 1.02 Blocked thing\n\n**Status:** Blocked\n' > "$r/.specs/docs/tasks/phase-1/1.02-blocked.md"
  echo "$r"
}

# A report carrying every marker plus hand-written text that must survive.
mkreport() {
  mkdir -p "$1/content"
  cat > "$1/content/report.html" <<'HTML'
<div class="sdd-report">
<p>HANDWRITTEN-BEFORE</p>
<!--GEN:generated-->stale stamp<!--/GEN:generated-->
<p>HANDWRITTEN-DECISIONS</p>
<!--GEN:plans-->stale plans<!--/GEN:plans-->
<p>HANDWRITTEN-BETWEEN</p>
<!--GEN:commits-->STALE-COMMIT-LIST<!--/GEN:commits-->
<p>HANDWRITTEN-AFTER</p>
</div>
HTML
}

echo "sdd-report"

# --- marker replacement leaves hand-written text intact ------------------------
p=$(mkproject proj)
g "$p" commit -q --allow-empty -m 'feat: <script>alert(1)</script> & "quotes"'
d="$lab/dash"; mkreport "$d"
out=$(SDD_DASHBOARD_DIR="$d" "$report" --project "$p" 2>&1); rc=$?
chk "$rc" 0 "regenerates a report carrying every marker"
html=$(command cat "$d/content/report.html")
for s in HANDWRITTEN-BEFORE HANDWRITTEN-DECISIONS HANDWRITTEN-BETWEEN HANDWRITTEN-AFTER; do
  has "$html" "$s" "keeps hand-written text: $s"
done
hasnt "$html" "STALE-COMMIT-LIST" "replaces the generated region"
hasnt "$html" "stale plans" "replaces the plans region"
has "$html" "<!--GEN:commits-->" "keeps the opening marker, so the next run finds it"
has "$html" "<!--/GEN:commits-->" "keeps the closing marker"

# A second run must not duplicate anything: regeneration is a replacement, not an append.
SDD_DASHBOARD_DIR="$d" "$report" --project "$p" >/dev/null 2>&1
n=$(grep -c 'HANDWRITTEN-AFTER' "$d/content/report.html")
chk "$n" 1 "a second run leaves exactly one copy of the hand-written text"
n=$(grep -c '<!--GEN:commits-->' "$d/content/report.html")
chk "$n" 1 "a second run leaves exactly one marker pair"

# --- commit rows ---------------------------------------------------------------
has "$html" "&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;quotes&quot;" "escapes HTML in a commit subject"
hasnt "$html" "<script>alert(1)" "never emits a commit subject raw"
has "$html" "$(git -C "$p" rev-parse --short HEAD)" "names HEAD by its short sha"
has "$html" "$(date '+%Y-%m-%d')" "dates commits in local time"

# --- status parsing, through the real page -------------------------------------
has "$html" 'pill partly">partly' "a yellow 'Partly built' phase is partly, not done"
has "$html" "Partly built 2026-09-07" "shows the phase's status line"
has "$html" "1 / 3" "counts built phases over all phases"
has "$html" 'pill blocked">blocked' "a Blocked task file gets the blocked pill"
has "$html" "Approved" "lists designs with their status lines"

# --- no per-plan progress bar, and no foreign ledger ---------------------------
# The bar this replaces counted `### Task N` headings against another plugin's scratch ledger.
# Asserting its ABSENCE is the point: the dependency is gone and must not come back.
hasnt "$html" "tasks</" "renders no per-plan task bar"
hasnt "$html" "subagent ledger" "and does not mention a foreign ledger"

# Newest plan first.
first=$(grep -o 'Widget plan\|Old plan' "$d/content/report.html" | head -1)
chk "$first" "Widget plan" "lists plans newest first"

# --- a missing marker fails loudly and writes nothing ---------------------------
d2="$lab/dash2"; mkreport "$d2"
sed -i.bak 's|<!--/GEN:commits-->||' "$d2/content/report.html"; rm -f "$d2/content/report.html.bak"
before=$(command cat "$d2/content/report.html")
out=$(SDD_DASHBOARD_DIR="$d2" "$report" --project "$p" 2>&1); rc=$?
if [ "$rc" -ne 0 ]; then ok "a missing marker exits non-zero"; else bad "a missing marker exited 0"; fi
has "$out" "commits" "names the missing marker"
chk "$(command cat "$d2/content/report.html")" "$before" "leaves the report untouched when a marker is missing"

# --- classification, unit level ------------------------------------------------
cls=$(python3 -B - "$report" <<'PY'
import sys, importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader("sdd_report", sys.argv[1])
spec = importlib.util.spec_from_loader("sdd_report", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
for line in ["🟢 Complete", "🟡 In Progress", "🟡 Partly built 2026-09-07", "🟡 Live since Monday",
             "Partly built 2026-09-07", "🔴 Blocked on review", "⚪ Not started", "🔵 Planning",
             "Complete", "In Progress", "Draft", "🟢 Built, although partly documented"]:
    print(f"{line}={m.classify(line)}")
PY
)
while IFS='=' read -r line want; do
  got=$(printf '%s\n' "$cls" | grep -F "$line=" | head -1 | cut -d= -f2)
  chk "$got" "$want" "classifies '$line'"
done <<'EXPECT'
🟢 Complete=done
🟡 In Progress=running
🟡 Partly built 2026-09-07=partly
🟡 Live since Monday=partly
Partly built 2026-09-07=partly
🔴 Blocked on review=blocked
⚪ Not started=queued
🔵 Planning=queued
Complete=done
In Progress=running
Draft=queued
🟢 Built, although partly documented=done
EXPECT

# --- --if-exists is silent without a dashboard ----------------------------------
out=$(SDD_DASHBOARD_DIR="$lab/none" "$report" --project "$p" --if-exists 2>&1); rc=$?
chk "$rc" 0 "--if-exists exits 0 when no dashboard exists"
chk "$out" "" "--if-exists prints nothing when no dashboard exists"
if [ -e "$lab/none" ]; then bad "--if-exists created a dashboard directory"; else ok "--if-exists creates nothing"; fi

# --- --init scaffolds from the template -----------------------------------------
d3="$lab/dash3"
SDD_DASHBOARD_DIR="$d3" "$report" --project "$p" --init >/dev/null 2>&1
init=$(command cat "$d3/content/report.html" 2>/dev/null)
has "$init" "Decisions I made for you" "--init scaffolds the hand-written sections"
has "$init" "<!--/GEN:plans-->" "--init scaffolds the markers"
hasnt "$init" "{{PROJECT}}" "--init fills in the project name"
echo "HAND-EDIT" >> "$d3/content/report.html"
SDD_DASHBOARD_DIR="$d3" "$report" --project "$p" --init >/dev/null 2>&1
has "$(command cat "$d3/content/report.html")" "HAND-EDIT" "--init never overwrites an existing report"

echo "sdd-dashboard"

# --- start twice is idempotent ---------------------------------------------------
ds="$lab/srv"; mkreport "$ds"; servers+=("$ds")
port=$(free_port)
u1=$(SDD_DASHBOARD_DIR="$ds" "$dash" start --port "$port" --host 127.0.0.1 2>&1); rc1=$?
chk "$rc1" 0 "start exits 0"
pid1=$(command cat "$ds/state/server.pid" 2>/dev/null)
u2=$(SDD_DASHBOARD_DIR="$ds" "$dash" start 2>&1); rc2=$?
chk "$rc2" 0 "a second start exits 0"
pid2=$(command cat "$ds/state/server.pid" 2>/dev/null)
chk "$pid2" "$pid1" "a second start reuses the running server"
has "$u2" "already running" "a second start says it was already running"
url=$(SDD_DASHBOARD_DIR="$ds" "$dash" url)
has "$u1" "$url" "start printed the same URL that url prints"
has "$u2" "$url" "the second start printed the same URL"
has "$u1" "$ds/content" "start prints the content directory"
has "$u1" "$ds/state" "start prints the state directory"
SDD_DASHBOARD_DIR="$ds" "$dash" status >/dev/null 2>&1; chk "$?" 0 "status exits 0 while running"

# --- the key gate ------------------------------------------------------------------
base="http://127.0.0.1:$port"
code=$(curl -s -o /dev/null -w '%{http_code}' "$base/")
chk "$code" 403 "a request without the key is refused"
key=${url##*key=}
jar="$lab/jar"
code=$(curl -s -o /dev/null -w '%{http_code}' -c "$jar" "$base/?key=$key")
chk "$code" 303 "the key in the query string redirects to a clean URL"
echo "fake-png" > "$ds/content/shot.png"
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" "$base/files/shot.png")
chk "$code" 200 "a plain /files link works on the cookie alone"
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" "$base/files/../state/key")
chk "$code" 404 "/files cannot climb out of the content directory"

# --- / always serves the report ------------------------------------------------------
sleep 1
printf '<h2>MOCKUP-SENTINEL</h2>\n' > "$ds/content/mockup-login.html"
touch "$ds/content/mockup-login.html"
root=$(curl -s -b "$jar" "$base/")
has "$root" "HANDWRITTEN-AFTER" "/ serves the report while a newer mockup exists"
hasnt "$root" "MOCKUP-SENTINEL" "/ does not serve the newer mockup"
has "$root" "/view/mockup-login.html" "the frame nav lists the mockup"
# Poll rather than curl once. Observed failing intermittently, and only when the whole suite runs
# back to back: the file is written and fetched in the same breath, and a single request can beat
# the server to it. One flaky assertion is worse than a missing one, because it teaches everyone
# to re-run a red suite instead of reading it.
view=""
for _ in 1 2 3 4 5 6; do
  view=$(curl -s -b "$jar" "$base/view/mockup-login.html")
  printf '%s' "$view" | grep -q "MOCKUP-SENTINEL" && break
  sleep 0.5
done
has "$view" "MOCKUP-SENTINEL" "/view/<name> serves the mockup"

# A mockup folder copied verbatim from the spec repo, with an image referenced relatively.
mkdir -p "$ds/content/2026-09-14-login"
printf '<img src="login.png">\n' > "$ds/content/2026-09-14-login/index.html"
echo "fake-png" > "$ds/content/2026-09-14-login/login.png"
has "$(curl -s -b "$jar" "$base/")" "/view/2026-09-14-login/index.html" "the nav lists a mockup folder's page"
printf '<p>second</p>\n' > "$ds/content/2026-09-14-login/signup.html"
root=$(curl -s -b "$jar" "$base/")
has "$root" '<div class="frame-menu-group-name">login<span>2026-09-14</span>' "a mockup folder with several pages is one group in the menu"
has "$root" '<a href="/" class="current"><span>Dashboard</span></a>' "the menu marks the report as the current page"
has "$root" 'class="frame-needs"' "the frame carries the Needs you chip"
view=$(curl -s -b "$jar" "$base/view/2026-09-14-login/signup.html")
has "$view" '<span class="frame-menu-current">2026-09-14-login/signup</span>' "the menu button names the page being viewed"
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" "$base/view/2026-09-14-login/login.png")
chk "$code" 200 "a mockup's relative image resolves under /view/"

# --- the change feed ------------------------------------------------------------------
sig=$(curl -s -b "$jar" "$base/__changed?since=0&wait=0" | python3 -c 'import sys,json; print(json.load(sys.stdin)["sig"])')
ch=$(curl -s -b "$jar" "$base/__changed?since=$sig&wait=0")
has "$ch" '"changed": false' "an unchanged content dir reports no change"
sleep 1; echo "<p>edit</p>" >> "$ds/content/report.html"
ch=$(curl -s -b "$jar" --max-time 5 "$base/__changed?since=$sig")
has "$ch" '"changed": true' "an edit wakes the long poll"

# --- stop is idempotent -----------------------------------------------------------------
SDD_DASHBOARD_DIR="$ds" "$dash" stop >/dev/null 2>&1; chk "$?" 0 "stop exits 0"
if kill -0 "$pid1" 2>/dev/null; then bad "the server survived stop"; else ok "stop ends the process"; fi
out=$(SDD_DASHBOARD_DIR="$ds" "$dash" stop 2>&1); chk "$?" 0 "a second stop exits 0"
has "$out" "not running" "a second stop says it was not running"
if SDD_DASHBOARD_DIR="$ds" "$dash" status >/dev/null 2>&1; then
  bad "status exited 0 once stopped"
else
  ok "status exits non-zero once stopped"
fi

# --- a restart keeps its URL, and --no-key drops the gate ---------------------------------
SDD_DASHBOARD_DIR="$ds" "$dash" start >/dev/null 2>&1
chk "$(SDD_DASHBOARD_DIR="$ds" "$dash" url)" "$url" "a restart keeps the port and the key"
SDD_DASHBOARD_DIR="$ds" "$dash" stop >/dev/null 2>&1
SDD_DASHBOARD_DIR="$ds" "$dash" start --no-key >/dev/null 2>&1
code=$(curl -s -o /dev/null -w '%{http_code}' "$base/files/shot.png")
chk "$code" 200 "--no-key serves without a cookie"
hasnt "$(SDD_DASHBOARD_DIR="$ds" "$dash" url)" "key=" "--no-key prints a URL without a key"
SDD_DASHBOARD_DIR="$ds" "$dash" stop >/dev/null 2>&1

echo "dashboard-session-end.sh"

endhook="$sdd/hooks/dashboard-session-end.sh"
endjson() { python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SessionEnd","cwd":sys.argv[1],"reason":sys.argv[2]}))' "$1" "$2"; }
alive() { SDD_DASHBOARD_DIR="$1" "$dash" status >/dev/null 2>&1; }

# --- by default the session owns it: /clear and resume keep it, the real end stops it --------
dw="$lab/bound"; mkreport "$dw"; servers+=("$dw")
SDD_DASHBOARD_DIR="$dw" "$dash" start --port "$(free_port)" --host 127.0.0.1 >/dev/null 2>&1
for reason in clear resume; do
  endjson "$p" "$reason" | SDD_DASHBOARD_DIR="$dw" "$endhook" >/dev/null 2>&1
  if alive "$dw"; then ok "a default server survives reason=$reason"; else bad "reason=$reason stopped the server"; fi
done
out=$(endjson "$p" prompt_input_exit | SDD_DASHBOARD_DIR="$dw" "$endhook" 2>&1); rc=$?
chk "$rc" 0 "exits 0 after stopping"
chk "$out" "" "prints nothing after stopping"
if alive "$dw"; then bad "a default server survived the session ending"; else ok "a default server stops when the session ends"; fi
has "$(SDD_DASHBOARD_DIR="$dw" "$dash" status 2>&1)" "session ended" "status says the session ended it"

# --- --keep-running outlives the session, and is remembered ----------------------------------
SDD_DASHBOARD_DIR="$dw" "$dash" start --keep-running >/dev/null 2>&1
out=$(endjson "$p" prompt_input_exit | SDD_DASHBOARD_DIR="$dw" "$endhook" 2>&1); rc=$?
chk "$rc" 0 "exits 0 for a --keep-running server"
chk "$out" "" "prints nothing for a --keep-running server"
if alive "$dw"; then ok "--keep-running survives the session ending"; else bad "--keep-running was stopped by the session ending"; fi
SDD_DASHBOARD_DIR="$dw" "$dash" stop >/dev/null 2>&1
SDD_DASHBOARD_DIR="$dw" "$dash" start >/dev/null 2>&1
endjson "$p" other | SDD_DASHBOARD_DIR="$dw" "$endhook" >/dev/null 2>&1
if alive "$dw"; then ok "a restart remembers --keep-running"; else bad "a restart forgot --keep-running"; fi

# --stop-with-session takes effect on the running server, with no restart.
pid_before=$(command cat "$dw/state/server.pid")
SDD_DASHBOARD_DIR="$dw" "$dash" start --stop-with-session >/dev/null 2>&1
chk "$(command cat "$dw/state/server.pid" 2>/dev/null)" "$pid_before" "--stop-with-session does not restart a running server"
endjson "$p" other | SDD_DASHBOARD_DIR="$dw" "$endhook" >/dev/null 2>&1
if alive "$dw"; then bad "--stop-with-session did not rebind the running server"; else ok "--stop-with-session rebinds the running server"; fi

# --- a config saved before the default flipped gets the new default ---------------------------
# Those configs recorded "stop_with_session": false only because it was the default then, so it
# is no evidence anyone chose to keep the server running.
SDD_DASHBOARD_DIR="$dw" "$dash" start >/dev/null 2>&1
python3 - "$dw/state/config.json" <<'PY2'
import json, sys
c = json.load(open(sys.argv[1])); c.pop("keep_running", None); c["stop_with_session"] = False
json.dump(c, open(sys.argv[1], "w"))
PY2
endjson "$p" other | SDD_DASHBOARD_DIR="$dw" "$endhook" >/dev/null 2>&1
if alive "$dw"; then bad "an old config kept the server past the session"; else ok "an old config gets the stop-with-session default"; fi

out=$(endjson "$p" other | SDD_DASHBOARD_DIR="$lab/none" "$endhook" 2>&1); rc=$?
chk "$rc" 0 "exits 0 with no dashboard"
chk "$out" "" "prints nothing with no dashboard"
if [ -e "$lab/none" ]; then bad "created a dashboard directory"; else ok "creates nothing with no dashboard"; fi

echo "idle timeout"

# 0.001 hours is 3.6 seconds, checked every half second, so the case runs in seconds.
di="$lab/idle"; mkreport "$di"; servers+=("$di")
ip=$(free_port)
SDD_DASHBOARD_IDLE_CHECK_SECONDS=0.5 SDD_DASHBOARD_DIR="$di" "$dash" start --port "$ip" --host 127.0.0.1 --no-key --idle-hours 0.001 >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7; do curl -s -o /dev/null "http://127.0.0.1:$ip/"; sleep 1; done
if alive "$di"; then ok "a viewed server is not idle"; else bad "stopped while being viewed"; fi
for _ in $(seq 1 20); do alive "$di" || break; sleep 0.5; done
if alive "$di"; then bad "an unviewed server outlived its idle timeout"; else ok "an unviewed server stops itself after the idle timeout"; fi
has "$(SDD_DASHBOARD_DIR="$di" "$dash" status 2>&1)" "idle" "status says it stopped for being idle"
dd="$lab/idle-default"; mkreport "$dd"; servers+=("$dd")
SDD_DASHBOARD_DIR="$dd" "$dash" start --port "$(free_port)" --host 127.0.0.1 >/dev/null 2>&1
has "$(command cat "$dd/state/config.json")" '"idle_hours": 12' "a start with no flag saves the 12-hour default"
has "$(SDD_DASHBOARD_DIR="$dd" "$dash" status 2>&1)" "after 12 idle hours" "status names the default"
SDD_DASHBOARD_DIR="$dd" "$dash" stop >/dev/null 2>&1
SDD_DASHBOARD_DIR="$di" "$dash" start --idle-hours 0 >/dev/null 2>&1
has "$(command cat "$di/state/config.json")" '"idle_hours": 0' "--idle-hours 0 turns the timeout off"
SDD_DASHBOARD_DIR="$di" "$dash" stop >/dev/null 2>&1

echo "dashboard-refresh.sh"

hookjson() { python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$1" "$2"; }

out=$(hookjson "$p" "git commit -m x" | SDD_DASHBOARD_DIR="$lab/none" "$hook" 2>&1); rc=$?
chk "$rc" 0 "exits 0 with no dashboard"
chk "$out" "" "prints nothing with no dashboard"

dh="$lab/dash-hook"; mkreport "$dh"
hookjson "$p" "ls -la" | SDD_DASHBOARD_DIR="$dh" "$hook" >/dev/null 2>&1
has "$(command cat "$dh/content/report.html")" "STALE-COMMIT-LIST" "ignores a Bash call that is not a commit"
out=$(hookjson "$p" "git -C .specs commit -qm 'docs: x'" | SDD_DASHBOARD_DIR="$dh" "$hook" 2>&1); rc=$?
chk "$rc" 0 "exits 0 after a commit"
chk "$out" "" "prints nothing after a commit"
hasnt "$(command cat "$dh/content/report.html")" "STALE-COMMIT-LIST" "regenerates the report after a commit"

db="$lab/dash-broken"; mkreport "$db"; sed -i.bak 's|<!--GEN:plans-->||' "$db/content/report.html"
out=$(hookjson "$p" "git commit -m x" | SDD_DASHBOARD_DIR="$db" "$hook" 2>&1); rc=$?
chk "$rc" 0 "never fails the tool, even when the report is broken"
chk "$out" "" "stays silent when the report is broken"

echo "picks.js"

picks="$sdd/scripts/picks.js"
if [ -r "$picks" ]; then ok "picks.js ships with the plugin"; else bad "picks.js does not ship"; fi

if command -v node >/dev/null 2>&1; then
  if node --check "$picks" >/dev/null 2>&1; then ok "picks.js parses"; else bad "picks.js does not parse"; fi
else
  echo "  SKIP  picks.js parse check (no node)"
fi

# A committed mockup set references picks.js relatively, so the server has to hand it back as a
# plain file from inside the folder rather than wrapping it in the HTML frame.
dp="$lab/dash-picks"; mkreport "$dp"; servers+=("$dp")
mkdir -p "$dp/content/2026-09-15-audio"
cp "$here/fixtures/picks/page.html" "$dp/content/2026-09-15-audio/music.html"
cp "$picks" "$dp/content/2026-09-15-audio/picks.js"
pp=$(free_port)
SDD_DASHBOARD_DIR="$dp" "$dash" start --port "$pp" --host 127.0.0.1 --no-key >/dev/null 2>&1
base="http://127.0.0.1:$pp/view/2026-09-15-audio"
has "$(curl -s -D - -o /dev/null "$base/picks.js")" "text/javascript" "serves picks.js as javascript"
body=$(curl -s "$base/picks.js")
has "$body" "data-pick-group" "serves the real picks.js"
hasnt "$body" "frame-live" "does not run picks.js through the page frame"
has "$(curl -s "$base/music.html")" 'src="picks.js"' "a mockup keeps its relative script path"
SDD_DASHBOARD_DIR="$dp" "$dash" stop >/dev/null 2>&1

# The prompt is built in the DOM, so the only honest check is a real engine. Skipped rather than
# faked where there is no browser: a shim would assert the shim.
chrome=$(command -v google-chrome-stable || command -v chromium || command -v chromium-browser || command -v google-chrome || true)
if [ -z "$chrome" ]; then
  echo "  SKIP  picks.js behaviour (no chrome on PATH)"
else
  pl="$lab/picks/2026-09-15-audio"; mkdir -p "$pl"
  cp "$here/fixtures/picks/page.html" "$pl/music.html"
  cp "$picks" "$pl/picks.js"
  "$chrome" --headless=new --disable-gpu --no-sandbox --user-data-dir="$lab/picks/profile" \
    --virtual-time-budget=4000 --dump-dom "file://$pl/music.html" >"$lab/picks/dom.html" 2>/dev/null
  pre() { python3 -c 'import sys,re,html
d=open(sys.argv[1],encoding="utf-8").read()
m=re.search(r"<pre id=\"%s\"[^>]*>(.*?)</pre>"%sys.argv[2],d,re.S)
sys.stdout.write(html.unescape(m.group(1)) if m else "")' "$lab/picks/dom.html" "$1"; }
  out=$(pre sdd-test-out); meta=$(pre sdd-test-meta)

  has "$out" "Picks from 2026-09-15-audio/music.html (Music for calm play)" "names the page and its title"
  has "$out" "Music: the warm half (spring and summer)" "uses data-pick-label for a group"
  has "$out" "Music: the cold half (autumn and winter)" "falls back to a group's own heading, not an option's"
  has "$out" "  -> With the wind (seamless)   [with-the-wind]" "carries the label and the id"
  hasnt "$out" "sun-and-moon" "a single-select group keeps only the last pick"
  has "$out" "  -> Whoosh, basic light organic   [whoosh-light]" "an option with no heading falls back to its text"
  has "$out" "  -> Whoosh, basic thump   [whoosh-thump]" "a data-pick-multi group keeps both picks"
  has "$out" "Not picked yet:" "names the groups left unanswered"
  has "$out" "  Music: menu and intro (quieter)" "lists an unanswered group by label"
  notelen=$(printf '%s\n' "$out" | sed -n 's/^ *note: \(N*\)$/\1/p' | tr -d '\n' | wc -c | tr -d ' ')
  chk "$notelen" "280" "caps a note at 280 characters in the prompt"

  # Six groups survive collection: the duplicate id, the uppercase id and the second option
  # sharing an id are all refused, which is the whole of the client-side validation.
  has "$meta" "groups=6" "refuses a duplicate and a malformed group id"
  has "$meta" "notes=5" "data-pick-note=off drops that group's note box"
  has "$meta" "picked=5" "marks every picked option and no others"
  has "$meta" "summary=4 of 6 picked:" "the bar counts groups, not options"
fi

echo "standalone nav and capture zoom"

# A page that is its own document keeps its own head and styles, so it never goes through the
# frame and used to arrive with no way back to the dashboard.
dn="$lab/dash-nav"; mkreport "$dn"; servers+=("$dn")
mkdir -p "$dn/content/2026-09-12-set"
cat > "$dn/content/2026-09-12-set/one.html" <<'EOF'
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>One</title></head>
<body><h1>One</h1></body></html>
EOF
cat > "$dn/content/2026-09-12-set/two.html" <<'EOF'
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Two</title></head>
<body><h1>Two</h1></body></html>
EOF
np=$(free_port)
SDD_DASHBOARD_DIR="$dn" "$dash" start --port "$np" --host 127.0.0.1 --no-key >/dev/null 2>&1
full=$(curl -s "http://127.0.0.1:$np/view/2026-09-12-set/one.html")
frag=$(curl -s "http://127.0.0.1:$np/")

has "$full" 'class="sdd-nav"' "a full document gets the injected nav"
has "$full" 'href="/">&#8592; Dashboard' "the injected nav links back to the report"
has "$full" '/view/2026-09-12-set/two.html' "the injected nav lists a sibling page"
has "$full" 'aria-current="page"' "the injected nav marks the page you are on"
has "$full" "<!DOCTYPE html>" "a full document keeps its own doctype"
hasnt "$full" "frame-menu-group" "a full document does not get the frame's own menu"
hasnt "$frag" 'class="sdd-nav"' "a page served through the frame gets no injected nav"

# The zoom lives in the frame, so a report scaffolded before this change picks it up on its next
# load with no edit to the report itself.
has "$frag" 'class="frame-zoom"' "the frame carries the zoom dialog"
has "$frag" "cursor: zoom-in" "the frame marks captures as clickable"
has "$frag" "showModal" "the zoom uses the native dialog"
hasnt "$full" 'class="frame-zoom"' "a full document is left alone by the zoom"
SDD_DASHBOARD_DIR="$dn" "$dash" stop >/dev/null 2>&1

if [ -z "$chrome" ]; then
  echo "  SKIP  zoom behaviour (no chrome on PATH)"
else
  zl="$lab/zoom"; mkdir -p "$zl"
  # Serve-time injection is the thing under test, so the page is taken from the server and only
  # its long poll removed, which would otherwise keep headless chrome from ever going idle.
  zp=$(free_port)
  SDD_DASHBOARD_DIR="$dn" "$dash" start --port "$zp" --host 127.0.0.1 --no-key >/dev/null 2>&1
  printf 'x' > "$dn/content/shot.png"
  python3 - "$zp" "$zl/page.html" <<'EOF'
import re, sys, urllib.request
s = urllib.request.urlopen(f"http://127.0.0.1:{sys.argv[1]}/").read().decode()
s = re.sub(r"<script>(?:(?!</script>).)*?poll\(\);(?:(?!</script>).)*?</script>", "", s, flags=re.S)
s = s.replace("</body>", """<script>window.addEventListener('load', function () {
  // The listener is delegated from .frame-content, so the capture has to live inside it, which is
  // where a report's own Screenshots section puts one.
  var host = document.querySelector('.frame-content .sdd-report') || document.querySelector('.frame-content');
  var o = document.createElement('pre'); o.id = 'probe'; o.hidden = true;
  if (!host) { o.textContent = 'NO FRAME CONTENT'; document.body.appendChild(o); return; }
  var fig = document.createElement('figure');
  fig.innerHTML = '<img alt="a" src="data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==">'
                + '<figcaption>the caption</figcaption>';
  host.appendChild(fig);
  fig.querySelector('img').click();
  var d = document.querySelector('.frame-zoom');
  o.textContent = 'open=' + d.open + ' caption=' + d.querySelector('figcaption').textContent;
  document.body.appendChild(o);
});</script></body>""")
open(sys.argv[2], "w", encoding="utf-8").write(s)
EOF
  "$chrome" --headless=new --disable-gpu --no-sandbox --user-data-dir="$zl/profile" \
    --virtual-time-budget=4000 --dump-dom "file://$zl/page.html" >"$zl/dom.html" 2>/dev/null
  probe=$(python3 -c 'import sys,re,html
d=open(sys.argv[1],encoding="utf-8").read()
m=re.search(r"<pre id=\"probe\"[^>]*>(.*?)</pre>",d,re.S)
sys.stdout.write(html.unescape(m.group(1)) if m else "")' "$zl/dom.html")
  has "$probe" "open=true" "clicking a capture opens the dialog"
  has "$probe" "caption=the caption" "the dialog carries the figure's caption"
  SDD_DASHBOARD_DIR="$dn" "$dash" stop >/dev/null 2>&1
fi

echo "generated status cards"

# A report scaffolded before these cards existed must keep regenerating everything it always had.
# Making a new marker mandatory would have stopped every installed dashboard dead.
dold="$lab/dash-oldreport"; mkreport "$dold"
out=$(SDD_DASHBOARD_DIR="$dold" "$report" --project "$p" 2>&1); rc=$?
chk "$rc" 0 "a report predating the new cards still regenerates"
has "$out" "predates" "and says which cards it skipped"
hasnt "$(cat "$dold/content/report.html")" "STALE-COMMIT-LIST" "and its commits region is still rewritten"
has "$(cat "$dold/content/report.html")" "HANDWRITTEN-DECISIONS" "leaving the hand-written sections alone"

# Tests and In progress were typed by hand until 2026-09-16. The rule to keep them current
# already existed in dashboard-upkeep and did not hold on its author, so they are read now.
# Scaffolded by --init from the current template, not by mkreport, which writes the older
# three-marker shape on purpose for the test above.
dg="$lab/dash-cards"
p2="$lab/proj-cards"
mkdir -p "$p2/.specs/docs/tasks/phase-1" "$p2/evals/results/20260916-120000"
git -C "$p2" init -q 2>/dev/null; git -C "$p2" -c user.name=t -c user.email=t@e commit -q --allow-empty -m init
cat > "$p2/CLAUDE.md" <<'EOF'
## Task Workflow
- **Spec Repo**: `.specs/`
- **Task Directory**: `.specs/docs/tasks/phase-N/`
EOF
git -C "$p2/.specs" init -q 2>/dev/null

# no meta.json yet
out=$(SDD_DASHBOARD_DIR="$dg" "$report" --init --project "$p2" 2>&1; cat "$dg/content/report.html")
has "$out" "never run here" "with no eval results the Tests card says so, rather than nothing"
has "$out" "nothing marked in progress" "and In progress reads the task files"

# a passing run
jq -n '{stamp:"20260916-120000", head:"abc1234def", claude_version:"t", runs:3, filter:"",
        threshold:1.0, cases:2, suite_passed:true, plugin_trees:{sdd:"clean"},
        plugin_results:{sdd:{cases:2,passed:2}}}' > "$p2/evals/results/20260916-120000/meta.json"
SDD_DASHBOARD_DIR="$dg" "$report" --project "$p2" >/dev/null 2>&1
out=$(cat "$dg/content/report.html")
has "$out" "2 / 2 passed" "it reports the measured counts"
has "$out" "abc1234" "and the commit they were measured at"
hasnt "$out" "never run here" "and stops saying it was never run"

# a failing run must not read as passing
jq -n '{stamp:"20260916-130000", head:"abc1234def", claude_version:"t", runs:3, filter:"",
        threshold:1.0, cases:2, suite_passed:false, plugin_trees:{sdd:"clean"},
        plugin_results:{sdd:{cases:2,passed:1}}}' > "$p2/evals/results/20260916-120000/meta.json"
SDD_DASHBOARD_DIR="$dg" "$report" --project "$p2" >/dev/null 2>&1
out=$(cat "$dg/content/report.html")
has "$out" "1 / 2 FAILED" "a failing run is reported as failing"
has "$out" "pill blocked" "and carries the blocked pill, not the done one"

# a dirty tree means the commit does not describe what ran
jq -n '{stamp:"20260916-140000", head:"abc1234def", claude_version:"t", runs:3, filter:"",
        threshold:1.0, cases:2, suite_passed:true, plugin_trees:{sdd:"dirty"},
        plugin_results:{sdd:{cases:2,passed:2}}}' > "$p2/evals/results/20260916-120000/meta.json"
SDD_DASHBOARD_DIR="$dg" "$report" --project "$p2" >/dev/null 2>&1
has "$(cat "$dg/content/report.html")" "uncommitted tree" "a dirty measurement says the commit does not describe it"

# In progress reads the task files
printf '# Task 1.01: Thing\n\n**Status:** 🟡 In Progress\n' > "$p2/.specs/docs/tasks/phase-1/1.01-thing.md"
printf '# Task 1.02: Other\n\n**Status:** Complete\n' > "$p2/.specs/docs/tasks/phase-1/1.02-other.md"
SDD_DASHBOARD_DIR="$dg" "$report" --project "$p2" >/dev/null 2>&1
card=$(python3 -c "
import re,sys
s=open('$dg/content/report.html',encoding='utf-8').read()
m=re.search(r'<!--GEN:inprogress-->(.*?)<!--/GEN:inprogress-->',s,re.S)
sys.stdout.write(m.group(1) if m else '')")
has "$card" "1.01-thing" "In progress lists a task whose status says so"
hasnt "$card" "1.02-other" "and not one that is Complete"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
