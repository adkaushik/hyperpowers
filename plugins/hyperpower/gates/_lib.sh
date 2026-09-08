#!/bin/sh
# Shared runtime for hyperpower gates. Source this file. Do not execute it.
# Contract: config JSON on stdin, one JSON result on stdout, exit 0 pass / 1 fail / 78 could not run.

HP_PASS=0
HP_FAIL=1
HP_DID_NOT_RUN=78

HP_GATE=""
HP_TMPDIR=""
HP_FLAT=""
HP_OUT=""
HP_TIMEOUT=600
HP_TIMEOUT_BIN=""
HP_TIMED_OUT=0
HP_DURATION=0
HP_FILES_READY=0
HP_IGNORES=""
HP_IGNORES_READY=0

# Flattens JSON on stdin to "dotted.path<TAB>value" lines. Used when jq is absent.
HP_JSON_AWK='
{ hp_buf = hp_buf $0 "\n" }
END {
  s = hp_buf
  len = length(s)
  pos = 1
  parse_value("")
}
function skipws(   c) {
  while (pos <= len) {
    c = substr(s, pos, 1)
    if (c == " " || c == "\t" || c == "\n" || c == "\r") pos++
    else return
  }
}
function emit(path, val) {
  if (path == "") return
  gsub(/\n/, " ", val)
  gsub(/\t/, " ", val)
  printf "%s\t%s\n", path, val
}
function parse_value(path,   c) {
  skipws()
  if (pos > len) return
  c = substr(s, pos, 1)
  if (c == "{") parse_object(path)
  else if (c == "[") parse_array(path)
  else if (c == "\"") emit(path, parse_string())
  else emit(path, parse_literal())
}
function parse_object(path,   c, key, child) {
  pos++
  skipws()
  if (substr(s, pos, 1) == "}") { pos++; return }
  while (pos <= len) {
    skipws()
    if (substr(s, pos, 1) != "\"") return
    key = parse_string()
    skipws()
    if (substr(s, pos, 1) != ":") return
    pos++
    child = (path == "") ? key : path "." key
    parse_value(child)
    skipws()
    c = substr(s, pos, 1)
    pos++
    if (c != ",") return
  }
}
function parse_array(path,   c, i, child) {
  pos++
  skipws()
  if (substr(s, pos, 1) == "]") { pos++; return }
  i = 0
  while (pos <= len) {
    child = (path == "") ? "" i : path "." i
    parse_value(child)
    i++
    skipws()
    c = substr(s, pos, 1)
    pos++
    if (c != ",") return
  }
}
function parse_string(   out, c, e, n) {
  pos++
  out = ""
  while (pos <= len) {
    c = substr(s, pos, 1)
    if (c == "\\") {
      pos++
      e = substr(s, pos, 1)
      if (e == "n") out = out "\n"
      else if (e == "t") out = out "\t"
      else if (e == "r") out = out "\r"
      else if (e == "b" || e == "f") out = out " "
      else if (e == "u") {
        n = hexval(substr(s, pos + 1, 4))
        pos = pos + 4
        if (n > 31 && n < 127) out = out sprintf("%c", n)
        else out = out "?"
      }
      else out = out e
      pos++
    } else if (c == "\"") {
      pos++
      return out
    } else {
      out = out c
      pos++
    }
  }
  return out
}
function hexval(h,   i, c, v, d) {
  v = 0
  for (i = 1; i <= length(h); i++) {
    c = tolower(substr(h, i, 1))
    d = index("0123456789abcdef", c) - 1
    if (d < 0) return -1
    v = v * 16 + d
  }
  return v
}
function parse_literal(   out, c) {
  out = ""
  while (pos <= len) {
    c = substr(s, pos, 1)
    if (c == "," || c == "}" || c == "]" || c == " " || c == "\t" || c == "\n" || c == "\r") break
    out = out c
    pos++
  }
  return out
}
'

# Escapes stdin into a JSON string body on stdout.
HP_ESCAPE_AWK='
function esc(str,   i, c, out) {
  out = ""
  for (i = 1; i <= length(str); i++) {
    c = substr(str, i, 1)
    if (c == "\\") out = out "\\\\"
    else if (c == "\"") out = out "\\\""
    else if (c == "\t") out = out "\\t"
    else if (c ~ /[[:cntrl:]]/) out = out " "
    else out = out c
  }
  return out
}
{ if (NR > 1) acc = acc "\\n"; acc = acc esc($0) }
END { printf "%s", acc }
'

hp_cleanup() {
  hp_cl_status=$?
  if [ -n "$HP_TMPDIR" ]; then
    rm -rf "$HP_TMPDIR" >/dev/null 2>&1 || true
  fi
  return $hp_cl_status
}

hp_tmpdir() {
  if [ -n "$HP_TMPDIR" ]; then return 0; fi
  HP_TMPDIR=$(mktemp -d 2>/dev/null) || HP_TMPDIR=""
  if [ -z "$HP_TMPDIR" ]; then
    HP_TMPDIR=${TMPDIR:-/tmp}/hyperpower-gate-$$
    mkdir -p "$HP_TMPDIR"
  fi
  trap hp_cleanup EXIT
  return 0
}

hp_now() {
  hp_nw=$(date +%s 2>/dev/null) || hp_nw=0
  case $hp_nw in
    ''|*[!0-9]*) hp_nw=0 ;;
  esac
  printf '%s' "$hp_nw"
}

# ---------------------------------------------------------------- config

hp_load_config() {
  hp_lc_raw=$HP_TMPDIR/config.json
  : > "$hp_lc_raw"
  if [ ! -t 0 ]; then
    cat > "$hp_lc_raw" 2>/dev/null || : > "$hp_lc_raw"
  fi
  : > "$HP_FLAT"
  if [ ! -s "$hp_lc_raw" ]; then return 0; fi
  if command -v jq >/dev/null 2>&1; then
    if jq -r 'paths(scalars) as $p | (($p|map(tostring))|join(".")) + "\t" + ((getpath($p)|tostring)|gsub("[\n\t]"; " "))' \
        < "$hp_lc_raw" > "$HP_FLAT" 2>/dev/null; then
      if [ -s "$HP_FLAT" ]; then return 0; fi
    fi
  fi
  if ! awk "$HP_JSON_AWK" < "$hp_lc_raw" > "$HP_FLAT" 2>/dev/null; then
    : > "$HP_FLAT"
  fi
  return 0
}

# hp_cfg <dotted.path> — prints the raw scalar, empty when absent.
hp_cfg() {
  if [ ! -s "$HP_FLAT" ]; then return 0; fi
  awk -F '\t' -v k="$1" '$1 == k { print substr($0, length(k) + 2); exit }' "$HP_FLAT"
}

# hp_cfg_str <dotted.path> — same, but JSON null becomes empty.
hp_cfg_str() {
  hp_cs_v=$(hp_cfg "$1")
  if [ "$hp_cs_v" = "null" ]; then hp_cs_v=""; fi
  printf '%s' "$hp_cs_v"
}

hp_set_timeout() {
  hp_st_t=$(hp_cfg limits.gate_timeout_seconds)
  case $hp_st_t in
    ''|*[!0-9]*) hp_st_t=600 ;;
  esac
  if [ "$hp_st_t" -le 0 ]; then hp_st_t=600; fi
  HP_TIMEOUT=$hp_st_t
  HP_TIMEOUT_BIN=""
  if command -v timeout >/dev/null 2>&1; then
    HP_TIMEOUT_BIN=timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    HP_TIMEOUT_BIN=gtimeout
  fi
  return 0
}

hp_cd_root() {
  hp_cr_root=${HYPERPOWER_REPO_ROOT:-}
  if [ -z "$hp_cr_root" ]; then
    hp_cr_root=$(git rev-parse --show-toplevel 2>/dev/null) || hp_cr_root=""
  fi
  if [ -n "$hp_cr_root" ] && [ -d "$hp_cr_root" ]; then
    CDPATH= cd -- "$hp_cr_root" || return 0
  fi
  return 0
}

# hp_init <gate-name> — reads stdin config, sets the timeout, moves to the repo root.
hp_init() {
  HP_GATE=$1
  hp_tmpdir
  HP_FLAT=$HP_TMPDIR/config.tsv
  HP_OUT=$HP_TMPDIR/output.log
  : > "$HP_OUT"
  hp_load_config
  hp_set_timeout
  hp_cd_root
  return 0
}

hp_enabled() {
  if [ "$(hp_cfg "gates.$HP_GATE.enabled")" = "false" ]; then return 1; fi
  return 0
}

hp_blocking() {
  if [ "$(hp_cfg "gates.$HP_GATE.blocking")" = "false" ]; then return 1; fi
  return 0
}

# A non-blocking gate still reports fail. The caller decides whether to stop.
hp_advisory_note() {
  if hp_blocking; then
    printf ''
  else
    printf ' Advisory: gates.%s.blocking is false.' "$HP_GATE"
  fi
}

# ---------------------------------------------------------------- files

hp_raw_files() {
  if [ -n "${HYPERPOWER_FILES_FILE:-}" ] && [ -f "${HYPERPOWER_FILES_FILE}" ]; then
    cat "$HYPERPOWER_FILES_FILE"
  elif [ -n "${HYPERPOWER_FILES:-}" ]; then
    printf '%s\n' "$HYPERPOWER_FILES" | tr ' \t' '\n\n'
  else
    hp_git_files
  fi
}

hp_git_files() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then return 0; fi
  git diff --name-only HEAD -- 2>/dev/null || true
  git ls-files --others --exclude-standard 2>/dev/null || true
}

hp_load_ignores() {
  if [ "$HP_IGNORES_READY" -eq 1 ]; then return 0; fi
  HP_IGNORES=""
  hp_li_i=0
  while [ "$hp_li_i" -lt 200 ]; do
    hp_li_pat=$(hp_cfg "paths.ignore.$hp_li_i")
    if [ -z "$hp_li_pat" ]; then break; fi
    hp_li_pat=${hp_li_pat%/}
    hp_li_pat=${hp_li_pat%/\*}
    HP_IGNORES="$HP_IGNORES$hp_li_pat
"
    hp_li_i=$((hp_li_i + 1))
  done
  HP_IGNORES_READY=1
  return 0
}

hp_ignored() {
  hp_ig_f=$1
  hp_load_ignores
  if [ -z "$HP_IGNORES" ]; then return 1; fi
  hp_ig_ifs=$IFS
  IFS='
'
  set -f
  set -- $HP_IGNORES
  set +f
  IFS=$hp_ig_ifs
  for hp_ig_pat do
    case $hp_ig_f in
      $hp_ig_pat|$hp_ig_pat/*) return 0 ;;
    esac
  done
  return 1
}

# Files this run may check: deduplicated, present on disk, not under paths.ignore.
# Deleted files are dropped. paths.source is not applied, so test files outside it survive.
hp_scope_files() {
  if [ "$HP_FILES_READY" -eq 1 ]; then
    cat "$HP_TMPDIR/files.txt"
    return 0
  fi
  hp_raw_files | awk 'NF' | sort -u > "$HP_TMPDIR/files.raw"
  : > "$HP_TMPDIR/files.txt"
  while IFS= read -r hp_sf_f; do
    if [ -z "$hp_sf_f" ]; then continue; fi
    if [ ! -f "$hp_sf_f" ]; then continue; fi
    if hp_ignored "$hp_sf_f"; then continue; fi
    printf '%s\n' "$hp_sf_f" >> "$HP_TMPDIR/files.txt"
  done < "$HP_TMPDIR/files.raw"
  HP_FILES_READY=1
  cat "$HP_TMPDIR/files.txt"
  return 0
}

hp_file_count() {
  hp_scope_files | awk 'END { print NR + 0 }'
}

# Reads paths on stdin, prints them single-quoted and space-separated.
hp_quote_files() {
  sed "s/'/'\\\\''/g" | sed "s/^/ '/; s/\$/'/" | tr -d '\n'
}

hp_replace_token() {
  hp_rt_h=$1
  hp_rt_t=$2
  hp_rt_v=$3
  hp_rt_out=""
  while :; do
    case $hp_rt_h in
      *"$hp_rt_t"*) ;;
      *) break ;;
    esac
    hp_rt_out="$hp_rt_out${hp_rt_h%%"$hp_rt_t"*}$hp_rt_v"
    hp_rt_h=${hp_rt_h#*"$hp_rt_t"}
  done
  printf '%s' "$hp_rt_out$hp_rt_h"
}

# hp_expand <command> — substitutes {files} and {route}. No other variable is substituted.
hp_expand() {
  hp_ex_cmd=$1
  case $hp_ex_cmd in
    *"{files}"*)
      hp_ex_files=$(hp_scope_files | hp_quote_files)
      hp_ex_files=${hp_ex_files# }
      hp_ex_cmd=$(hp_replace_token "$hp_ex_cmd" "{files}" "$hp_ex_files")
      ;;
  esac
  case $hp_ex_cmd in
    *"{route}"*)
      hp_ex_cmd=$(hp_replace_token "$hp_ex_cmd" "{route}" "${HYPERPOWER_ROUTE:-}")
      ;;
  esac
  printf '%s' "$hp_ex_cmd"
}

# ---------------------------------------------------------------- execution

hp_tool_check() {
  hp_tc_first=${1%% *}
  case $hp_tc_first in
    ''|*=*|*'$'*|*'`'*|*'('*|*'"'*) return 0 ;;
  esac
  if command -v "$hp_tc_first" >/dev/null 2>&1; then return 0; fi
  return 1
}

# hp_exec <command> — runs it, captures output in $HP_OUT, returns its exit status.
# Call it as: hp_exec "$cmd" || status=$?
hp_exec() {
  hp_ex_run=$1
  HP_TIMED_OUT=0
  hp_ex_start=$(hp_now)
  hp_ex_status=0
  : > "$HP_OUT"
  if [ -n "$HP_TIMEOUT_BIN" ]; then
    "$HP_TIMEOUT_BIN" "$HP_TIMEOUT" sh -c "$hp_ex_run" </dev/null > "$HP_OUT" 2>&1 || hp_ex_status=$?
    if [ "$hp_ex_status" -eq 124 ]; then HP_TIMED_OUT=1; fi
  else
    hp_ex_marker=$HP_TMPDIR/timed_out
    rm -f "$hp_ex_marker"
    sh -c "$hp_ex_run" </dev/null > "$HP_OUT" 2>&1 &
    hp_ex_job=$!
    # The watchdog holds no inherited descriptor and polls, so it cannot keep a caller's
    # command substitution open after the job finishes.
    (
      hp_wd_left=$HP_TIMEOUT
      while [ "$hp_wd_left" -gt 0 ]; do
        sleep 1
        if ! kill -0 "$hp_ex_job" 2>/dev/null; then exit 0; fi
        hp_wd_left=$((hp_wd_left - 1))
      done
      : > "$hp_ex_marker"
      kill -TERM "$hp_ex_job" 2>/dev/null || true
    ) >/dev/null 2>&1 </dev/null &
    hp_ex_watch=$!
    wait "$hp_ex_job" 2>/dev/null || hp_ex_status=$?
    kill -TERM "$hp_ex_watch" >/dev/null 2>&1 || true
    wait "$hp_ex_watch" >/dev/null 2>&1 || true
    if [ -f "$hp_ex_marker" ]; then HP_TIMED_OUT=1; fi
  fi
  HP_DURATION=$(( $(hp_now) - hp_ex_start ))
  if [ "$HP_DURATION" -lt 0 ]; then HP_DURATION=0; fi
  return "$hp_ex_status"
}

# ---------------------------------------------------------------- output

hp_short() {
  hp_sh_s=$1
  hp_sh_n=$2
  if [ "${#hp_sh_s}" -le "$hp_sh_n" ]; then
    printf '%s' "$hp_sh_s"
    return 0
  fi
  printf '%s' "$hp_sh_s" | cut -c "1-$hp_sh_n" | tr -d '\n'
  printf '...'
}

hp_tail() {
  if [ ! -s "$HP_OUT" ]; then
    printf 'no output'
    return 0
  fi
  tail -n 20 "$HP_OUT" | cut -c 1-200
}

# Copies the captured output into the run journal and prints its path, when a run dir is set.
hp_save_log() {
  hp_sl_dir=${HYPERPOWER_RUN_DIR:-}
  if [ -z "$hp_sl_dir" ]; then return 0; fi
  if ! mkdir -p "$hp_sl_dir/gates" 2>/dev/null; then return 0; fi
  if ! cp "$HP_OUT" "$hp_sl_dir/gates/$HP_GATE.log" 2>/dev/null; then return 0; fi
  printf '%s/gates/%s.log' "$hp_sl_dir" "$HP_GATE"
}

hp_evidence() {
  hp_ev_body=$(hp_tail)
  hp_ev_log=$(hp_save_log)
  if [ -n "$hp_ev_log" ]; then
    printf '%s\nlog: %s' "$hp_ev_body" "$hp_ev_log"
  else
    printf '%s' "$hp_ev_body"
  fi
}

hp_result() {
  hp_rs_detail=$(printf '%s' "$2" | awk "$HP_ESCAPE_AWK")
  hp_rs_evidence=$(printf '%s' "$3" | awk "$HP_ESCAPE_AWK")
  printf '{"gate":"%s","result":"%s","detail":"%s","evidence":"%s"}\n' \
    "$HP_GATE" "$1" "$hp_rs_detail" "$hp_rs_evidence"
}

hp_pass() {
  hp_result pass "$1" "${2:-}"
  exit "$HP_PASS"
}

hp_fail() {
  hp_result fail "$1" "${2:-}"
  exit "$HP_FAIL"
}

hp_did_not_run() {
  # 78, never 0. The JSON says did_not_run, but the exit code is the only thing a shell
  # caller, CI step or hook reads, and 0 there reports a pass nobody verified.
  hp_result did_not_run "$1" "${2:-}"
  exit 78
}

# ---------------------------------------------------------------- shared gate body

# hp_command_gate <commands key> — the whole flow for a gate that runs one configured command.
# Exits. It never returns to the caller.
hp_command_gate() {
  hp_cg_key=$1

  if ! hp_enabled; then
    hp_did_not_run "gate disabled in hyperpower.yml" "gates.$HP_GATE.enabled is false"
  fi

  hp_cg_raw=$(hp_cfg_str "commands.$hp_cg_key")
  if [ -z "$hp_cg_raw" ]; then
    hp_did_not_run "commands.$hp_cg_key is null or missing" \
      "set commands.$hp_cg_key in hyperpower.yml, or set gates.$HP_GATE.enabled to false"
  fi

  if ! hp_tool_check "$hp_cg_raw"; then
    hp_did_not_run "${hp_cg_raw%% *} is not on PATH" "commands.$hp_cg_key = $hp_cg_raw"
  fi

  case $hp_cg_raw in
    *"{route}"*)
      if [ -z "${HYPERPOWER_ROUTE:-}" ]; then
        hp_did_not_run "commands.$hp_cg_key uses {route} but HYPERPOWER_ROUTE is unset" \
          "commands.$hp_cg_key = $hp_cg_raw"
      fi
      ;;
  esac

  case $hp_cg_raw in
    *"{files}"*)
      if [ "$(hp_file_count)" -eq 0 ]; then
        hp_did_not_run "no files in scope for {files}" \
          "commands.$hp_cg_key = $hp_cg_raw"
      fi
      ;;
  esac

  hp_cg_label=$(hp_short "$hp_cg_raw" 120)
  hp_cg_cmd=$(hp_expand "$hp_cg_raw")
  hp_cg_status=0
  hp_exec "$hp_cg_cmd" || hp_cg_status=$?
  hp_cg_log=$(hp_save_log)

  if [ "$hp_cg_status" -eq 0 ] && [ "$HP_TIMED_OUT" -eq 0 ]; then
    hp_cg_evidence="commands.$hp_cg_key = $hp_cg_raw"
  else
    hp_cg_evidence=$(hp_tail)
  fi
  if [ -n "$hp_cg_log" ]; then
    hp_cg_evidence="$hp_cg_evidence
log: $hp_cg_log"
  fi

  if [ "$HP_TIMED_OUT" -eq 1 ]; then
    hp_did_not_run "$hp_cg_label timed out after ${HP_TIMEOUT}s" "$hp_cg_evidence"
  fi
  # 127 is "command not found". hp_tool_check only sees the first word, so a runner such as
  # npx or pnpm, or an env-var prefix, can hide a missing tool until execution.
  if [ "$hp_cg_status" -eq 127 ]; then
    hp_did_not_run "$hp_cg_label exited 127: a command it invokes is not installed" \
      "$hp_cg_evidence"
  fi
  if [ "$hp_cg_status" -eq 0 ]; then
    hp_pass "$hp_cg_label passed in ${HP_DURATION}s" "$hp_cg_evidence"
  fi
  hp_fail "$hp_cg_label exited $hp_cg_status after ${HP_DURATION}s.$(hp_advisory_note)" \
    "$hp_cg_evidence"
}
