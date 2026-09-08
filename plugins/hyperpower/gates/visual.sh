#!/bin/sh
# visual gate. Screenshots the changed route and diffs it against the locked mock the
# designer committed.
#
# The mock is the fidelity contract. agents/designer.md writes it to <docs>/mocks/<slug>.html,
# where <docs> is the first entry of paths.docs and defaults to docs/, and records the path in
# design.json with a `locked` flag. This gate reads design.json from the run journal first and
# falls back to the route slug. A mock nobody locked is a proposal, so it is never used as a
# baseline.
#
# Exit 78 when the gate is disabled, when no mock exists for the route, when the mock is not
# locked, when commands.dev_server or commands.dev_url is null, when no headless browser is
# installed, when neither curl nor wget is on PATH, or when no image diff tool is available.
# An unlocked route is not a failure. It is a route nobody has drawn yet.
#
# Two numbers are hardcoded, because the hyperpower.yml schema in docs/configuration.md has no
# field for either and this gate never reads a field that is not in the schema:
#   DIFF_TOLERANCE    per-channel difference a pixel may have and still count as equal
#   DIFF_MAX_PERCENT  share of differing pixels that fails the gate
# Change them here.
#
# A timeout is a fail, not a did-not-run. The budget covers booting the server and taking two
# screenshots, so a shot that never arrived inside it is a failure. hp-gates records its own
# timeouts the same way.
#
# The dev server and the browser are stopped on every exit path, including failure, timeout,
# INT and TERM.
set -eu

case ${1:-} in
  --help|-h)
    cat <<'EOF'
visual.sh - hyperpower visual diff gate

Config JSON arrives on stdin. One JSON result object goes to stdout.

  printf '%s' '{"commands":{"dev_server":"pnpm dev","dev_url":"http://localhost:5173"}}' \
    | HYPERPOWER_ROUTE=/settings HYPERPOWER_RUN_DIR=.hyperpower/runs/4f2a ./visual.sh

Reads commands.dev_server, commands.dev_url, paths.docs, gates.visual.enabled,
gates.visual.blocking, and limits.gate_timeout_seconds.

Fails when more than 1% of pixels differ by more than 8 per channel. Both numbers are
hardcoded because the config schema has no field for either.

Finding the mock, in order:
  1. mock.path in <HYPERPOWER_RUN_DIR>/design.json, which must have locked: true
  2. <docs>/mocks/<slug>.html, where <slug> comes from the route

Environment:
  HYPERPOWER_ROUTE        the route to shoot. Defaults to / and the result says so.
  HYPERPOWER_RUN_DIR      run journal folder. design.json is read from it, and the diff image
                          and both screenshots are written to its gates/ directory.
  HYPERPOWER_REPO_ROOT    directory the dev server runs in.
  HYPERPOWER_BROWSER_BIN  path to the headless browser. Defaults to the first of chromium,
                          chromium-browser, google-chrome, google-chrome-stable, chrome, or
                          a Chrome, Chromium, Edge or Brave app bundle on macOS.

Requires a Chromium-family browser, curl or wget, and one image comparator: python3, or
ImageMagick compare with identify. Exit 0 pass, 1 fail, 78 could not run.
EOF
    exit 0
    ;;
esac

HP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HP_DIR/_lib.sh"

hp_init visual

# A pixel differing by this much or less on every channel counts as equal. It absorbs
# antialiasing, not a changed colour.
DIFF_TOLERANCE=8
# More than this share of differing pixels fails the gate. One percent of a 1280x800 frame is
# a block about 100 pixels square, which is a moved control rather than a soft edge.
DIFF_MAX_PERCENT=1
# Both screenshots are taken at this size, so the diff compares the same viewport.
SHOT_WIDTH=1280
SHOT_HEIGHT=800

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
TAB=$(printf '\t')

# ---------------------------------------------------------------- process control

# Every pid descended from the given pids, breadth first, six generations deep.
descendants() {
  d_list=$1
  d_all=""
  d_depth=0
  while [ -n "$d_list" ] && [ "$d_depth" -lt 6 ]; do
    d_next=$(ps -Ao pid=,ppid= 2>/dev/null | awk -v list="$d_list" '
      BEGIN { n = split(list, a, " "); for (i = 1; i <= n; i++) want[a[i]] = 1 }
      $2 in want { print $1 }
    ' || true)
    if [ -z "$d_next" ]; then break; fi
    d_all="$d_all $d_next"
    d_list=$d_next
    d_depth=$((d_depth + 1))
  done
  printf '%s' "$d_all"
}

# stop_pid <pid> <in-own-group> — TERM, then KILL after five seconds. Never leaves a child.
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
  while [ "$sp_i" -lt 5 ]; do
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

# ---------------------------------------------------------------- budget

elapsed() {
  el_v=$(( $(hp_now) - GATE_STARTED ))
  if [ "$el_v" -lt 0 ]; then el_v=0; fi
  printf '%s' "$el_v"
}

remaining() {
  rm_v=$(( HP_TIMEOUT - $(elapsed) ))
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

# 0 the file is written and settled, 1 budget spent, 2 the browser exited without one.
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

# screenshot <url> <png> <budget> — 0 written, 1 budget spent, 2 the browser produced nothing.
screenshot() {
  sc_url=$1
  sc_png=$2
  sc_budget=$3
  rm -f "$sc_png"
  launch_group "$HP_TMPDIR/browser-stdout.log" "$HP_TMPDIR/browser-stderr.log" "$browser_bin" \
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
    --force-device-scale-factor=1 \
    --window-size="$SHOT_WIDTH,$SHOT_HEIGHT" \
    --user-data-dir="$HP_TMPDIR/browser-profile" \
    --virtual-time-budget=5000 \
    --screenshot="$sc_png" \
    "$sc_url"
  BROWSER_PID=$LAUNCH_PID
  BROWSER_GROUP=$LAUNCH_GROUP
  sc_status=0
  wait_artifact "$sc_png" "$sc_budget" || sc_status=$?
  stop_pid "$BROWSER_PID" "$BROWSER_GROUP"
  BROWSER_PID=""
  return "$sc_status"
}

slug_of() {
  printf '%s' "$1" | awk '
    {
      s = $0
      sub(/[?#].*$/, "", s)
      gsub(/^\/+/, "", s)
      gsub(/\/+$/, "", s)
      if (s == "") s = "index"
      s = tolower(s)
      gsub(/[^a-z0-9]+/, "-", s)
      gsub(/^-+/, "", s)
      gsub(/-+$/, "", s)
      if (s == "") s = "index"
      print s
    }'
}

# ---------------------------------------------------------------- config

if ! hp_enabled; then
  hp_did_not_run "gate disabled in hyperpower.yml" "gates.visual.enabled is false"
fi

route=${HYPERPOWER_ROUTE:-/}
route_default=0
if [ -z "${HYPERPOWER_ROUTE:-}" ]; then route_default=1; fi
slug=$(slug_of "$route")

docs_dir=$(hp_cfg_str paths.docs.0)
if [ -z "$docs_dir" ]; then docs_dir=docs/; fi
docs_dir=${docs_dir%/}

# The designer records the mock it built and whether a human locked it. That record is the
# fidelity contract for this run, so it is read before any guess from the route.
mock=""
mock_source=""
design=""
if [ -n "${HYPERPOWER_RUN_DIR:-}" ] && [ -f "$HYPERPOWER_RUN_DIR/design.json" ]; then
  design=$HYPERPOWER_RUN_DIR/design.json
  flat_design=$HP_TMPDIR/design.tsv
  awk "$HP_JSON_AWK" < "$design" > "$flat_design" 2>/dev/null || : > "$flat_design"
  design_field() {
    awk -F "$TAB" -v k="$1" '$1 == k { print substr($0, length(k) + 2); exit }' "$flat_design"
  }
  design_mock=$(design_field mock.path)
  design_locked=$(design_field locked)
  design_baseline=$(design_field verification.baseline_valid)
  if [ -n "$design_mock" ] && [ "$design_mock" != "null" ]; then
    if [ ! -f "$design_mock" ]; then
      hp_did_not_run "design.json names a mock that is not on disk: $design_mock" \
        "the designer wrote $design_mock and it is gone. Rerun the design stage, or set gates.visual.enabled to false."
    fi
    if [ "$design_locked" != "true" ]; then
      hp_did_not_run "the mock at $design_mock is not locked" \
        "design.json records locked: ${design_locked:-absent}. A mock nobody locked is a proposal, not a baseline. Lock it, then rerun the gate."
    fi
    if [ "$design_baseline" = "false" ]; then
      hp_did_not_run "design.json records verification.baseline_valid false for $design_mock" \
        "the designer built this mock without a human in the run. Lock it, then rerun the gate."
    fi
    mock=$design_mock
    mock_source="design.json"
  fi
fi

if [ -z "$mock" ]; then
  last_segment=$(printf '%s' "$route" | awk -F / '{ print $NF }')
  for candidate in \
    "$docs_dir/mocks/$slug.html" \
    "$docs_dir/mocks/$(printf '%s' "$slug" | tr '-' '_').html" \
    "$docs_dir/mocks/$(slug_of "$last_segment").html"; do
    if [ -f "$candidate" ]; then
      mock=$candidate
      mock_source="route slug"
      break
    fi
  done
fi

if [ -z "$mock" ]; then
  hp_did_not_run "no locked mock for route $route" \
    "the designer commits one to $docs_dir/mocks/$slug.html and records it in design.json. A route nobody has drawn is not a failure."
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
    "set both in hyperpower.yml, or set gates.visual.enabled to false. Both are null in the shipped schema."
fi

target=$(route_url "$dev_url" "$route")

if command -v curl >/dev/null 2>&1; then
  PROBE=curl
elif command -v wget >/dev/null 2>&1; then
  PROBE=wget
else
  hp_did_not_run "no HTTP probe on PATH" \
    "install curl or wget, or set gates.visual.enabled to false"
fi

browser_bin=$(find_browser || true)
if [ -z "$browser_bin" ]; then
  hp_did_not_run "no headless browser installed" \
    "install Google Chrome or Chromium, or point HYPERPOWER_BROWSER_BIN at one. The gate screenshots both the route and the mock with it."
fi

# python3 first: it is already a hyperpower dependency and it reports the same number on every
# machine, which a threshold needs. ImageMagick is the fallback for a machine without it.
differ=""
if [ -n "$PYTHON_BIN" ]; then
  differ=python3
elif command -v compare >/dev/null 2>&1 && command -v identify >/dev/null 2>&1; then
  differ=imagemagick
elif command -v magick >/dev/null 2>&1; then
  differ=magick
else
  hp_did_not_run "no image diff tool available" \
    "install python3, or install ImageMagick. Without one the screenshots cannot be compared, and an uncompared screenshot is not a pass."
fi

# ---------------------------------------------------------------- run

log=$HP_TMPDIR/visual-gate.log
live_png=$HP_TMPDIR/live.png
mock_png=$HP_TMPDIR/mock.png
diff_png=$HP_TMPDIR/diff.png
: > "$log"
printf '=== mock: %s (from %s) ===\n' "$mock" "$mock_source" >> "$log"

booted=0
preboot=$(probe_url "$dev_url")
case $preboot in
  ''|000)
    printf '=== boot: %s ===\n' "$dev_server" >> "$log"
    SERVER_LOG=$HP_TMPDIR/dev-server.log
    : > "$SERVER_LOG"
    launch_group "$SERVER_LOG" "$SERVER_LOG" sh -c "$dev_server"
    SERVER_PID=$LAUNCH_PID
    SERVER_GROUP=$LAUNCH_GROUP
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
    hp_fail "visual gate ran out of its ${HP_TIMEOUT}s budget before the dev server answered.$(hp_advisory_note)" \
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
    hp_fail "$dev_url did not answer within ${HP_TIMEOUT}s.$(hp_advisory_note)" "$(hp_evidence)"
  fi
fi

mock_abs=$mock
case $mock_abs in
  /*) ;;
  *) mock_abs=$PWD/$mock_abs ;;
esac

shot_failed=""
for pair in "route${TAB}$target${TAB}$live_png" "mock${TAB}file://$mock_abs${TAB}$mock_png"; do
  what=${pair%%"$TAB"*}
  rest=${pair#*"$TAB"}
  url=${rest%%"$TAB"*}
  png=${rest#*"$TAB"}
  budget=$(remaining)
  if [ "$budget" -le 0 ]; then
    shot_failed="the ${HP_TIMEOUT}s budget ran out before the $what screenshot"
    break
  fi
  shot=0
  screenshot "$url" "$png" "$budget" || shot=$?
  printf '=== %s screenshot: %s ===\n' "$what" "$url" >> "$log"
  if [ "$shot" -eq 1 ]; then
    shot_failed="the $what screenshot of $url did not arrive within ${HP_TIMEOUT}s"
    break
  fi
  if [ "$shot" -eq 2 ]; then
    tail -n 10 "$HP_TMPDIR/browser-stderr.log" >> "$log" 2>/dev/null || true
    HP_OUT=$log
    hp_did_not_run "the headless browser produced no $what screenshot of $url" "$(hp_evidence)"
  fi
done

if [ -n "$shot_failed" ]; then
  HP_OUT=$log
  hp_fail "$shot_failed.$(hp_advisory_note)" "$(hp_evidence)"
fi

# Compare. Every comparator prints one line: "differing total width height", or "ERROR <why>".
compare_out=""
case $differ in
  python3)
    cat > "$HP_TMPDIR/pngdiff.py" <<'PYEOF'
"""Compare two PNGs and write a diff image. Standard library only.

Prints "<differing> <total> <width> <height>", or "ERROR <reason>". Pixels outside the
overlap of two differently sized images count as differing: a layout that moved is what this
gate is looking for.
"""
import struct
import sys
import zlib

CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


def unfilter(data, width, height, channels):
    """Undo the per-scanline filters. Returns one bytearray per row."""
    stride = width * channels
    rows = []
    previous = bytearray(stride)
    at = 0
    for _ in range(height):
        kind = data[at]
        at += 1
        line = bytearray(data[at:at + stride])
        at += stride
        if kind == 0:
            pass
        elif kind == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif kind == 3:
            for i in range(channels):
                line[i] = (line[i] + (previous[i] >> 1)) & 0xFF
            for i in range(channels, stride):
                line[i] = (line[i] + ((line[i - channels] + previous[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(channels):
                line[i] = (line[i] + previous[i]) & 0xFF
            for i in range(channels, stride):
                left = line[i - channels]
                up = previous[i]
                upleft = previous[i - channels]
                estimate = left + up - upleft
                da = abs(estimate - left)
                db = abs(estimate - up)
                dc = abs(estimate - upleft)
                if da <= db and da <= dc:
                    pick = left
                elif db <= dc:
                    pick = up
                else:
                    pick = upleft
                line[i] = (line[i] + pick) & 0xFF
        else:
            raise ValueError("filter type %d" % kind)
        rows.append(line)
        previous = line
    return rows


def to_rgb(row, width, colour, channels, table):
    """One row as width*3 bytes of RGB, whatever colour type it arrived in."""
    if colour == 2:
        return row
    out = bytearray(width * 3)
    if colour == 0:
        out[0::3] = row
        out[1::3] = row
        out[2::3] = row
    elif colour == 4:
        grey = row[0::2]
        out[0::3] = grey
        out[1::3] = grey
        out[2::3] = grey
    elif colour == 6:
        out[0::3] = row[0::4]
        out[1::3] = row[1::4]
        out[2::3] = row[2::4]
    else:
        for x in range(width):
            at = row[x] * 3
            if at + 2 < len(table):
                out[x * 3] = table[at]
                out[x * 3 + 1] = table[at + 1]
                out[x * 3 + 2] = table[at + 2]
    return out


def read_png(where):
    raw = open(where, "rb").read()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % where)
    at = 8
    header = None
    body = []
    table = b""
    while at + 8 <= len(raw):
        size = struct.unpack(">I", raw[at:at + 4])[0]
        kind = raw[at + 4:at + 8]
        chunk = raw[at + 8:at + 8 + size]
        at += 12 + size
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", chunk)
        elif kind == b"PLTE":
            table = chunk
        elif kind == b"IDAT":
            body.append(chunk)
        elif kind == b"IEND":
            break
    if header is None:
        raise ValueError("%s has no IHDR" % where)
    width, height, depth, colour, compression, filtering, interlace = header
    if depth != 8:
        raise ValueError("%s is %d-bit and this comparator reads 8-bit PNGs" % (where, depth))
    if interlace != 0:
        raise ValueError("%s is interlaced" % where)
    if compression != 0 or filtering != 0:
        raise ValueError("%s uses an unknown compression or filter method" % where)
    channels = CHANNELS.get(colour)
    if channels is None:
        raise ValueError("%s uses colour type %d" % (where, colour))
    rows = unfilter(zlib.decompress(b"".join(body)), width, height, channels)
    return width, height, [to_rgb(r, width, colour, channels, table) for r in rows]


def write_png(where, width, height, rows):
    body = bytearray()
    for row in rows:
        body.append(0)
        body.extend(row)
    out = bytearray(b"\x89PNG\r\n\x1a\n")

    def chunk(kind, payload):
        out.extend(struct.pack(">I", len(payload)))
        out.extend(kind)
        out.extend(payload)
        out.extend(struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    chunk(b"IDAT", zlib.compress(bytes(body), 6))
    chunk(b"IEND", b"")
    open(where, "wb").write(bytes(out))


def faded(row, width):
    """The row, greyed and lightened, so the red diff pixels are the only thing that reads."""
    out = bytearray(width * 3)
    for x in range(0, width * 3, 3):
        grey = 255 - ((255 - ((row[x] * 30 + row[x + 1] * 59 + row[x + 2] * 11) // 100)) >> 2)
        out[x] = out[x + 1] = out[x + 2] = grey
    return out


def main():
    left, right, diff_path, tolerance = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    lw, lh, lrows = read_png(left)
    rw, rh, rrows = read_png(right)
    width = max(lw, rw)
    height = max(lh, rh)
    red = bytearray(b"\xff\x28\x28" * width)
    white = bytearray(b"\xff\xff\xff" * width)
    differing = 0
    out_rows = []
    for y in range(height):
        lrow = lrows[y] if y < lh else None
        rrow = rrows[y] if y < rh else None
        if lrow is None or rrow is None:
            differing += width
            out_rows.append(bytearray(red))
            continue
        if lw == rw and lrow == rrow:
            out_rows.append(faded(lrow, width))
            continue
        row = faded(lrow, lw) if lw == width else faded(lrow, lw) + white[lw * 3:width * 3]
        limit = min(lw, rw) * 3
        for x in range(0, limit, 3):
            if (abs(lrow[x] - rrow[x]) <= tolerance
                    and abs(lrow[x + 1] - rrow[x + 1]) <= tolerance
                    and abs(lrow[x + 2] - rrow[x + 2]) <= tolerance):
                continue
            differing += 1
            row[x] = 255
            row[x + 1] = 40
            row[x + 2] = 40
        for x in range(min(lw, rw), width):
            differing += 1
            row[x * 3] = 255
            row[x * 3 + 1] = 40
            row[x * 3 + 2] = 40
        out_rows.append(row)
    write_png(diff_path, width, height, out_rows)
    sys.stdout.write("%d %d %d %d\n" % (differing, width * height, width, height))


try:
    main()
except Exception as error:  # a comparator that raised is a comparison that did not happen
    sys.stdout.write("ERROR %s\n" % error)
PYEOF
    compare_out=$("$PYTHON_BIN" "$HP_TMPDIR/pngdiff.py" "$live_png" "$mock_png" "$diff_png" "$DIFF_TOLERANCE" 2>>"$log" || printf 'ERROR the comparator did not finish\n')
    ;;
  imagemagick|magick)
    if [ "$differ" = magick ]; then
      im_identify="magick identify"
      im_compare="magick compare"
    else
      im_identify=identify
      im_compare=compare
    fi
    live_size=$($im_identify -format '%w %h' "$live_png" 2>>"$log" || printf '')
    mock_size=$($im_identify -format '%w %h' "$mock_png" 2>>"$log" || printf '')
    if [ -z "$live_size" ] || [ -z "$mock_size" ]; then
      compare_out="ERROR $im_identify could not read the screenshots"
    elif [ "$live_size" != "$mock_size" ]; then
      # ImageMagick refuses to compare two different sizes, and a moved layout is exactly
      # what this gate looks for, so the whole frame counts as differing.
      im_total=$(printf '%s' "$live_size" | awk '{ print $1 * $2 }')
      cp "$live_png" "$diff_png" 2>/dev/null || true
      compare_out="$im_total $im_total $(printf '%s' "$live_size" | awk '{ print $1, $2 }')"
    else
      im_raw=$($im_compare -metric AE "$live_png" "$mock_png" "$diff_png" 2>&1 || true)
      im_count=$(printf '%s' "$im_raw" | tr -d ' ' | awk -F '[(]' '{ print $1 }')
      case $im_count in
        ''|*[!0-9]*) compare_out="ERROR $im_compare printed \"$(printf '%s' "$im_raw" | tr '\n' ' ')\"" ;;
        *) compare_out="$im_count $(printf '%s' "$live_size" | awk '{ print $1 * $2, $1, $2 }')" ;;
      esac
    fi
    ;;
esac

printf '=== comparator: %s -> %s ===\n' "$differ" "$compare_out" >> "$log"

case $compare_out in
  ERROR*)
    HP_OUT=$log
    hp_did_not_run "the screenshots could not be compared: ${compare_out#ERROR }" "$(hp_evidence)"
    ;;
esac

differing=$(printf '%s' "$compare_out" | awk '{ print $1 + 0 }')
total=$(printf '%s' "$compare_out" | awk '{ print $2 + 0 }')
dimensions=$(printf '%s' "$compare_out" | awk '{ print $3 "x" $4 }')
if [ "$total" -le 0 ]; then
  HP_OUT=$log
  hp_did_not_run "the comparator reported a zero-pixel image" "$(hp_evidence)"
fi

percent=$(awk -v d="$differing" -v t="$total" 'BEGIN { printf "%.2f", (d * 100) / t }')
over=$(awk -v d="$differing" -v t="$total" -v m="$DIFF_MAX_PERCENT" \
  'BEGIN { print ((d * 100) > (t * m)) ? 1 : 0 }')

# The diff image outlives this gate, so a human and the run journal can both open it.
if [ -n "${HYPERPOWER_RUN_DIR:-}" ] && mkdir -p "$HYPERPOWER_RUN_DIR/gates" 2>/dev/null; then
  diff_out=$HYPERPOWER_RUN_DIR/gates/visual-diff-$slug.png
  live_out=$HYPERPOWER_RUN_DIR/gates/visual-live-$slug.png
  mock_out=$HYPERPOWER_RUN_DIR/gates/visual-mock-$slug.png
else
  diff_out=${TMPDIR:-/tmp}/hyperpower-visual-diff-$slug.png
  live_out=${TMPDIR:-/tmp}/hyperpower-visual-live-$slug.png
  mock_out=${TMPDIR:-/tmp}/hyperpower-visual-mock-$slug.png
fi
cp "$diff_png" "$diff_out" 2>/dev/null || diff_out="not written"
cp "$live_png" "$live_out" 2>/dev/null || live_out="not written"
cp "$mock_png" "$mock_out" 2>/dev/null || mock_out="not written"

printf '=== diff image: %s ===\n=== route screenshot: %s ===\n=== mock screenshot: %s ===\n' \
  "$diff_out" "$live_out" "$mock_out" >> "$log"
HP_OUT=$log
evidence="diff: $diff_out
route: $live_out
mock: $mock_out
$(hp_evidence)"

note=""
if [ "$route_default" -eq 1 ]; then
  note=" HYPERPOWER_ROUTE was unset, so the gate shot the site root."
fi
if [ "$booted" -eq 0 ]; then
  note="$note commands.dev_url already answered, so the gate started no server."
fi

if [ "$over" -eq 1 ]; then
  hp_fail "$target differs from $mock by $percent% of $dimensions pixels, over the $DIFF_MAX_PERCENT% limit.$note$(hp_advisory_note)" \
    "$evidence"
fi

hp_pass "$target matches $mock within $DIFF_MAX_PERCENT%: $percent% of $dimensions pixels differ.$note" \
  "$evidence"
