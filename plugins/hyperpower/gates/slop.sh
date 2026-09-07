#!/bin/sh
# slop gate. Runs antislop --profile <profile> and ai-slop-detector over the scoped files.
# Static analysis only. No model, no tokens.
# Exit 78 when the gate is disabled, either binary is missing from PATH, the profile is strict,
# no files are in scope, or a tool times out. It never passes because a tool was missing.
set -eu

HP_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$HP_DIR/_lib.sh"

hp_init slop

if ! hp_enabled; then
  hp_did_not_run "gate disabled in hyperpower.yml" "gates.slop.enabled is false"
fi

profile=$(hp_cfg_str gates.slop.profile)
if [ -z "$profile" ]; then profile=core; fi
case $profile in
  core|standard)
    ;;
  strict)
    hp_did_not_run "profile strict is not allowed in the gate" \
      "gates.slop.profile = strict. Use core here and standard in /hyperpower:sweep."
    ;;
  *)
    hp_did_not_run "unknown slop profile: $profile" \
      "gates.slop.profile must be core or standard"
    ;;
esac

# Both tools are part of the check. One of them missing means half the check did not happen,
# so the gate reports did_not_run rather than a pass it only half verified.
missing=""
if ! command -v antislop >/dev/null 2>&1; then missing="antislop"; fi
if ! command -v ai-slop-detector >/dev/null 2>&1; then
  if [ -n "$missing" ]; then missing="$missing and ai-slop-detector"
  else missing="ai-slop-detector"; fi
fi
if [ -n "$missing" ]; then
  hp_did_not_run "$missing not on PATH" \
    "install what is missing, or set gates.slop.enabled to false in hyperpower.yml"
fi

count=$(hp_file_count)
if [ "$count" -eq 0 ]; then
  hp_did_not_run "no files in scope" \
    "set HYPERPOWER_FILES, or run inside a git work tree with changes"
fi

files_arg=$(hp_scope_files | hp_quote_files)
combined=$HP_TMPDIR/slop.log
: > "$combined"

elapsed=0
failed=""

status=0
hp_exec "antislop --profile $profile$files_arg" || status=$?
printf '=== antislop --profile %s ===\n' "$profile" >> "$combined"
cat "$HP_OUT" >> "$combined"
elapsed=$((elapsed + HP_DURATION))
if [ "$HP_TIMED_OUT" -eq 1 ]; then
  HP_OUT=$combined
  hp_did_not_run "antislop timed out after ${HP_TIMEOUT}s" "$(hp_evidence)"
fi
if [ "$status" -eq 127 ]; then
  HP_OUT=$combined
  hp_did_not_run "antislop exited 127: a command it invokes is not installed" "$(hp_evidence)"
fi
if [ "$status" -ne 0 ]; then failed="antislop exited $status"; fi

status=0
hp_exec "ai-slop-detector$files_arg" || status=$?
printf '=== ai-slop-detector ===\n' >> "$combined"
cat "$HP_OUT" >> "$combined"
elapsed=$((elapsed + HP_DURATION))
if [ "$HP_TIMED_OUT" -eq 1 ]; then
  HP_OUT=$combined
  hp_did_not_run "ai-slop-detector timed out after ${HP_TIMEOUT}s" "$(hp_evidence)"
fi
if [ "$status" -eq 127 ]; then
  HP_OUT=$combined
  hp_did_not_run "ai-slop-detector exited 127: a command it invokes is not installed" \
    "$(hp_evidence)"
fi
if [ "$status" -ne 0 ]; then
  if [ -n "$failed" ]; then failed="$failed, ai-slop-detector exited $status"
  else failed="ai-slop-detector exited $status"; fi
fi

HP_OUT=$combined
evidence=$(hp_evidence)

if [ -n "$failed" ]; then
  hp_fail "$failed on $count files.$(hp_advisory_note)" "$evidence"
fi

hp_pass "antislop ($profile) and ai-slop-detector passed on $count files in ${elapsed}s" \
  "$evidence"
