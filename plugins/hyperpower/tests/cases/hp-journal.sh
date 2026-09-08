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
JOURNAL=$HP_SCRIPTS/JOURNAL.md

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
#
# The expected key sets are read out of JOURNAL.md at test time rather than restated here.
# A field added to the writer and not to the document fails, and so does the reverse. A
# restated list would pass while the two drifted apart.

usage=$RUNS/$run/usage.jsonl

j usage "$run" --stage review --agent reviewer --model claude-opus-5 \
  --input 18422 --output 1130 --cache-read 16000 --duration-ms 9400 --outcome ok
t_status "hp-journal usage records a model call" 0
t_eq "a model call carries the keys JOURNAL.md documents" \
  "$(t_tool md-jsonl-keys "$JOURNAL" usage.jsonl 1)" "$(t_tool jsonl-keys "$usage" 1)"
t_eq "input_tokens holds the fresh input only" "18422" \
  "$(t_tool jsonl-get "$usage" 1 input_tokens)"
t_eq "cache_read is recorded apart from input_tokens" "16000" \
  "$(t_tool jsonl-get "$usage" 1 cache_read)"
t_eq "the stage is written as given" "review" "$(t_tool jsonl-get "$usage" 1 stage)"

j usage "$run" --stage gate:types --duration-ms 3200 --outcome ok
t_status "hp-journal usage records a gate result" 0
t_eq "a gate record carries the keys JOURNAL.md documents for one" \
  "$(t_tool md-jsonl-keys "$JOURNAL" usage.jsonl 2)" "$(t_tool jsonl-keys "$usage" 2)"
t_eq "a gate record names no model" "gate:types" \
  "$(t_tool md-jsonl-get "$JOURNAL" usage.jsonl 2 stage)"

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
t_eq "a mistake line carries the keys JOURNAL.md documents" \
  "$(t_tool md-jsonl-keys "$JOURNAL" mistakes.jsonl 1)" "$(t_tool jsonl-keys "$mistakes" 1)"
t_file_lacks "a mistake line carries no timestamp" "$mistakes" '"ts"'
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

# ---------------------------------------------------------------------------
# 6. The cache key is the digest JOURNAL.md specifies, byte for byte.
#
# Three digests, one per line, each line terminated, with the literal none for a digest
# that is null. hptool computes that here from the stored inputs, so this compares
# hp-journal against the document rather than against itself. An implementation that drops
# the sentinel or the trailing newline computes a different key for an unchanged step, and
# every resume then replays work that had not moved.

j new --base "$BASE"
krun=$(t_out)
t_tool contract "$HP_SCHEMAS/understand.json" --run-id "$krun" > "$HP_TEST_TMP/ku.json"
t_tool contract "$HP_SCHEMAS/plan.json" --run-id "$krun" > "$HP_TEST_TMP/kp.json"
j step "$krun" understand --file "$HP_TEST_TMP/ku.json"
j hash "$krun" understand --files src/a.txt --prompt "understand prompt"

ku=$RUNS/$krun/understand.json
t_eq "the first recorded step has no upstream to hash" "null" \
  "$(t_json_get "$ku" cache_key.upstream_hash)"
t_eq "the first step's key is the documented digest of its three inputs" \
  "$(t_tool cache-key "$(t_json_get "$ku" cache_key.prompt_hash)" \
    "$(t_json_get "$ku" cache_key.upstream_hash)" \
    "$(t_json_get "$ku" cache_key.files_hash)")" \
  "$(t_json_get "$ku" cache_key.key)"

j step "$krun" plan --file "$HP_TEST_TMP/kp.json"
j hash "$krun" plan --files src/a.txt,src/b.txt --prompt "plan prompt"
kp=$RUNS/$krun/plan.json
t_ne "a later step hashes the step recorded before it" "null" \
  "$(t_json_get "$kp" cache_key.upstream_hash)"
t_eq "a later step's key is the documented digest too" \
  "$(t_tool cache-key "$(t_json_get "$kp" cache_key.prompt_hash)" \
    "$(t_json_get "$kp" cache_key.upstream_hash)" \
    "$(t_json_get "$kp" cache_key.files_hash)")" \
  "$(t_json_get "$kp" cache_key.key)"
t_ne "the key is not the prompt hash alone" "$(t_json_get "$kp" cache_key.prompt_hash)" \
  "$(t_json_get "$kp" cache_key.key)"
t_eq "the blob hash is the value git hash-object prints" \
  "$(git -C "$HP_TEST_REPO" hash-object src/b.txt)" \
  "$(t_json_get "$kp" cache_key.blobs.'src/b.txt')"

# ---------------------------------------------------------------------------
# 7. step validates the record before it writes it.
#
# The check lives in hp-journal and not only in the skill that calls it, so a shell loop
# calling hp-journal step gets the same refusal.

j new --base "$BASE"
vrun=$(t_out)
t_tool contract "$HP_SCHEMAS/plan.json" --run-id "$vrun" \
  --drop approach --enum-break status > "$HP_TEST_TMP/vbad.json"

j step "$vrun" plan --file "$HP_TEST_TMP/vbad.json"
t_status "a contract the schema rejects is refused" 1
t_no_file "the refused contract left no plan.json behind" "$RUNS/$vrun/plan.json"
t_stderr_has "the refusal reports the missing field" '$.approach'
t_stderr_has "the refusal reports the value outside the enum" '$.status'
t_stderr_has "the refusal names the escape hatch" "--no-validate"

j step "$vrun" plan --file "$HP_TEST_TMP/vbad.json" --no-validate
t_status "--no-validate records the contract unchecked" 0
t_file "--no-validate wrote the file the check refused" "$RUNS/$vrun/plan.json"

# ---------------------------------------------------------------------------
# 8. corrections.jsonl, and the once lifecycle.
#
# A once correction applies to the next replay of its own step and then retires. Three
# commands own one step each, and correction-applied is the only writer of applied.

j new --base "$BASE"
crun=$(t_out)
t_tool contract "$HP_SCHEMAS/plan.json" --run-id "$crun" --assumption a1 \
  > "$HP_TEST_TMP/cplan.json"
j step "$crun" plan --file "$HP_TEST_TMP/cplan.json"
t_status "a contract declaring an assumption is recorded" 0

corrections=$RUNS/$crun/corrections.jsonl

j correction "$crun" --step plan --assumption a1 \
  --text "settings API returns { items: [] }" --scope once
t_status "hp-journal correction records a correction" 0
t_eq "a correction line carries the keys JOURNAL.md documents" \
  "$(t_tool md-jsonl-keys "$JOURNAL" corrections.jsonl 1)" \
  "$(t_tool jsonl-keys "$corrections" 1)"
t_eq "the correction names the assumption it corrects" "a1" \
  "$(t_tool jsonl-get "$corrections" 1 assumption)"
t_eq "the scope is written as given" "once" "$(t_tool jsonl-get "$corrections" 1 scope)"
t_eq "a new correction is not stamped applied" "<missing>" \
  "$(t_tool jsonl-get "$corrections" 1 applied)"

j correction "$crun" --step plan --assumption a9 --text "no such assumption" --scope once
t_status "a correction against an assumption the step never declared is refused" 1
t_stderr_has "the refusal names the ids the step did declare" "a1"

j corrections "$crun" --step plan --pending --json
t_status "hp-journal corrections --pending exits 0" 0
t_eq "the once correction is pending before a replay uses it" "a1" \
  "$(t_json_get "$T_OUT" 0.assumption)"

j correction-applied "$crun" --step plan
t_status "hp-journal correction-applied exits 0" 0
t_eq "the replay stamps the correction it used" "true" \
  "$(t_tool jsonl-get "$corrections" 1 applied)"

j corrections "$crun" --step plan --pending --json
t_eq "an applied once correction is no longer pending" "[]" "$(t_out)"

j correction "$crun" --step plan --assumption a1 --text "and this one stands" --scope run
j correction-applied "$crun" --step plan
t_eq "a run correction is never stamped applied" "<missing>" \
  "$(t_tool jsonl-get "$corrections" 2 applied)"

# ---------------------------------------------------------------------------
# 9. resume.jsonl carries the step names, not a count.

resume=$RUNS/$crun/resume.jsonl

j resume-event "$crun" --from gates --decision build --drifted build
t_status "hp-journal resume-event records a replay" 0
t_eq "a replay line carries the keys JOURNAL.md documents" \
  "$(t_tool md-jsonl-keys "$JOURNAL" resume.jsonl 1)" "$(t_tool jsonl-keys "$resume" 1)"
t_eq "drifted holds the step name a reader can act on" "build" \
  "$(t_tool jsonl-get "$resume" 1 drifted.0)"
t_eq "the decision is written as given" "build" "$(t_tool jsonl-get "$resume" 1 decision)"

j resume-event "$crun" --from gates --decision gates-anyway
t_status "the anyway decision is part of the vocabulary" 0
j resume-event "$crun" --from gates --decision maybe
t_status "a decision outside the vocabulary is refused" 1

# ---------------------------------------------------------------------------
# 10. UNRECORDED, and a config hash that moved.
#
# hash writes <step>.json before the stage returns, which is the order skills/run uses. A
# file holding only a cache key is a placeholder. Reporting it as ok would replay over a
# stage that never produced a contract.

j hash "$crun" review --files src/b.txt --prompt "review prompt"
t_status "hash writes a placeholder for a step no stage has recorded" 0
t_file "the placeholder is a file on disk" "$RUNS/$crun/review.json"

j drift "$crun" --from review
t_stdout_has "a cache key with no contract reports UNRECORDED" \
  "UNRECORDED — cache key only, no step contract recorded"
j drift "$crun" --from review --json
t_eq "an unrecorded step is never ok" "no_contract" "$(t_json_get "$T_OUT" steps.1.state)"

cat > "$HP_TEST_REPO/hyperpower.local.yml" <<'EOF'
limits:
  gate_timeout_seconds: 61
EOF

j drift "$crun" --from plan
t_stdout_has "a config hash that moved drifts every step" \
  "Config hash changed since this run. Treat every step as drifted."
j drift "$crun" --from plan --json
t_eq "drift --json records that the config moved" "true" \
  "$(t_json_get "$T_OUT" config_drifted)"
t_eq "a moved config drifts every step, not one" "true" "$(t_json_get "$T_OUT" all_drifted)"

rm -f "$HP_TEST_REPO/hyperpower.local.yml"
j drift "$crun" --from plan --json
t_eq "restoring the config clears the config drift" "false" \
  "$(t_json_get "$T_OUT" config_drifted)"

# ---------------------------------------------------------------------------
# 11. list, path, and the repo root order JOURNAL.md fixes.
#
# HYPERPOWER_REPO_ROOT is how a worktree, a sandbox and a gate subprocess name a root that
# is not the working directory. hp-config, hp-journal and gates/_lib.sh all honour it. A
# script that ignores it reads a different journal, and nothing in the output shows it.

j list --json
t_status "hp-journal list exits 0" 0
t_ne "list names a recorded run" "<missing>" "$(t_json_get "$T_OUT" 0.run)"
t_ne "list names a second recorded run" "<missing>" "$(t_json_get "$T_OUT" 1.run)"

j list --limit 1 --json
t_ne "--limit 1 prints a row" "<missing>" "$(t_json_get "$T_OUT" 0.run)"
t_eq "--limit 1 prints no second row" "<missing>" "$(t_json_get "$T_OUT" 1.run)"

T_CWD=$HP_TEST_TMP
t_run env HYPERPOWER_REPO_ROOT="$HP_TEST_REPO" "$HP_PYTHON" "$HP_JOURNAL" list --json
t_status "HYPERPOWER_REPO_ROOT names the root for hp-journal too" 0
t_ne "a journal read from outside the repo still finds its runs" "<missing>" \
  "$(t_json_get "$T_OUT" 0.run)"

T_CWD=$HP_TEST_TMP
t_run env HYPERPOWER_REPO_ROOT="$HP_TEST_REPO" "$HP_PYTHON" "$HP_JOURNAL" path "$crun"
t_eq "path resolves against the same root" "$RUNS/$crun" "$(t_out)"

# ---------------------------------------------------------------------------
# Task class is checked against task-classes.yml, and the run folder is not created
# when it fails. JOURNAL.md states this as normative: "A class outside that file is
# refused with the valid list, and the run folder is not created." Without this case the
# check can be deleted and every assertion still passes.

before=$(ls "$RUNS" 2>/dev/null | wc -l | tr -d ' ')
t_hp_journal new --root "$HP_TEST_REPO" --task-class totally-invented --base "$BASE"
t_ne "an invented task class is refused" "0" "$T_STATUS"
t_stderr_has "the refusal names the valid classes" "task-classes.yml"
after=$(ls "$RUNS" 2>/dev/null | wc -l | tr -d ' ')
t_eq "a refused class creates no run folder" "$before" "$after"

# Every class the routing table defines is accepted, so the check cannot drift into
# rejecting real work.
for tc in trivial one-file-fix feature ui-feature refactor bug dependency; do
  t_hp_journal new --root "$HP_TEST_REPO" --task-class "$tc" --base "$BASE"
  t_status "task class $tc is accepted" 0
done
