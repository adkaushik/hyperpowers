#!/bin/sh
# browser gate. Boots commands.dev_server, waits for commands.dev_url to answer, loads the
# changed route in a headless browser, and asserts that the page rendered.
#
# Exit 78 when the gate is disabled, when commands.dev_server or commands.dev_url is null,
# when neither curl nor wget is on PATH, or when no headless browser is installed. Both
# commands are null in the shipped schema, so this gate stays inert until someone sets them.
# It never falls back to a curl request and calls that a render: a page that answers 200 and
# paints nothing is the failure this gate exists to catch.
#
# A timeout is a fail, not a did-not-run. The budget covers booting the server and painting
# one page, so a page that never appeared inside it is a rendering failure. hp-gates records
# its own timeouts the same way.
#
# The dev server and the browser are stopped on every exit path, including failure, timeout,
# INT and TERM. When commands.dev_url already answers, the gate uses that server and starts
# none, so a second copy never fights for the port.
set -eu

case ${1:-} in
  --help|-h)
    cat <<'EOF'
browser.sh - hyperpower browser gate

Config JSON arrives on stdin. One JSON result object goes to stdout.

  printf '%s' '{"commands":{"dev_server":"pnpm dev","dev_url":"http://localhost:5173"}}' \
    | HYPERPOWER_ROUTE=/settings ./browser.sh

Reads commands.dev_server, commands.dev_url, gates.browser.enabled,
gates.browser.blocking, and limits.gate_timeout_seconds.

Environment:
  HYPERPOWER_ROUTE        the route to load. Defaults to / and the result says so.
  HYPERPOWER_RUN_DIR      run journal folder. The full log is copied to gates/browser.log.
  HYPERPOWER_REPO_ROOT    directory the dev server runs in.
  HYPERPOWER_BROWSER_BIN  path to the headless browser. Defaults to the first of chromium,
                          chromium-browser, google-chrome, google-chrome-stable, chrome, or
                          a Chrome, Chromium, Edge or Brave app bundle on macOS.

Requires curl or wget for the readiness probe, and a Chromium-family browser for the render.
Exit 0 pass, 1 fail, 78 could not run.
EOF
    exit 0
    ;;
esac

HP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HP_DIR/_lib.sh"

hp_init browser

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

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1; then PYTHON_BIN=python3; fi

LAUNCH_PID=""
LAUNCH_GROUP=0
SERVER_PID=""
SERVER_GROUP=0
SERVER_LOG=""
BROWSER_PID=""
BROWSER_GROUP=0
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
  if [ -n "$BROWSER_PID" ]; then
    stop_pid "$BROWSER_PID" "$BROWSER_GROUP"
    BROWSER_PID=""
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
  for fb_name in chromium chromium-browser google-chrome google-chrome-stable chrome headless_shell; do
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
  pu_follow=${2:-no}
  if [ "$PROBE" = curl ]; then
    if [ "$pu_follow" = follow ]; then
      curl -s -L -o /dev/null -m 10 -w '%{http_code}' "$pu_url" 2>/dev/null || printf ''
    else
      curl -s -o /dev/null -m 10 -w '%{http_code}' "$pu_url" 2>/dev/null || printf ''
    fi
  else
    if [ "$pu_follow" = follow ]; then
      wget -q -S -O /dev/null -T 10 --tries=1 "$pu_url" 2>&1 | awk '/^ *HTTP\// { code = $2 } END { print code }'
    else
      wget -q -S -O /dev/null -T 10 --tries=1 --max-redirect=0 "$pu_url" 2>&1 | awk '/^ *HTTP\// { code = $2 } END { print code }'
    fi
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

# 0 the artifact is written, 1 budget spent, 2 the browser exited without one.
# Chrome on macOS writes its artifact and then stays alive, so a settled file ends the wait.
wait_artifact() {
  wa_file=$1
  wa_budget=$2
  wa_last=-1
  wa_waited=0
  while [ "$wa_waited" -lt "$wa_budget" ]; do
    if [ -f "$wa_file" ]; then
      wa_size=$(wc -c < "$wa_file" 2>/dev/null | tr -d ' ')
      case $wa_size in
        ''|*[!0-9]*) wa_size=0 ;;
      esac
      if [ "$wa_size" -gt 0 ] && [ "$wa_size" -eq "$wa_last" ]; then return 0; fi
      wa_last=$wa_size
    fi
    if ! proc_running "$BROWSER_PID"; then
      if [ -s "$wa_file" ]; then return 0; fi
      return 2
    fi
    sleep 1
    wa_waited=$((wa_waited + 1))
  done
  return 1
}

# ---------------------------------------------------------------- config

if ! hp_enabled; then
  hp_did_not_run "gate disabled in hyperpower.yml" "gates.browser.enabled is false"
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
    "set both in hyperpower.yml, or set gates.browser.enabled to false. Both are null in the shipped schema."
fi

route=${HYPERPOWER_ROUTE:-/}
route_default=0
if [ -z "${HYPERPOWER_ROUTE:-}" ]; then route_default=1; fi
target=$(route_url "$dev_url" "$route")

if command -v curl >/dev/null 2>&1; then
  PROBE=curl
elif command -v wget >/dev/null 2>&1; then
  PROBE=wget
else
  hp_did_not_run "no HTTP probe on PATH" \
    "install curl or wget, or set gates.browser.enabled to false"
fi

browser_bin=$(find_browser || true)
if [ -z "$browser_bin" ]; then
  hp_did_not_run "no headless browser installed" \
    "install Google Chrome or Chromium, or point HYPERPOWER_BROWSER_BIN at one. This gate never downgrades to a $PROBE request and calls that a render."
fi

# ---------------------------------------------------------------- run

log=$HP_TMPDIR/browser-gate.log
dom=$HP_TMPDIR/dom.html
browser_err=$HP_TMPDIR/browser-stderr.log
: > "$log"

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
    hp_fail "browser gate ran out of its ${WORK_TIMEOUT}s working budget before the dev server answered.$(hp_advisory_note)" \
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

status=$(probe_url "$target" follow)
printf '=== GET %s -> %s ===\n' "$target" "${status:-no answer}" >> "$log"

profile=$HP_TMPDIR/browser-profile
mkdir -p "$profile"
budget=$(remaining)
if [ "$budget" -le 0 ]; then
  HP_OUT=$log
  hp_fail "browser gate ran out of its ${WORK_TIMEOUT}s working budget before loading $target.$(hp_advisory_note)" \
    "$(hp_evidence)"
fi

launch_group "$dom" "$browser_err" "$browser_bin" \
  --headless \
  --disable-gpu \
  --no-sandbox \
  --no-first-run \
  --no-default-browser-check \
  --disable-extensions \
  --disable-background-networking \
  --disable-sync \
  --disable-component-update \
  --disable-dev-shm-usage \
  --hide-scrollbars \
  --window-size=1280,800 \
  --user-data-dir="$profile" \
  --virtual-time-budget=5000 \
  --dump-dom "$target"
BROWSER_PID=$LAUNCH_PID
BROWSER_GROUP=$LAUNCH_GROUP

loaded=0
wait_artifact "$dom" "$budget" || loaded=$?
stop_pid "$BROWSER_PID" "$BROWSER_GROUP"
BROWSER_PID=""

printf '=== headless browser: %s ===\n' "$browser_bin" >> "$log"
if [ -s "$dom" ]; then
  printf '=== dom head ===\n' >> "$log"
  head -c 4000 "$dom" >> "$log"
  printf '\n' >> "$log"
else
  printf '=== browser stderr ===\n' >> "$log"
  tail -n 10 "$browser_err" >> "$log" 2>/dev/null || true
fi
HP_OUT=$log

if [ "$loaded" -eq 1 ]; then
  hp_fail "$target did not render within ${WORK_TIMEOUT}s of the ${HP_TIMEOUT}s budget.$(hp_advisory_note)" "$(hp_evidence)"
fi
if [ "$loaded" -eq 2 ]; then
  hp_did_not_run "the headless browser exited without producing a DOM" \
    "$(hp_evidence)"
fi

case $status in
  ''|000)
    hp_fail "$target did not answer an HTTP request.$(hp_advisory_note)" "$(hp_evidence)"
    ;;
  [45]*)
    hp_fail "$target answered HTTP $status.$(hp_advisory_note)" "$(hp_evidence)"
    ;;
esac

if ! grep -q -i '<body' "$dom"; then
  hp_fail "$target produced a DOM with no body element.$(hp_advisory_note)" "$(hp_evidence)"
fi

# Dev servers report a broken build as an overlay inside a page that still answers 200.
overlay=$(grep -o -i -F \
  -e 'vite-error-overlay' \
  -e 'webpack-dev-server-client-overlay' \
  -e 'Unhandled Runtime Error' \
  -e 'Application error: a client-side exception has occurred' \
  -e 'Internal Server Error' \
  -e 'Cannot GET ' \
  "$dom" 2>/dev/null | sort -u | tr '\n' ' ' || true)
overlay=${overlay% }
if [ -n "$overlay" ]; then
  hp_fail "$target rendered an error: $overlay.$(hp_advisory_note)" "$(hp_evidence)"
fi

# Visible text and rendered elements, with script and style content removed. An SPA whose
# bundle threw answers 200 and paints an empty root, and this is what sees that.
painted=$(tr '<' '\n' < "$dom" | awk '
  NR == 1 { next }
  {
    gt = index($0, ">")
    name = (gt > 1) ? substr($0, 1, gt - 1) : $0
    rest = (gt > 0) ? substr($0, gt + 1) : ""
    lower = tolower(name)
    if (lower ~ /^body([ >\/]|$)/) body = 1
    else if (lower ~ /^\/body/) body = 0
    if (lower ~ /^script/ || lower ~ /^style/) skip = 1
    else if (lower ~ /^\/script/ || lower ~ /^\/style/) skip = 0
    else if (body && !skip) {
      text = text rest
      if (lower ~ /^(img|svg|input|canvas|video|button|select|textarea)([ >\/]|$)/) elements++
    }
  }
  END {
    gsub(/[ \t\r\n]+/, "", text)
    printf "%d %d", length(text), elements + 0
  }
' || true)
case $painted in
  [0-9]*' '[0-9]*) ;;
  *) painted="0 0" ;;
esac
text_len=${painted%% *}
element_count=${painted##* }

if [ "$text_len" -eq 0 ] && [ "$element_count" -eq 0 ]; then
  hp_fail "$target answered HTTP $status and rendered an empty body.$(hp_advisory_note)" \
    "$(hp_evidence)"
fi

note=""
if [ "$route_default" -eq 1 ]; then
  note=" HYPERPOWER_ROUTE was unset, so the gate loaded the site root."
fi
if [ "$booted" -eq 0 ]; then
  note="$note commands.dev_url already answered, so the gate started no server."
fi

noun=elements
if [ "$element_count" -eq 1 ]; then noun=element; fi

hp_pass "$target rendered in $(elapsed)s: HTTP $status, $text_len characters of body text, $element_count rendered $noun.$note" \
  "$(hp_evidence)"
