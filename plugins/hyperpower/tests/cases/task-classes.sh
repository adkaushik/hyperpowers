#!/bin/sh
# task-classes.yml: one vocabulary in three files.
#
# The class names live in task-classes.yml, in the task_class enum of schemas/route.json,
# and in the same enum of schemas/plan.json. Route writes the class, the planner copies it,
# and /hyperpower:usage groups by it. A class in one file and not the others kills a run at
# its second stage, so the three lists are compared here directly.
#
# task-classes.yml is read through hp-config's own parser. A second parser here would drift
# from the one the harness ships.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'task-classes.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only task-classes'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

TABLE=$HP_PLUGIN/task-classes.yml
ROUTE=$HP_SCHEMAS/route.json
PLAN=$HP_SCHEMAS/plan.json

t_file "the routing table ships with the plugin" "$TABLE"

declared=$(t_tool yaml-keys "$TABLE" classes)
t_ne "task-classes.yml declares classes" "" "$declared"
t_ge "task-classes.yml declares the seven documented classes" 7 \
  "$(printf '%s\n' "$declared" | tr ',' '\n' | wc -l | tr -d ' ')"

t_eq "schemas/route.json names every class task-classes.yml declares" "$declared" \
  "$(t_tool json-members "$ROUTE" properties.task_class.enum)"
t_eq "schemas/plan.json names every class task-classes.yml declares" "$declared" \
  "$(t_tool json-members "$PLAN" properties.task_class.enum)"
t_eq "route.json candidates uses the same class list" "$declared" \
  "$(t_tool json-members "$ROUTE" properties.candidates.items.enum)"
t_eq "route.json ratcheted_from uses the same class list" "$declared" \
  "$(t_tool json-members "$ROUTE" properties.ratcheted_from.enum --no-null)"

t_eq "the ratchet orders every declared class" "$declared" \
  "$(t_tool yaml-members "$TABLE" ratchet)"
t_in "the fallback class is one of the declared classes" \
  "$(t_tool yaml-get "$TABLE" fallback)" "$declared"

# ---------------------------------------------------------------------------
# Stage lists and tiers, per class.

pipeline=$(t_tool yaml-members "$TABLE" pipeline)
t_eq "route.json stages enum matches the pipeline" "$pipeline" \
  "$(t_tool json-members "$ROUTE" properties.stages.items.enum)"
t_eq "route.json skipped enum matches the pipeline" "$pipeline" \
  "$(t_tool json-members "$ROUTE" properties.skipped.items.enum)"

tiers_allowed=$(t_tool yaml-members "$TABLE" tiers_allowed)
t_eq "the two model tiers are the only tiers" "judgment,mechanical" "$tiers_allowed"

for class in $(printf '%s' "$declared" | tr ',' ' '); do
  stages=$(t_tool yaml-members "$TABLE" "classes.$class.stages")
  tiers=$(t_tool yaml-keys "$TABLE" "classes.$class.tiers")
  t_eq "class $class gives every stage it runs a model tier" "$stages" "$tiers"

  for stage in $(printf '%s' "$stages" | tr ',' ' '); do
    t_in "class $class runs $stage, which is in the pipeline" "$stage" "$pipeline"
    t_in "class $class runs $stage on an allowed tier" \
      "$(t_tool yaml-get "$TABLE" "classes.$class.tiers.$stage")" "$tiers_allowed"
  done

  t_ne "class $class says how to recognise it" "<missing>" \
    "$(t_tool yaml-get "$TABLE" "classes.$class.recognise")"
  t_ne "class $class says what rules it out" "<missing>" \
    "$(t_tool yaml-get "$TABLE" "classes.$class.not_this_class")"
  t_ne "class $class says whether it waits for a human" "<missing>" \
    "$(t_tool yaml-get "$TABLE" "classes.$class.waits_for_human")"
done

# route never appears in a class stage list. It runs before the class is known.
t_eq "route is not a stage any class can select" "0" \
  "$(printf '%s\n' "$pipeline" | tr ',' '\n' | grep -c '^route$' || true)"
