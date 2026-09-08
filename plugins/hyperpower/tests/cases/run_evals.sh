#!/bin/sh
# run_evals.py: the shipped cases are well formed, and score refuses to aggregate rows the
# two conditions were not both judged on.
#
# An unpaired aggregate compares a candidate judged on one set of prompts against a
# baseline judged on another, and prints a verdict as if it had compared them.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'run_evals.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only run_evals'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

CASES=$HP_PLUGIN/evals/cases.jsonl
SCORES=$HP_TEST_TMP/scores.jsonl

row() {
  # row <case id> <trial> <condition> <correctness score>
  printf '{"case":"%s","trial":%s,"condition":"%s","correctness":%s,"autonomy":4,' \
    "$1" "$2" "$3" "$4"
  printf '"actionability":4,"safety":4,"concision":4,"render_conformance":4,"blocker":false}\n'
}

# ---------------------------------------------------------------------------
# 1. validate

t_hp_evals validate
t_status "run_evals.py validate accepts the shipped cases" 0

t_hp_evals validate --cases "$CASES"
t_status "validate accepts the cases file named directly" 0

printf '{"id":"missing-fields"}\n' > "$HP_TEST_TMP/bad-cases.jsonl"
t_hp_evals validate --cases "$HP_TEST_TMP/bad-cases.jsonl"
t_status "validate rejects a case missing required fields" 1

printf 'not json\n' > "$HP_TEST_TMP/garbage.jsonl"
t_hp_evals validate --cases "$HP_TEST_TMP/garbage.jsonl"
t_status "validate rejects a cases file that is not JSONL" 1

t_hp_evals validate --cases "$HP_TEST_TMP/does-not-exist.jsonl"
t_status "validate rejects a cases file that does not exist" 1

# ---------------------------------------------------------------------------
# 2. score refuses unpaired rows.

first=$(t_tool jsonl-get "$CASES" 1 id)
second=$(t_tool jsonl-get "$CASES" 2 id)
t_ne "the shipped cases have ids to score" "<missing>" "$first"

{
  row "$first" 1 baseline 4
  row "$second" 1 baseline 4
  row "$first" 1 candidate 4
} > "$SCORES"

t_hp_evals score --scores "$SCORES" --baseline baseline --candidate candidate
t_status "score refuses unpaired rows with exit 1" 1
t_stderr_has "it says the conditions are not paired" "conditions are not paired"
t_stderr_has "it names the row the candidate is missing" "$second"
t_stderr_has "it refuses to aggregate rather than compare" "refusing to aggregate"

{
  row "$first" 1 baseline 4
  row "$first" 1 candidate 4
  row "$first" 2 candidate 4
} > "$SCORES"

t_hp_evals score --scores "$SCORES" --baseline baseline --candidate candidate
t_status "an extra candidate trial is unpaired too" 1
t_stderr_has "it names the condition missing the row" "baseline"

# ---------------------------------------------------------------------------
# 3. Paired rows aggregate, and the release rule decides.

{
  row "$first" 1 baseline 4
  row "$first" 1 candidate 4
} > "$SCORES"

t_hp_evals score --scores "$SCORES" --baseline baseline --candidate candidate
t_stderr_lacks "paired rows are aggregated" "refusing to aggregate"
t_status "a candidate that only matches baseline fails the release rule" 2
t_stdout_has "the verdict names both conditions" "candidate vs baseline"

{
  row "$first" 1 baseline 2
  row "$first" 1 candidate 5
} > "$SCORES"

t_hp_evals score --scores "$SCORES" --baseline baseline --candidate candidate
t_status "a candidate that beats baseline on every dimension passes" 0

# ---------------------------------------------------------------------------
# 4. Bad score rows are named, not averaged.

{
  row "$first" 1 baseline 4
  printf '{"case":"%s","trial":1,"condition":"candidate","correctness":9,"autonomy":4,' "$first"
  printf '"actionability":4,"safety":4,"concision":4,"render_conformance":4,"blocker":false}\n'
} > "$SCORES"

t_hp_evals score --scores "$SCORES" --baseline baseline --candidate candidate
t_status "a score outside 1 to 5 is refused" 1
t_stderr_has "the bad row is named by line" "line 2"

{
  row "$first" 1 baseline 4
  row "$first" 1 candidate 4
  row "$first" 1 candidate 3
} > "$SCORES"

t_hp_evals score --scores "$SCORES" --baseline baseline --candidate candidate
t_status "two rows for one case, trial and condition are refused" 1
t_stderr_has "the duplicate is named" "duplicate"
