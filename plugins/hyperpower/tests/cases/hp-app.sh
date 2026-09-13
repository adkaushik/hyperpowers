#!/bin/sh
# hp-app: the conductor's record. Every subcommand and its exit codes, drift against a moved
# HEAD, paths.state, and the note session start injects.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'hp-app.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only hp-app'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

HP_APP=$HP_SCRIPTS/hp-app
STATE=$HP_TEST_REPO/.hyperpower
APP=$STATE/app.json

app() { t_run "$HP_PYTHON" "$HP_APP" --root "$HP_TEST_REPO" "$@"; }

count_of() {
  "$HP_PYTHON" -c 'import json, sys; print(len(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$1" "$2"
}

# ---------------------------------------------------------------------------
# 1. Nothing recorded yet.

app show
t_status "show with no app exits 1" 1
t_stderr_has "the no-app message names /hyperpower:build" "/hyperpower:build"

app note
t_status "note with no app exits 0" 0
t_eq "note with no app prints nothing, so session start adds nothing" "" "$(t_out)"

app path
t_status "path works before an app exists" 0
case $(t_out) in
  */.hyperpower/app.json) t_ok "app.json lives in the state directory" ;;
  *) t_bad "app.json lives in the state directory" "path printed: $(t_out)" ;;
esac

NOREPO=$HP_TEST_TMP/norepo
mkdir -p "$NOREPO"
if git -C "$NOREPO" rev-parse --show-toplevel >/dev/null 2>&1; then
  t_skip "outside a git repository hp-app exits 78" "the temporary directory is inside a git repository"
else
  T_CWD=$NOREPO
  t_run "$HP_PYTHON" "$HP_APP" show
  t_status "outside a git repository hp-app exits 78" 78
fi

T_CWD=$NOREPO
t_run env HYPERPOWER_REPO_ROOT="$HP_TEST_REPO" "$HP_PYTHON" "$HP_APP" path
t_status "HYPERPOWER_REPO_ROOT names the root from any directory" 0
case $(t_out) in
  "$HP_TEST_REPO"/.hyperpower/app.json) t_ok "the record lives under the root the variable names" ;;
  *) t_bad "the record lives under the root the variable names" "path printed: $(t_out)" ;;
esac

T_CWD=$NOREPO
t_run env HYPERPOWER_REPO_ROOT="$HP_TEST_TMP/no-such-dir" "$HP_PYTHON" "$HP_APP" init --name typo --scope feature --mode conductor --origin new
t_status "a HYPERPOWER_REPO_ROOT that is not a directory is bad input" 2
t_stderr_has "the error names the variable" "HYPERPOWER_REPO_ROOT"
t_no_file "nothing is created under a root that does not exist" "$HP_TEST_TMP/no-such-dir"

# ---------------------------------------------------------------------------
# 2. init records an app, and refuses to replace one silently.

HEAD0=$(git -C "$HP_TEST_REPO" rev-parse HEAD)

app init --name tracker --scope app --mode conductor --origin new --stack "next.js, django"
t_status "init exits 0" 0
t_file "init writes app.json" "$APP"
t_file "init renders app.md beside it" "$STATE/app.md"
t_json "the name is recorded" "$APP" name tracker
t_json "the scope is recorded" "$APP" scope app
t_json "the mode is recorded" "$APP" mode conductor
t_json "the origin is recorded" "$APP" origin new
t_json "the record is version 1" "$APP" version 1
t_json "no feature is current yet" "$APP" current null
t_eq "the stack is split on commas and trimmed" "django,next.js" \
  "$(t_tool json-members "$APP" stack)"
t_json "init records HEAD as the reconciled commit" "$APP" reconciled_head "$HEAD0"

app init --name other --scope feature --mode conductor --origin new
t_status "a second init without --force exits 2" 2
t_stderr_has "the refusal says an app is already recorded" "already recorded"
t_json "the refused init leaves the first app in place" "$APP" name tracker

app init --name tracker --scope website --mode conductor --origin new
t_status "an unknown scope is bad input" 2

app init --name tracker --scope app --mode conductor --origin resume
t_stderr_has "resume is not an origin: an app is resumed, never recorded as one" "invalid choice"

app init --name tracker --scope app --mode conductor --origin takeover --force
t_status "init --force replaces the app" 0
t_json "the replacement is what is recorded" "$APP" origin takeover

# ---------------------------------------------------------------------------
# 3. Features: ids in order, status and phase rules, lookup by name.

app feature add --name habits
t_eq "the first feature is f1" "f1" "$(t_out)"
app feature add --name streaks
t_eq "the second feature is f2" "f2" "$(t_out)"
app feature add --name reminders --status half-done
t_eq "the third feature is f3" "f3" "$(t_out)"

t_json "a feature starts planned" "$APP" features.0.status planned
t_json "a new feature has no phase" "$APP" features.0.phase null
t_json "a feature added as half-done keeps that status" "$APP" features.2.status half-done

app feature set f9 --status done
t_status "setting a feature that does not exist exits 2" 2
t_stderr_has "the error lists the features that do exist" "f1, f2, f3"

app feature set habits --status done
t_status "a feature can be named instead of numbered" 0
t_json "setting by name changes that feature" "$APP" features.0.status done

app feature set f2 --phase build
t_status "a phase on a feature that is not active exits 2" 2
t_json "the refused phase is not written" "$APP" features.1.phase null

app feature set f2 --phase deploy
t_status "a phase outside the seven is bad input" 2

app current f2
t_status "current exits 0" 0
t_json "current marks the feature active" "$APP" features.1.status active
t_json "current records which feature" "$APP" current f2

app feature set f2 --phase verify
t_status "a phase on the active feature is accepted" 0
t_json "the phase is recorded" "$APP" features.1.phase verify

app current f3
t_json "only one feature is active: the previous one goes back to planned" "$APP" features.1.status planned
t_json "the previous feature loses its phase" "$APP" features.1.phase null
t_json "the new current feature is active" "$APP" features.2.status active

app feature set f3 --phase report
app feature set f3 --status done --run 4f2a --report .hyperpower/reports/f3-reminders.html
t_json "a finished feature records its run" "$APP" features.2.run_id 4f2a
t_json "a finished feature records its report" "$APP" features.2.report .hyperpower/reports/f3-reminders.html
t_json "a status other than active clears the phase" "$APP" features.2.phase null

t_file_has "app.md shows a done feature checked" "$STATE/app.md" "[x] f1  habits"
t_file_has "app.md shows where the report is" "$STATE/app.md" "report: .hyperpower/reports/f3-reminders.html"

leftover=$(ls -A "$STATE" | grep '^\.app-' || true)
t_eq "every write renames its temp file into place" "" "$leftover"

app show --json
t_status "show --json exits 0" 0
t_json "show --json prints the record" "$T_OUT" name tracker
app show
t_stdout_has "show prints app.md" "# tracker"

# ---------------------------------------------------------------------------
# 4. mode switches without touching anything else.

app mode copassenger
t_status "mode exits 0" 0
t_stdout_has "mode says what it switched to" "mode copassenger"
t_json "the new mode is recorded" "$APP" mode copassenger
t_json "switching mode keeps the features" "$APP" features.0.name habits

app mode passenger
t_status "an unknown mode is bad input" 2
t_json "the refused mode is not written" "$APP" mode copassenger

# ---------------------------------------------------------------------------
# 5. Drift: commits since the last check are reported before they are recorded.

app reconcile --check
t_status "reconcile --check exits 0" 0
t_stdout_has "no commits since init is no drift" "no drift"

printf 'changed\n' >> "$HP_TEST_REPO/src/a.txt"
git -C "$HP_TEST_REPO" commit -q -am "touch a"
printf 'changed\n' >> "$HP_TEST_REPO/src/b.txt"
git -C "$HP_TEST_REPO" commit -q -am "touch b"
HEAD2=$(git -C "$HP_TEST_REPO" rev-parse HEAD)

app reconcile --check --json
t_json "commits since the reconciled head are drift" "$T_OUT" drifted true
t_eq "both commits are listed" 2 "$(count_of "$T_OUT" commits)"
t_eq "the files they changed are listed" "src/a.txt,src/b.txt" \
  "$(t_tool json-members "$T_OUT" files)"
t_json "--check does not record the new head" "$APP" reconciled_head "$HEAD0"

app reconcile
t_status "reconcile exits 0" 0
t_stdout_has "reconcile says how many commits it found" "2 commits since the state was last checked"
t_json "reconcile without --check records the new head" "$APP" reconciled_head "$HEAD2"

app reconcile --check
t_stdout_has "once recorded, the same commits are not drift again" "no drift"

# ---------------------------------------------------------------------------
# 6. The note: what a new session is told about the app in progress.

app current f2
app feature set f2 --phase build

app note
t_status "note with an app exits 0" 0
t_stdout_has "the note is marked as an app in progress" "APP IN PROGRESS"
t_stdout_has "the note names the app, its scope and its mode" "tracker is recorded here as an app in copassenger mode"
t_stdout_has "the note counts finished features" "2 of 3 features done"
t_stdout_has "the note names the current feature and its phase" "Current: streaks, in build."
t_stdout_has "the note forbids resuming unasked" "Never resume on your own."
t_stdout_has "the note lists the four steering phrases" "take over, I'll drive, what's next?, stop"

# ---------------------------------------------------------------------------
# 7. Session start carries the note, and adds nothing when there is no app.

t_run env CLAUDE_PROJECT_DIR="$HP_TEST_REPO" sh "$HP_PLUGIN/hooks/session-start.sh"
t_status "session start exits 0 with an app recorded" 0
t_stdout_has "session start carries the note" "APP IN PROGRESS"
t_stdout_has "session start names build as the entry point" "CONDUCTOR"

BARE=$HP_TEST_TMP/bare
mkdir -p "$BARE"
git -C "$BARE" init -q
t_run env CLAUDE_PROJECT_DIR="$BARE" sh "$HP_PLUGIN/hooks/session-start.sh"
t_status "session start exits 0 with no config" 0
t_stdout_has "with no config, session start points at build" "/hyperpower:build"
t_file_lacks "with no config, session start injects one line, not the protocol" "$T_OUT" "PIPELINE"
t_file_lacks "with no app, session start adds no note" "$T_OUT" "APP IN PROGRESS"

# ---------------------------------------------------------------------------
# 8. paths.state moves the record.

MOVED=$HP_TEST_TMP/moved
mkdir -p "$MOVED"
git -C "$MOVED" init -q
awk '{ print } /^paths:$/ { print "  state: .claude/hyperpower" }' \
  "$HP_TEST_REPO/hyperpower.yml" > "$MOVED/hyperpower.yml"
t_run "$HP_PYTHON" "$HP_APP" --root "$MOVED" init --name moved --scope feature --mode conductor --origin new
t_status "init works with paths.state set" 0
t_file "paths.state moves app.json" "$MOVED/.claude/hyperpower/app.json"
t_no_file "nothing is written to the default state directory" "$MOVED/.hyperpower"

# ---------------------------------------------------------------------------
# 9. Drift with no usable base: a record made before the first commit, and a recorded commit
#    the repository no longer has. Neither may report no drift.

FRESH=$HP_TEST_TMP/fresh
mkdir -p "$FRESH"
git -C "$FRESH" init -q
early() { t_run "$HP_PYTHON" "$HP_APP" --root "$FRESH" "$@"; }

early init --name early --scope feature --mode conductor --origin new
t_json "a record made before the first commit has no reconciled head" \
  "$FRESH/.hyperpower/app.json" reconciled_head null

printf 'one\n' > "$FRESH/one.txt"
git -C "$FRESH" add one.txt
git -C "$FRESH" commit -q -m one
printf 'two\n' > "$FRESH/two.txt"
git -C "$FRESH" add two.txt
git -C "$FRESH" commit -q -m two

early reconcile --check --json
t_json "commits after a record with no base are drift" "$T_OUT" drifted true
t_eq "every commit on HEAD is listed" 2 "$(count_of "$T_OUT" commits)"
t_eq "every file on HEAD is listed" "one.txt,two.txt" "$(t_tool json-members "$T_OUT" files)"

early reconcile --check
t_stdout_has "the text says the record predates the first commit" "before the first commit"

"$HP_PYTHON" - "$FRESH/.hyperpower/app.json" <<'EOF'
import json, sys
with open(sys.argv[1]) as handle:
    state = json.load(handle)
state["reconciled_head"] = "0123456789abcdef0123456789abcdef01234567"
with open(sys.argv[1], "w") as handle:
    json.dump(state, handle)
EOF

early reconcile --check --json
t_json "a recorded commit the repository does not have is flagged" "$T_OUT" base_missing true
t_json "a missing base is drift, never no drift" "$T_OUT" drifted true

early reconcile --check
t_stdout_has "the text says drift cannot be listed" "cannot be listed"
t_file_lacks "the text never claims no drift over a missing base" "$T_OUT" "no drift"

early reconcile
t_json "reconcile records HEAD over a missing base" "$FRESH/.hyperpower/app.json" \
  reconciled_head "$(git -C "$FRESH" rev-parse HEAD)"
