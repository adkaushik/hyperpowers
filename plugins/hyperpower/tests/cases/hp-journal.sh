#!/bin/sh
# hp-journal: reproducible run ids, a step contract that survives the round trip, the
# drift report, and the two append-only record shapes JOURNAL.md fixes.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'hp-journal.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only hp-journal'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

RUNS=$HP_TEST_REPO/.hyperpower/runs
BASE=1111111111111111111111111111111111111111
STEPS="route understand plan design build gates review fix render"

j() { t_hp_journal "$@" --root "$HP_TEST_REPO"; }

# ---------------------------------------------------------------------------
# 1. new writes meta.json, and the run id comes from the base sha, not a clock.

j new --task-class feature --base "$BASE"
t_status "hp-journal new exits 0" 0
run=$(t_out)
meta=$RUNS/$run/meta.json

t_file "hp-journal new writes meta.json" "$meta"
t_json "meta.json records the run id" "$meta" run "$run"
t_json "meta.json records the base sha" "$meta" base_sha "$BASE"
t_json "meta.json records the task class route picked" "$meta" task_class "feature"
t_json "meta.json records the schema version" "$meta" schema "1"
t_json "meta.json starts with no outcome" "$meta" outcome "null"
t_json "meta.json starts with no finish time" "$meta" finished_at "null"
t_json "meta.json records the counter the id came from" "$meta" id_counter "0"
t_json "meta.json records the model tiers in effect" "$meta" models.judgment "claude-opus-5"
t_file_has "meta.json records how the id was derived" "$meta" "sha256(<base_sha>:<counter>)"
t_dir "hp-journal new creates the gate log directory" "$RUNS/$run/gates"

t_hp_config --root "$HP_TEST_REPO" --hash
t_json "meta.json records the hash hp-config prints" "$meta" config_hash "$(t_out)"

# The same base sha and counter give the same id in a repository that has never seen it.
REPO2=$HP_TEST_TMP/repo2
mkdir -p "$REPO2"
cp "$HP_TEST_REPO/hyperpower.yml" "$REPO2/hyperpower.yml"
t_hp_journal new --root "$REPO2" --task-class feature --base "$BASE"
t_status "hp-journal new exits 0 in a second repository" 0
t_eq "the run id is reproducible from the same base sha and counter" "$run" "$(t_out)"

# A second run on the same base sha takes the next counter rather than the same folder.
j new --base "$BASE"
second=$(t_out)
t_ne "a second run on one base sha claims a different folder" "$run" "$second"
t_json "the second run records counter 1" "$RUNS/$second/meta.json" id_counter "1"

NO_CONFIG=$HP_TEST_TMP/no-config
mkdir -p "$NO_CONFIG"
t_hp_journal new --root "$NO_CONFIG"
t_status "hp-journal new with no hyperpower.yml exits 78" 78

j path latest
t_eq "latest resolves to a recorded run folder" "$RUNS/$second" "$(t_out)"

# ---------------------------------------------------------------------------
# 2. A contract written by hp-journal step re-validates against its own schema.
#
# hp-journal stamps step, run_id and recorded_at on top of the contract. This is the round
# trip that a stamped field not in the schema would break.

for step in $STEPS; do
  contract=$HP_TEST_TMP/$step-contract.json
  t_tool contract "$HP_SCHEMAS/$step.json" --run-id "$run" > "$contract"

  t_hp_validate "$step" --file "$contract"
  t_status "the minimal $step contract is valid before it is recorded" 0

  j step "$run" "$step" --file "$contract"
  t_status "hp-journal step writes the $step contract" 0

  written=$RUNS/$run/$step.json
  t_json "$step.json names its own step" "$written" step "$step"
  t_json "$step.json names its run" "$written" run_id "$run"
  t_ne "$step.json is stamped with recorded_at" "<missing>" \
    "$(t_json_get "$written" recorded_at)"

  t_hp_validate "$step" --file "$written"
  t_status "the recorded $step contract re-validates against its schema" 0
done

j hash "$run" plan --files src/a.txt,src/b.txt --prompt "plan prompt"
t_status "hp-journal hash stores a cache key for the plan step" 0
t_hp_validate plan --file "$RUNS/$run/plan.json"
t_status "the plan contract still validates after hashing" 0
t_json "the cache key names its upstream step" "$RUNS/$run/plan.json" \
  cache_key.upstream_step "understand"
t_eq "the cache key records the blob of every file the step read" \
  "src/a.txt,src/b.txt" "$(t_tool json-keys "$RUNS/$run/plan.json" cache_key.blobs)"

j step "$run" plan --file "$HP_TEST_TMP/plan-contract.json"
t_json "step keeps the cache key hash already wrote" "$RUNS/$run/plan.json" \
  cache_key.upstream_step "understand"

j step "$run" plan --file "$HP_TEST_TMP/route-contract.json"
t_status "a contract naming another step is refused" 1

# ---------------------------------------------------------------------------
# 3. drift: ok on a clean tree, DRIFTED with a file count after an edit, UNHASHED with no
#    cache key.

j new --base "$BASE"
drun=$(t_out)
t_tool contract "$HP_SCHEMAS/understand.json" --run-id "$drun" > "$HP_TEST_TMP/u.json"
t_tool contract "$HP_SCHEMAS/plan.json" --run-id "$drun" > "$HP_TEST_TMP/p.json"
j step "$drun" understand --file "$HP_TEST_TMP/u.json"
j hash "$drun" understand --files src/a.txt --prompt "understand prompt"

j drift "$drun" --from understand
t_status "hp-journal drift exits 0 on a clean tree" 0
t_stdout_has "a clean step reports ok in lower case" "Understand   ok"
t_stdout_has "the header names the run and the step" "Resume run $drun from Understand."

j drift "$drun" --from understand --json
t_eq "drift --json calls a clean step ok" "ok" "$(t_json_get "$T_OUT" steps.0.state)"
t_eq "a clean step has no changed files" "0" "$(t_json_get "$T_OUT" steps.0.changed_files)"
t_eq "a clean run has no earliest drifted step" "null" \
  "$(t_json_get "$T_OUT" earliest_drifted)"

printf 'edited by the drift test\n' >> "$HP_TEST_REPO/src/a.txt"

j drift "$drun" --from understand
t_stdout_has "an edited file drifts the step and names the count" \
  "DRIFTED — 1 file changed since this step"
t_file_lacks "a drifted step is never reported as ok" "$T_OUT" "Understand   ok"

j drift "$drun" --from understand --json
t_eq "drift --json marks the step drifted" "drifted" "$(t_json_get "$T_OUT" steps.0.state)"
t_eq "drift --json counts the changed files" "1" \
  "$(t_json_get "$T_OUT" steps.0.changed_files)"
t_eq "drift --json names the changed file" "src/a.txt" \
  "$(t_json_get "$T_OUT" steps.0.files.0)"
t_eq "drift --json blames the file input, not the prompt" "true" \
  "$(t_json_get "$T_OUT" steps.0.drifted.files)"

j step "$drun" plan --file "$HP_TEST_TMP/p.json"
j drift "$drun" --from plan
t_stdout_has "a step with no cache key reports UNHASHED" \
  "UNHASHED — no cache key recorded for this step"
j drift "$drun" --from plan --json
t_eq "an unhashed step is never ok" "unhashed" "$(t_json_get "$T_OUT" steps.1.state)"

# paths.ignore removes a file from the comparison.
j new --base "$BASE"
irun=$(t_out)
mkdir -p "$HP_TEST_REPO/dist"
printf 'built\n' > "$HP_TEST_REPO/dist/out.txt"
t_tool contract "$HP_SCHEMAS/understand.json" --run-id "$irun" > "$HP_TEST_TMP/iu.json"
j step "$irun" understand --file "$HP_TEST_TMP/iu.json"
j hash "$irun" understand --files dist/out.txt --prompt "ignored prompt"
printf 'rebuilt\n' > "$HP_TEST_REPO/dist/out.txt"
j drift "$irun" --from understand --json
t_eq "a file under paths.ignore is not compared" "ok" "$(t_json_get "$T_OUT" steps.0.state)"

# ---------------------------------------------------------------------------
# 4. usage.jsonl and mistakes.jsonl carry the shapes JOURNAL.md documents.

usage=$RUNS/$run/usage.jsonl

j usage "$run" --stage review --agent reviewer --model claude-opus-5 \
  --input 18422 --output 1130 --cache-read 16000 --duration-ms 9400 --outcome ok
t_status "hp-journal usage records a model call" 0
t_eq "a model call carries the nine documented fields" \
  "agent,cache_read,duration_ms,input_tokens,model,outcome,output_tokens,stage,ts" \
  "$(t_tool jsonl-keys "$usage" 1)"
t_eq "input_tokens holds the fresh input only" "18422" \
  "$(t_tool jsonl-get "$usage" 1 input_tokens)"
t_eq "cache_read is recorded apart from input_tokens" "16000" \
  "$(t_tool jsonl-get "$usage" 1 cache_read)"
t_eq "the stage is written as given" "review" "$(t_tool jsonl-get "$usage" 1 stage)"

j usage "$run" --stage gate:types --duration-ms 3200 --outcome ok
t_status "hp-journal usage records a gate result" 0
t_eq "a gate record carries no model, agent or token counts" \
  "duration_ms,outcome,stage,ts" "$(t_tool jsonl-keys "$usage" 2)"

j usage "$run" --stage gate:types --model claude-opus-5 --input 1 --output 1
t_status "a gate record naming a model is refused" 1
j usage "$run" --stage plan --input 1 --output 1
t_status "a model call with no --model is refused" 1
j usage "$run" --stage plan --model claude-opus-5
t_status "a model call with no token counts is refused" 1

mistakes=$RUNS/$run/mistakes.jsonl

j mistake "$run" --kind assumption_refuted --key settings-api-shape \
  --ref decisions/2026-09-07-settings.md
t_status "hp-journal mistake records a failure event" 0
t_eq "a mistake line carries exactly run, kind, key and ref" "key,kind,ref,run" \
  "$(t_tool jsonl-keys "$mistakes" 1)"
t_eq "the mistake names the run the promoter counts" "$run" \
  "$(t_tool jsonl-get "$mistakes" 1 run)"

j mistake "$run" --kind gate_failed --key generated-import-drift
t_eq "the ref defaults to the run meta.json" ".hyperpower/runs/$run/meta.json" \
  "$(t_tool jsonl-get "$mistakes" 2 ref)"

j mistake "$run" --kind gate_failed --key Settings-API-Shape
t_status "a mistake key outside kebab case is refused" 1
j mistake "$run" --kind run-4f2a-note --key settings-api-shape
t_status "a mistake kind outside the four is refused" 1

# ---------------------------------------------------------------------------
# 5. finish stamps the outcome the archivist reads.

j finish "$run" --outcome ok
t_status "hp-journal finish exits 0" 0
t_json "meta.json records the outcome" "$meta" outcome "ok"
t_ne "meta.json records when the run finished" "null" "$(t_json_get "$meta" finished_at)"

j finish "$run" --outcome shipped
t_status "an outcome outside the four is refused" 1
