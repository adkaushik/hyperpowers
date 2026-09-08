#!/bin/sh
# hp-gates: the three exit codes, and the run journal it writes.
#
# The exit code is the only signal a hook, a CI step or /hyperpower:run reads. 0 must mean
# every enabled blocking gate passed, 1 must mean one failed, and 78 must mean one could
# not run. A gate the config disabled is a deliberate choice, so it never produces 78.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'hp-gates.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only hp-gates'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

# write_config <typecheck> <types.enabled> <types.blocking> <test_scoped> <unit.enabled> <unit.blocking>
# Every other gate stays off, so each scenario runs only the gates it names.
write_config() {
  cat > "$HP_TEST_REPO/hyperpower.yml" <<EOF
version: 1
project:
  name: scratch
paths:
  source: [src/]
  ignore: [dist/]
commands:
  typecheck: $1
  test_scoped: $4
gates:
  types:   { enabled: $2, blocking: $3 }
  unit:    { enabled: $5, blocking: $6 }
  lint:    { enabled: false, blocking: false }
  build:   { enabled: false, blocking: false }
  slop:    { enabled: false, blocking: false }
  e2e:     { enabled: false, blocking: false }
  browser: { enabled: false, blocking: false }
  a11y:    { enabled: false, blocking: false }
  visual:  { enabled: false, blocking: false }
models:
  judgment: claude-opus-5
  mechanical: claude-haiku-4-5
limits:
  gate_timeout_seconds: 60
telemetry:
  enabled: true
EOF
}

# ---------------------------------------------------------------------------
# Exit 0: every enabled blocking gate passed.

write_config true true true null false false
t_hp_gates --json
t_status "every enabled blocking gate passing exits 0" 0
t_eq "the passing gate is recorded as a pass" "pass" "$(t_tool gate-field "$T_OUT" types result)"
t_eq "no blocking gate failed" "[]" "$(t_json_get "$T_OUT" blocking_failures)"
t_eq "no blocking gate went unverified" "[]" "$(t_json_get "$T_OUT" blocking_unverified)"
t_eq "the aggregate records the exit code it returned" "0" \
  "$(t_json_get "$T_OUT" exit_code)"

# ---------------------------------------------------------------------------
# Exit 1: a blocking gate failed.

write_config false true true null false false
t_hp_gates --json
t_status "a failing blocking gate exits 1" 1
t_eq "the failing gate is recorded as a failure" "fail" "$(t_tool gate-field "$T_OUT" types result)"
t_eq "the failing blocking gate is named" '["types"]' \
  "$(t_json_get "$T_OUT" blocking_failures)"

# ---------------------------------------------------------------------------
# Exit 78: a blocking gate could not run. Never 0, because nothing was verified.

write_config null true true null false false
t_hp_gates --json
t_status "a blocking gate whose command is null exits 78" 78
t_eq "the gate that could not run is recorded as did_not_run" "did_not_run" \
  "$(t_tool gate-field "$T_OUT" types result)"
t_eq "the unverified blocking gate is named" '["types"]' \
  "$(t_json_get "$T_OUT" blocking_unverified)"
t_eq "a gate that could not run is not a failure" "[]" \
  "$(t_json_get "$T_OUT" blocking_failures)"

write_config "hp-test-absent-tool --check" true true null false false
t_hp_gates --json
t_status "a blocking gate whose tool is missing exits 78" 78
t_eq "the missing tool is recorded as did_not_run" "did_not_run" \
  "$(t_tool gate-field "$T_OUT" types result)"
t_file_has "the detail names the tool that is not on PATH" "$T_OUT" "hp-test-absent-tool"

# ---------------------------------------------------------------------------
# A disabled gate never produces 78, whatever its blocking flag says.

write_config true false true true true true
t_hp_gates --json
t_status "a disabled blocking gate does not produce 78" 0
t_eq "the disabled gate is recorded as did_not_run" "did_not_run" \
  "$(t_tool gate-field "$T_OUT" types result)"
t_eq "the disabled gate carries the disabled detail" "gate disabled in hyperpower.yml" \
  "$(t_tool gate-field "$T_OUT" types detail)"
t_eq "a disabled gate is not counted as unverified" "[]" \
  "$(t_json_get "$T_OUT" blocking_unverified)"
t_eq "the enabled blocking gate still ran" "pass" "$(t_tool gate-field "$T_OUT" unit result)"

# ---------------------------------------------------------------------------
# A non-blocking gate reports its result and never changes the exit code.

write_config false true false null false false
t_hp_gates --json
t_status "a failing non-blocking gate exits 0" 0
t_eq "the warning is still recorded as a failure" "fail" "$(t_tool gate-field "$T_OUT" types result)"
t_eq "a non-blocking failure is not a blocking failure" "[]" \
  "$(t_json_get "$T_OUT" blocking_failures)"

write_config null true false null false false
t_hp_gates --json
t_status "a non-blocking gate that could not run exits 0" 0

# A blocking failure outranks a blocking gate that could not run.
write_config false true true null true true
t_hp_gates --json
t_status "a blocking failure beside an unverified gate exits 1" 1
t_eq "both gates are still reported" '["types"]' "$(t_json_get "$T_OUT" blocking_failures)"
t_eq "the unverified gate is still named" '["unit"]' \
  "$(t_json_get "$T_OUT" blocking_unverified)"

# ---------------------------------------------------------------------------
# The run journal: gates.json is a step contract, and every gate gets a usage record.

write_config true true true null false false
t_hp_journal new --root "$HP_TEST_REPO" --task-class feature
t_status "hp-journal new exits 0" 0
run=$(t_out)
runs=$HP_TEST_REPO/.hyperpower/runs/$run

t_hp_gates --run "$run"
t_status "hp-gates writing into a run still exits 0" 0
t_file "hp-gates writes gates.json into the run folder" "$runs/gates.json"

t_hp_validate gates --file "$runs/gates.json"
t_status "gates.json validates against schemas/gates.json" 0
t_json "gates.json names the gates step" "$runs/gates.json" step "gates"
t_json "gates.json names its run" "$runs/gates.json" run_id "$run"
t_ne "gates.json is stamped with recorded_at" "<missing>" \
  "$(t_json_get "$runs/gates.json" recorded_at)"
t_ne "gates.json carries a cache key resume can drift-check" "<missing>" \
  "$(t_json_get "$runs/gates.json" cache_key.key)"

t_eq "one usage record per configured gate" "9" "$(t_tool jsonl-count "$runs/usage.jsonl")"
t_eq "the usage record names the gate stage" "gate:types" \
  "$(t_tool jsonl-get "$runs/usage.jsonl" 1 stage)"
t_eq "a gate usage record carries no token counts" "duration_ms,outcome,stage,ts" \
  "$(t_tool jsonl-keys "$runs/usage.jsonl" 1)"
t_file "the gate writes its own log into the run folder" "$runs/gates/types.log"

# ---------------------------------------------------------------------------
# --only runs one gate. With no run named it is a probe and records nothing.

rm -f "$runs/gates.json"
t_hp_gates --only types --json
t_status "a one-gate probe exits 0" 0
t_eq "the probe ran one gate" "1" "$(t_json_get "$T_OUT" counts.total)"
t_no_file "a probe with no run writes no gates.json" "$runs/gates.json"
t_stderr_has "the probe says why it recorded nothing" "probe"

t_hp_gates --only nosuchgate
t_status "--only on a gate the config does not list exits 2" 2
t_stderr_has "it lists the gates the config does hold" "types"
