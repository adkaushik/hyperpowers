#!/bin/sh
# hp-validate: it accepts a valid contract, and it reports every violation in an invalid
# one rather than stopping at the first.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'hp-validate.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only hp-validate'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

STEPS="route understand plan design build gates review fix render"

# ---------------------------------------------------------------------------
# 1. Every stage has a schema, and the smallest instance that schema describes is valid.

t_hp_validate --list
t_status "hp-validate --list exits 0" 0
for step in $STEPS; do
  t_file "schemas/$step.json exists" "$HP_SCHEMAS/$step.json"
  t_stdout_has "--list names the $step stage" "$step"
done

for step in $STEPS; do
  contract=$HP_TEST_TMP/$step.json
  t_tool contract "$HP_SCHEMAS/$step.json" > "$contract"
  t_hp_validate "$step" --file "$contract"
  t_status "hp-validate accepts a valid $step contract" 0
  t_stdout_has "it says which contract it validated for $step" "valid:"
done

t_hp_validate plan --stdin
t_status "an empty stdin contract exits 1" 1
T_STDIN=$HP_TEST_TMP/plan.json
t_hp_validate plan --stdin
t_status "a contract on stdin validates" 0

# ---------------------------------------------------------------------------
# 2. An invalid contract is exit 1, and every violation is printed.
#
# Three faults at once: a required field removed, a field the schema does not allow, and a
# value outside an enum. A validator that stops at the first fault reports one of them.

bad=$HP_TEST_TMP/bad-plan.json
t_tool contract "$HP_SCHEMAS/plan.json" \
  --drop approach --extra not_in_the_schema --enum-break status > "$bad"

t_hp_validate plan --file "$bad"
t_status "an invalid contract exits 1" 1
t_stderr_has "it reports the missing required field" '$.approach'
t_stderr_has "it reports the field that is not in the schema" '$.not_in_the_schema'
t_stderr_has "it reports the value outside the enum" '$.status'
t_stderr_has "it counts every violation rather than the first" "3 violations."
t_stderr_has "it names the schema it checked against" "plan.json"

single=$HP_TEST_TMP/one-fault.json
t_tool contract "$HP_SCHEMAS/plan.json" --drop approach > "$single"
t_hp_validate plan --file "$single"
t_status "one fault is still exit 1" 1
t_stderr_has "one fault is counted in the singular" "1 violation."

# ---------------------------------------------------------------------------
# 3. The other exit codes.

printf 'not json at all\n' > "$HP_TEST_TMP/garbage.json"
t_hp_validate plan --file "$HP_TEST_TMP/garbage.json"
t_status "a file that is not JSON exits 1" 1
t_stderr_has "it says the file is not valid JSON" "not valid JSON"

t_hp_validate plan --file "$HP_TEST_TMP/does-not-exist.json"
t_status "a file that does not exist exits 1" 1

t_hp_validate nosuchstage --file "$HP_TEST_TMP/plan.json"
t_status "a stage with no schema exits 78" 78
t_stderr_has "it lists the stages that do have schemas" "plan"

t_hp_validate plan
t_status "naming neither --file nor --stdin is a usage error" 2

t_hp_validate --list --file "$HP_TEST_TMP/plan.json"
t_status "--list with a file is a usage error" 2

# ---------------------------------------------------------------------------
# 4. Every schema carries the fixed assumption record. hp-validate refuses one that varies.

for step in $STEPS; do
  t_eq "schemas/$step.json requires the assumptions array" "array" \
    "$(t_tool json-get "$HP_SCHEMAS/$step.json" properties.assumptions.type)"
  t_eq "schemas/$step.json fixes the seven assumption fields" \
    "checkable,claim,confidence,declared_at,id,source,status" \
    "$(t_tool json-members "$HP_SCHEMAS/$step.json" properties.assumptions.items.required)"
  t_eq "schemas/$step.json forbids an invented contract field" "false" \
    "$(t_tool json-get "$HP_SCHEMAS/$step.json" additionalProperties)"
done

broken=$HP_TEST_TMP/schemas
mkdir -p "$broken"
"$HP_PYTHON" - "$HP_SCHEMAS/plan.json" "$broken/plan.json" <<'PY'
import json
import sys

schema = json.load(open(sys.argv[1], encoding="utf-8"))
schema["properties"]["assumptions"]["items"]["required"].remove("checkable")
json.dump(schema, open(sys.argv[2], "w", encoding="utf-8"))
PY
t_hp_validate plan --file "$HP_TEST_TMP/plan.json" --schemas-dir "$broken"
t_status "a schema that drops an assumption field is refused at load time" 78
t_stderr_has "the refusal names the fixed record" "checkable"
