#!/bin/sh
# hp-status: it reads and never writes, it says plainly when no run exists, and its stuck
# signals fire on the journal rather than on a guess.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'hp-status.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only hp-status'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

HP_STATUS="$HP_SCRIPTS/hp-status"
# The fixture repo leaves paths.state at the default, so the runs live here.
RUNS=$HP_TEST_REPO/.hyperpower/runs
t_status_run() { t_run env HYPERPOWER_REPO_ROOT="$HP_TEST_REPO" "$HP_PYTHON" "$HP_STATUS" "$@"; }

t_file "hp-status exists" "$HP_STATUS"
t_status_run --help
t_status "hp-status --help exits 0" 0

# ---------------------------------------------------------------------------
# 1. With no run recorded it must say so, not imply something is wrong. This is the
#    answer to "why are there no logs" and it has to be unmissable.

BEFORE=$(ls "$RUNS" 2>/dev/null | wc -l | tr -d ' ')
if [ "$BEFORE" = "0" ]; then
  t_status_run
  t_status "no runs recorded exits 1" 1
  t_stdout_has "it says a normal question writes nothing" "writes nothing"
else
  t_skip "no runs recorded exits 1" "the fixture already has $BEFORE runs"
fi

# ---------------------------------------------------------------------------
# 2. The environment line answers "is it on".

t_status_run
t_stdout_has "it reports the protocol" "protocol"
t_stdout_has "it reports the state directory" "state"
t_stdout_has "it reports which gates are live" "gates"

# ---------------------------------------------------------------------------
# 3. A recorded run is reported, and the run id appears.

t_hp_journal new --root "$HP_TEST_REPO" --task-class feature
t_status "hp-journal new exits 0" 0
SRUN=$(t_out)

t_status_run
t_status "a recorded run exits 0" 0
t_stdout_has "the run id is reported" "$SRUN"

# ---------------------------------------------------------------------------
# 4. Stuck signals come from the journal. Three identical failure keys is the
#    threshold, because rounds 1-3 resume the same builder.

for _ in 1 2 3; do
  t_hp_journal mistake "$SRUN" --root "$HP_TEST_REPO" \
    --kind gate_failed --key stuck-on-one-thing
done
t_status "hp-journal mistake exits 0" 0

t_status_run --stop-hint
t_stdout_has "a repeated failure key raises a stuck signal" "STUCK SIGNALS"
t_stdout_has "the signal names the repeated key" "stuck-on-one-thing"
t_stdout_has "the report says the signals are facts, not a verdict" "not a verdict"

# ---------------------------------------------------------------------------
# 5. It never stops anything. --stop-hint prints commands for the human to run.
#    A status command that could end a run would be judging from partial logs.

t_stdout_has "--stop-hint points at why" "hyperpower:why"
t_stdout_has "--stop-hint points at resume" "hyperpower:resume"
t_stdout_lacks_kill() {
  t_file_lacks "$1" "$T_OUT" "$2"
}
t_stdout_lacks_kill "it does not claim to have stopped anything" "stopped the run"
t_stdout_lacks_kill "it does not claim the approach is wrong" "wrong route"

# ---------------------------------------------------------------------------
# 6. Read only. The run folder must be byte-identical after a report.

# find -exec, never cksum $(...) - with no files cksum reads stdin and blocks forever.
find "$RUNS/$SRUN" -type f -exec cksum {} + > "$HP_TEST_TMP/before.sums" 2>/dev/null || :
sort -o "$HP_TEST_TMP/before.sums" "$HP_TEST_TMP/before.sums"
t_status_run --last 5
find "$RUNS/$SRUN" -type f -exec cksum {} + > "$HP_TEST_TMP/after.sums" 2>/dev/null || :
sort -o "$HP_TEST_TMP/after.sums" "$HP_TEST_TMP/after.sums"
if cmp -s "$HP_TEST_TMP/before.sums" "$HP_TEST_TMP/after.sums"; then
  t_ok "reporting does not modify the run journal"
else
  t_bad "reporting does not modify the run journal" "checksums changed after a report"
fi

# ---------------------------------------------------------------------------
# 7. --json gives a skill the facts without the prose.

t_status_run --json
t_status "--json exits 0" 0
# t_json_get returning a real value is the proof it parsed as JSON.
t_ne "--json reports whether the protocol would be injected" "<missing>" \
  "$(t_json_get "$T_OUT" protocol_injected)"
t_ne "--json reports the state directory" "<missing>" \
  "$(t_json_get "$T_OUT" state)"

# ---------------------------------------------------------------------------
# 8. Bad input is refused rather than guessed at.

t_status_run --run zzzznope
t_status "an unknown run id exits 2" 2
t_status_run --watch 1
t_status "--watch below the floor exits 2" 2
