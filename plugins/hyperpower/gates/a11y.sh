#!/bin/sh
# a11y gate. Boots commands.dev_server, waits for commands.dev_url to answer, and runs the
# axe CLI against the changed route.
#
# Fails on any violation whose impact is serious or critical. That threshold is hardcoded:
# the hyperpower.yml schema in docs/configuration.md has no field for it, and this gate never
# reads a field that is not in the schema. To change what blocks, edit BLOCKING_IMPACTS here.
# moderate and minor violations are counted and reported, and they never fail the gate.
#
# Exit 78 when the gate is disabled, when commands.dev_server or commands.dev_url is null,
# when the axe CLI is not on PATH, when no headless browser is installed for axe to drive,
# when neither curl nor wget is on PATH, or when axe prints no report this gate can read.
# Never exit 0 for any of those: a missing axe is an accessibility check that did not happen.
#
# A timeout is a fail, not a did-not-run. The budget covers booting the server and one axe
# run, so a scan that never finished inside it is a failure. hp-gates records its own
# timeouts the same way.
#
# The dev server is stopped on every exit path, including failure, timeout, INT and TERM.
set -eu

case ${1:-} in
  --help|-h)
    cat <<'EOF'
a11y.sh - hyperpower accessibility gate

Config JSON arrives on stdin. One JSON result object goes to stdout.

  printf '%s' '{"commands":{"dev_server":"pnpm dev","dev_url":"http://localhost:5173"}}' \
    | HYPERPOWER_ROUTE=/settings ./a11y.sh

Reads commands.dev_server, commands.dev_url, gates.a11y.enabled, gates.a11y.blocking, and
limits.gate_timeout_seconds.

Fails on serious and critical violations. moderate and minor are reported only. The
threshold is hardcoded because the config schema has no field for it.

Environment:
  HYPERPOWER_ROUTE        the route to scan. Defaults to / and the result says so.
  HYPERPOWER_RUN_DIR      run journal folder. The full log is copied to gates/a11y.log.
  HYPERPOWER_REPO_ROOT    directory the dev server runs in.
  HYPERPOWER_BROWSER_BIN  path to the browser axe drives. Defaults to the first of chromium,
                          chromium-browser, google-chrome, google-chrome-stable, chrome, or
                          a Chrome, Chromium, Edge or Brave app bundle on macOS.

Requires the axe CLI (npm install -g @axe-core/cli), a Chromium-family browser, and curl or
wget. Exit 0 pass, 1 fail, 78 could not run.
EOF
    exit 0
    ;;
esac

HP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HP_DIR/_lib.sh"

hp_init a11y

# hp-gates stops this script at limits.gate_timeout_seconds and gives it five seconds to die.
# The gate keeps this many seconds back so its own timer fires first: it then reports the
# timeout in its own words and stops the dev server before the outer killer arrives. A gate
# killed part way through teardown leaves the dev server running, because the server sits in
# its own session and hp-gates only signals this script's process group.
TEARDOWN_RESERVE=8
WORK_TIMEOUT=$((HP_TIMEOUT - TEARDOWN_RESERVE))
# A budget smaller than the reserve is not a real configuration. Use it whole rather than
# reduce it to nothing.
if [ "$WORK_TIMEOUT" -lt 1 ]; then WORK_TIMEOUT=$HP_TIMEOUT; fi

# The impacts that fail the gate. axe reports critical, serious, moderate and minor.
BLOCKING_IMPACTS="critical serious"

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN=python3; fi

LAUNCH_PID=""
LAUNCH_GROUP=0
SERVER_PID=""
SERVER_GROUP=0
SERVER_LOG=""
RUN_PID=""
RUN_GROUP=0
PROBE=""
GATE_STARTED=$(hp_now)

# ---------------------------------------------------------------- process control

# Every pid descended from the given pids, breadth first, six generations deep.
descendants() {
  d_list=$1
  d_all=""
  d_depth=0
  while [ -n "$d_list" ] && [ "$d_depth" -lt 6 ]; do
    d_next=$(ps -Ao pid=,ppid= 2>/dev/null | awk -v list="$d_list" '
      BEGIN { n = split(list, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
      $2 in want { printf "%s ", $1 }
    ' || true)
    if [ -z "$d_next" ]; then break; fi
    d_all="$d_all $d_next"
    d_list=$d_next
    d_depth=$((d_depth + 1))
  done
  printf '%s' "$d_all"
}

# stop_pid <pid> <in-own-group> — TERM, then KILL after three seconds. Never leaves a child.
# Three, not more: hp-gates gives this script five seconds between its TERM and its KILL, and
# a teardown that overruns that window is killed part way through.
stop_pid() {
  sp_pid=$1
  sp_group=$2
  if [ -z "$sp_pid" ]; then return 0; fi
  if [ "$sp_group" -eq 1 ]; then
    kill -TERM "-$sp_pid" 2>/dev/null || true
  else
    sp_kids=$(descendants "$sp_pid")
    kill -TERM $sp_kids "$sp_pid" 2>/dev/null || true
  fi
  sp_i=0
  while [ "$sp_i" -lt 3 ]; do
    if ! kill -0 "$sp_pid" 2>/dev/null; then break; fi
    sleep 1
    sp_i=$((sp_i + 1))
  done
  if kill -0 "$sp_pid" 2>/dev/null; then
    if [ "$sp_group" -eq 1 ]; then
      kill -KILL "-$sp_pid" 2>/dev/null || true
    else
      sp_kids=$(descendants "$sp_pid")
      kill -KILL $sp_kids "$sp_pid" 2>/dev/null || true
    fi
  fi
  wait "$sp_pid" 2>/dev/null || true
  return 0
}

gate_cleanup() {
  if [ -n "$RUN_PID" ]; then
    stop_pid "$RUN_PID" "$RUN_GROUP"
    RUN_PID=""
  fi
  if [ -n "$SERVER_PID" ]; then
    stop_pid "$SERVER_PID" "$SERVER_GROUP"
    SERVER_PID=""
  fi
  hp_cleanup
  return 0
}

trap 'gate_cleanup' EXIT
trap 'gate_cleanup; exit 130' INT
trap 'gate_cleanup; exit 143' TERM

# launch_group <stdout-file> <stderr-file> <command...> — starts a child in its own process
# group, so stop_pid can signal the whole tree. python3 is preferred because it keeps the pid
# it reports; setsid on some systems forks and reports the wrapper instead.
launch_group() {
  lg_out=$1
  lg_err=$2
  shift 2
  if [ -n "$PYTHON_BIN" ]; then
    "$PYTHON_BIN" -c 'import os, sys
os.setsid()
os.execvp(sys.argv[1], sys.argv[1:])' "$@" >"$lg_out" 2>"$lg_err" </dev/null &
    LAUNCH_PID=$!
    LAUNCH_GROUP=1
  elif command -v setsid >/dev/null 2>&1; then
    setsid "$@" >"$lg_out" 2>"$lg_err" </dev/null &
    LAUNCH_PID=$!
    LAUNCH_GROUP=1
  else
    "$@" >"$lg_out" 2>"$lg_err" </dev/null &
    LAUNCH_PID=$!
    LAUNCH_GROUP=0
  fi
  return 0
}

# start_server <command> <log> — boots the dev server under a supervisor in its own session,
# and sets SERVER_PID and SERVER_GROUP to it.
#
# The supervisor owns the server as its child, so one signal to its own process group stops
# the whole tree, however many processes the command forked. It stops on TERM, when this
# gate's pid disappears, and at a hard deadline. Those last two are the point: hp-gates kills
# a gate that overruns by signalling the gate's process group, the supervisor is not in that
# group, and a supervisor that only listened for TERM would then keep the server alive for
# ever. It watches the gate instead of trusting it.
#
# The supervisor exits with the dev server's own status, so the caller still reads 127 as a
# missing dependency rather than as a crash.
start_server() {
  ss_cmd=$1
  ss_log=$2
  ss_deadline=$((HP_TIMEOUT + 30))
  # The supervisor stops the server with `kill 0`, which signals its whole process group.
  # That group is the server's own only when launch_group can isolate it. With neither
  # python3 nor setsid the supervisor shares this gate's process group, and the group signal
  # would kill the gate and whatever called the gate. Start the server without a supervisor
  # there, and let stop_pid signal it and its children by pid.
  if [ -z "$PYTHON_BIN" ] && ! command -v setsid >/dev/null 2>&1; then
    launch_group "$ss_log" "$ss_log" sh -c "$ss_cmd"
    SERVER_PID=$LAUNCH_PID
    SERVER_GROUP=$LAUNCH_GROUP
    return 0
  fi
  launch_group "$ss_log" "$ss_log" sh -c '
    gate=$1
    budget=$2
    cmd=$3
    stop_tree() {
      trap "" TERM
      kill -TERM 0 2>/dev/null || true
      sleep 2
      kill -KILL 0 2>/dev/null || true
      exit 143
    }
    trap stop_tree TERM INT HUP
    (
      while [ "$budget" -gt 0 ]; do
        # Two questions, because one is not enough. kill -0 answers for a zombie, and a gate
        # that was killed stays a zombie until its own caller reaps it, so read the state as
        # well. A supervisor whose parent is no longer the gate has been reparented, which
        # says the same thing and survives pid reuse.
        parent=$(ps -o ppid= -p $$ 2>/dev/null | tr -d " " 2>/dev/null)
        [ "$parent" = "$gate" ] || break
        state=$(ps -o stat= -p "$gate" 2>/dev/null | tr -d " " 2>/dev/null)
        case ${state:-gone} in
          gone|Z*) break ;;
        esac
        sleep 1
        budget=$((budget - 1))
      done
      kill -TERM 0 2>/dev/null || true
    ) &
    ss_watch=$!
    sh -c "$cmd" &
    ss_kid=$!
    ss_status=0
    wait "$ss_kid" || ss_status=$?
    kill -TERM "$ss_watch" 2>/dev/null || true
    exit "$ss_status"
  ' hyperpower-dev-server "$$" "$ss_deadline" "$ss_cmd"
  SERVER_PID=$LAUNCH_PID
  SERVER_GROUP=$LAUNCH_GROUP
  return 0
}

# ---------------------------------------------------------------- budget

elapsed() {
  el_v=$(( $(hp_now) - GATE_STARTED ))
  if [ "$el_v" -lt 0 ]; then el_v=0; fi
  printf '%s' "$el_v"
}

remaining() {
  rm_v=$(( WORK_TIMEOUT - $(elapsed) ))
  if [ "$rm_v" -lt 0 ]; then rm_v=0; fi
  printf '%s' "$rm_v"
}

# ---------------------------------------------------------------- tools

find_browser() {
  if [ -n "${HYPERPOWER_BROWSER_BIN:-}" ]; then
    if [ -x "$HYPERPOWER_BROWSER_BIN" ]; then
      printf '%s' "$HYPERPOWER_BROWSER_BIN"
      return 0
    fi
    if command -v "$HYPERPOWER_BROWSER_BIN" >/dev/null 2>&1; then
      command -v "$HYPERPOWER_BROWSER_BIN"
      return 0
    fi
    return 1
  fi
  for fb_name in chromium chromium-browser google-chrome google-chrome-stable chrome; do
    if command -v "$fb_name" >/dev/null 2>&1; then
      command -v "$fb_name"
      return 0
    fi
  done
  for fb_path in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"; do
    if [ -x "$fb_path" ]; then
      printf '%s' "$fb_path"
      return 0
    fi
  done
  return 1
}

# Prints the HTTP status of one request. Empty or 000 means nothing answered.
probe_url() {
  pu_url=$1
  if [ "$PROBE" = curl ]; then
    curl -s -o /dev/null -m 10 -w '%{http_code}' "$pu_url" 2>/dev/null || printf ''
  else
    wget -q -S -O /dev/null -T 10 --tries=1 --max-redirect=0 "$pu_url" 2>&1 |
      awk '/^ *HTTP\// { code = $2 } END { print code }'
  fi
}

route_url() {
  ru_base=${1%/}
  ru_route=${2:-/}
  case $ru_route in
    http://*|https://*)
      printf '%s' "$ru_route"
      return 0
      ;;
  esac
  case $ru_route in
    /*) ;;
    *) ru_route=/$ru_route ;;
  esac
  printf '%s%s' "$ru_base" "$ru_route"
}

# True while the pid is alive and not yet a zombie. A finished child stays a zombie until it
# is waited for, and kill -0 still answers for one, so the state has to be read as well.
proc_running() {
  if [ -z "$1" ]; then return 1; fi
  if ! kill -0 "$1" 2>/dev/null; then return 1; fi
  pr_stat=$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ' || true)
  case $pr_stat in
    Z*) return 1 ;;
  esac
  return 0
}

server_alive() {
  proc_running "$SERVER_PID"
}

RUN_STATUS=0
RUN_TIMED_OUT=0
RUN_SECONDS=0

# run_bounded <stdout-file> <stderr-file> <budget> <command...> — runs the command to
# completion, or kills its whole process group when the budget runs out. Sets RUN_STATUS,
# RUN_TIMED_OUT and RUN_SECONDS. Nothing survives it.
run_bounded() {
  rb_out=$1
  rb_err=$2
  rb_budget=$3
  shift 3
  RUN_STATUS=0
  RUN_TIMED_OUT=0
  rb_started=$(hp_now)
  launch_group "$rb_out" "$rb_err" "$@"
  rb_pid=$LAUNCH_PID
  rb_group=$LAUNCH_GROUP
  RUN_PID=$rb_pid
  RUN_GROUP=$rb_group
  rb_waited=0
  while [ "$rb_waited" -lt "$rb_budget" ]; do
    if ! proc_running "$rb_pid"; then break; fi
    sleep 1
    rb_waited=$((rb_waited + 1))
  done
  if proc_running "$rb_pid"; then
    RUN_TIMED_OUT=1
    stop_pid "$rb_pid" "$rb_group"
  else
    wait "$rb_pid" 2>/dev/null || RUN_STATUS=$?
  fi
  RUN_PID=""
  RUN_SECONDS=$(( $(hp_now) - rb_started ))
  if [ "$RUN_SECONDS" -lt 0 ]; then RUN_SECONDS=0; fi
  return 0
}

# 0 answered, 1 budget spent, 2 the server exited first.
wait_ready() {
  wr_url=$1
  wr_budget=$2
  wr_waited=0
  while [ "$wr_waited" -lt "$wr_budget" ]; do
    wr_code=$(probe_url "$wr_url")
    case $wr_code in
      ''|000) ;;
      *) return 0 ;;
    esac
    if ! server_alive; then return 2; fi
    sleep 1
    wr_waited=$((wr_waited + 1))
  done
  return 1
}

# ---------------------------------------------------------------- config

if ! hp_enabled; then
  hp_did_not_run "gate disabled in hyperpower.yml" "gates.a11y.enabled is false"
fi

dev_server=$(hp_cfg_str commands.dev_server)
dev_url=$(hp_cfg_str commands.dev_url)
missing=""
missing_verb="is"
if [ -z "$dev_server" ]; then missing="commands.dev_server"; fi
if [ -z "$dev_url" ]; then
  if [ -n "$missing" ]; then
    missing="$missing and commands.dev_url"
    missing_verb="are"
  else
    missing="commands.dev_url"
  fi
fi
if [ -n "$missing" ]; then
  hp_did_not_run "$missing $missing_verb null or missing" \
    "set both in hyperpower.yml, or set gates.a11y.enabled to false. Both are null in the shipped schema."
fi

route=${HYPERPOWER_ROUTE:-/}
route_default=0
if [ -z "${HYPERPOWER_ROUTE:-}" ]; then route_default=1; fi
target=$(route_url "$dev_url" "$route")

if ! command -v axe >/dev/null 2>&1; then
  hp_did_not_run "the axe CLI is not on PATH" \
    "install it with: npm install -g @axe-core/cli. Then rerun /hyperpower:doctor."
fi

if command -v curl >/dev/null 2>&1; then
  PROBE=curl
elif command -v wget >/dev/null 2>&1; then
  PROBE=wget
else
  hp_did_not_run "no HTTP probe on PATH" \
    "install curl or wget, or set gates.a11y.enabled to false"
fi

browser_bin=$(find_browser || true)
if [ -z "$browser_bin" ]; then
  hp_did_not_run "axe browser prerequisite unmet: no Chromium-family browser installed" \
    "install Google Chrome or Chromium, or point HYPERPOWER_BROWSER_BIN at one. axe drives a real browser and cannot scan without one."
fi

# ---------------------------------------------------------------- run

TAB=$(printf '\t')
log=$HP_TMPDIR/a11y-gate.log
report=$HP_TMPDIR/axe.json
flat=$HP_TMPDIR/axe.tsv
rules=$HP_TMPDIR/violations.tsv
: > "$log"
: > "$report"

booted=0
preboot=$(probe_url "$dev_url")
case $preboot in
  ''|000)
    printf '=== boot: %s ===\n' "$dev_server" >> "$log"
    SERVER_LOG=$HP_TMPDIR/dev-server.log
    : > "$SERVER_LOG"
    start_server "$dev_server" "$SERVER_LOG"
    booted=1
    ;;
  *)
    printf '=== %s already answered %s. commands.dev_server was not started. ===\n' \
      "$dev_url" "$preboot" >> "$log"
    ;;
esac

if [ "$booted" -eq 1 ]; then
  budget=$(remaining)
  if [ "$budget" -le 0 ]; then
    cat "$SERVER_LOG" >> "$log"
    HP_OUT=$log
    hp_fail "a11y gate ran out of its ${WORK_TIMEOUT}s working budget before the dev server answered.$(hp_advisory_note)" \
      "$(hp_evidence)"
  fi
  ready=0
  wait_ready "$dev_url" "$budget" || ready=$?
  cat "$SERVER_LOG" >> "$log"
  if [ "$ready" -eq 2 ]; then
    server_status=0
    wait "$SERVER_PID" 2>/dev/null || server_status=$?
    SERVER_PID=""
    HP_OUT=$log
    if [ "$server_status" -eq 127 ]; then
      hp_did_not_run "commands.dev_server exited 127: a command it invokes is not installed" \
        "$(hp_evidence)"
    fi
    hp_fail "commands.dev_server exited $server_status before $dev_url answered.$(hp_advisory_note)" \
      "$(hp_evidence)"
  fi
  if [ "$ready" -ne 0 ]; then
    HP_OUT=$log
    hp_fail "$dev_url did not answer within ${WORK_TIMEOUT}s of the ${HP_TIMEOUT}s budget.$(hp_advisory_note)" "$(hp_evidence)"
  fi
fi

budget=$(remaining)
if [ "$budget" -le 0 ]; then
  HP_OUT=$log
  hp_fail "a11y gate ran out of its ${WORK_TIMEOUT}s working budget before axe started.$(hp_advisory_note)" \
    "$(hp_evidence)"
fi

# axe writes the report to stdout, and its progress and warnings to stderr. Mixing the two
# would corrupt the JSON, so each stream gets its own file. run_bounded owns the timeout, so
# a scan that overruns takes its whole process group down with it.
axe_err=$HP_TMPDIR/axe-stderr.log
run_bounded "$report" "$axe_err" "$budget" axe "$target" --stdout
printf '=== axe %s (exit %s in %ss) ===\n' "$target" "$RUN_STATUS" "$RUN_SECONDS" >> "$log"
tail -n 20 "$axe_err" >> "$log" 2>/dev/null || true
HP_OUT=$log

if [ "$RUN_TIMED_OUT" -eq 1 ]; then
  hp_fail "axe did not finish scanning $target within the ${budget}s left of its ${WORK_TIMEOUT}s working budget.$(hp_advisory_note)" \
    "$(hp_evidence)"
fi
if [ "$RUN_STATUS" -eq 127 ]; then
  hp_did_not_run "axe exited 127: a command it invokes is not installed" "$(hp_evidence)"
fi

# Strip anything an axe build prints before the JSON, then flatten it to dotted paths.
body=$HP_TMPDIR/axe-body.json
awk 'started { print; next } /^[[{]/ { started = 1; print }' "$report" > "$body" || true
: > "$flat"
if [ -s "$body" ]; then
  awk "$HP_JSON_AWK" < "$body" > "$flat" 2>/dev/null || : > "$flat"
fi

if ! grep -q -E '(^|\.)(testEngine\.name|violations\.[0-9]+\.id)[[:space:]]' "$flat" 2>/dev/null; then
  printf '=== axe report head ===\n' >> "$log"
  head -c 2000 "$report" >> "$log" 2>/dev/null || true
  hp_did_not_run "axe exited $RUN_STATUS and printed no report this gate could read" \
    "$(hp_evidence)"
fi

# One line per violation: impact, rule id, node count.
awk -F '\t' '
  {
    key = $1
    value = substr($0, length(key) + 2)
    if (key ~ /(^|\.)violations\.[0-9]+\.id$/) {
      prefix = substr(key, 1, length(key) - 3)
      id[prefix] = value
      seen[prefix] = 1
    } else if (key ~ /(^|\.)violations\.[0-9]+\.impact$/) {
      prefix = substr(key, 1, length(key) - 7)
      impact[prefix] = value
      seen[prefix] = 1
    } else if (key ~ /(^|\.)violations\.[0-9]+\.nodes\.[0-9]+\.html$/) {
      prefix = key
      sub(/\.nodes\.[0-9]+\.html$/, "", prefix)
      nodes[prefix]++
      seen[prefix] = 1
    }
  }
  END {
    for (p in seen) {
      im = (p in impact && impact[p] != "" && impact[p] != "null") ? impact[p] : "unknown"
      rule = (p in id && id[p] != "") ? id[p] : "unnamed-rule"
      rank = (im == "critical") ? 1 : (im == "serious") ? 2 : (im == "moderate") ? 3 : (im == "minor") ? 4 : 5
      printf "%d\t%s\t%s\t%d\n", rank, im, rule, nodes[p] + 0
    }
  }
' "$flat" | sort -t "$TAB" -k1,1n -k3,3 > "$rules" || true

count_impact() {
  awk -F '\t' -v want="$1" '$2 == want { n++ } END { print n + 0 }' "$rules"
}

critical=$(count_impact critical)
serious=$(count_impact serious)
moderate=$(count_impact moderate)
minor=$(count_impact minor)
unknown=$(count_impact unknown)
total=$(awk 'END { print NR + 0 }' "$rules")

parts=""
for pair in "critical $critical" "serious $serious" "moderate $moderate" "minor $minor" "unknown $unknown"; do
  name=${pair%% *}
  value=${pair##* }
  if [ "$value" -gt 0 ]; then
    if [ -n "$parts" ]; then parts="$parts, "; fi
    parts="$parts$value $name"
  fi
done
if [ -z "$parts" ]; then parts="none"; fi

# Evidence names the rules, worst first, so the fix has somewhere to start.
listing=$(awk -F '\t' '{ printf "%s %s (%d %s)\n", $2, $3, $4, ($4 == 1) ? "node" : "nodes" }' "$rules" || true)
if [ -n "$listing" ]; then
  printf '=== violations ===\n%s\n' "$listing" >> "$log"
fi
evidence=$(hp_evidence)

note=""
if [ "$route_default" -eq 1 ]; then
  note=" HYPERPOWER_ROUTE was unset, so the gate scanned the site root."
fi
if [ "$booted" -eq 0 ]; then
  note="$note commands.dev_url already answered, so the gate started no server."
fi

blocking_count=0
for impact_name in $BLOCKING_IMPACTS; do
  blocking_count=$((blocking_count + $(count_impact "$impact_name")))
done

noun=violations
if [ "$total" -eq 1 ]; then noun=violation; fi

if [ "$blocking_count" -gt 0 ]; then
  hp_fail "axe found $total $noun on $target: $parts. $blocking_count serious or critical.$note$(hp_advisory_note)" \
    "$evidence"
fi

if [ "$total" -eq 0 ]; then
  hp_pass "axe found no violations on $target.$note" "$evidence"
fi

hp_pass "axe found $total $noun on $target: $parts. None is serious or critical.$note" \
  "$evidence"
