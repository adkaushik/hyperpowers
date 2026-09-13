#!/bin/sh
# copassenger.py: silent unless an app is in co-passenger mode, one line per signal in
# priority order, never the same line twice, and never a decision that blocks the turn.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'copassenger.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only copassenger'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

HOOK=$HP_PLUGIN/hooks/copassenger.py
HP_APP=$HP_SCRIPTS/hp-app
ALL=$HP_TEST_TMP/every-output
PAYLOAD=$HP_TEST_TMP/payload.json

# A repo with no .gitignore. The state directory shows up as untracked, the way it does in
# a repo that never ignored it, which is where the hook could mistake its memo for work.
CP=$HP_TEST_TMP/cp
mkdir -p "$CP"
git -C "$CP" init -q
printf 'base\n' > "$CP/base.txt"
git -C "$CP" add base.txt
git -C "$CP" commit -q -m base

app() { "$HP_PYTHON" "$HP_APP" --root "$CP" "$@" >/dev/null; }

# Every hook call runs with HYPERPOWER_HOOK_DEBUG=1, so a crash fails the assertion instead
# of passing as silence.
# hook <stop_hook_active 0|1> <last assistant message> [repo]
hook() {
  "$HP_PYTHON" -c 'import json, sys
print(json.dumps({"cwd": sys.argv[1], "stop_hook_active": sys.argv[2] == "1",
                  "last_assistant_message": sys.argv[3]}))' "${3:-$CP}" "$1" "$2" > "$PAYLOAD"
  raw "$PAYLOAD"
}

raw() {
  T_STDIN=$1
  t_run env HYPERPOWER_HOOK_DEBUG=1 "$HP_PYTHON" "$HOOK"
  cat "$T_OUT" >> "$ALL"
}

silent() {
  if [ "$T_STATUS" -eq 0 ] && [ ! -s "$T_OUT" ]; then
    t_ok "$1"
    return 0
  fi
  t_bad "$1" "exit $T_STATUS
stdout: $(t_excerpt "$T_OUT")
stderr: $(t_excerpt "$T_ERR")"
}

says() {
  if [ "$T_STATUS" -eq 0 ] && grep -F -q -e "$2" -- "$T_OUT"; then
    t_ok "$1"
    return 0
  fi
  t_bad "$1" "expected a line holding: $2
exit $T_STATUS
stdout: $(t_excerpt "$T_OUT")
stderr: $(t_excerpt "$T_ERR")"
}

fresh() {
  git -C "$CP" reset -q --hard
  git -C "$CP" clean -fdq -e .hyperpower
  rm -f "$CP/.hyperpower/copassenger.json"
}

# ---------------------------------------------------------------------------
# 1. Silence: every condition that must hold before it speaks.

app init --name cp --scope feature --mode copassenger --origin new

printf 'not json{' > "$HP_TEST_TMP/garbage"
raw "$HP_TEST_TMP/garbage"
silent "a payload that is not JSON is silent"

printf '[]' > "$HP_TEST_TMP/list"
raw "$HP_TEST_TMP/list"
silent "a JSON payload that is not an object is silent"

printf 'changed\n' >> "$CP/base.txt"
hook 1 "All done."
silent "stop_hook_active is silent, as a loop guard"

fresh
hook 0 "All done, implemented."
silent "a clean tree is silent, even when the turn claims done"

printf 'changed\n' >> "$CP/base.txt"
mv "$CP/.hyperpower/app.json" "$HP_TEST_TMP/app.json.away"
hook 0 "All done."
silent "no app.json is silent"
mv "$HP_TEST_TMP/app.json.away" "$CP/.hyperpower/app.json"

app mode conductor
hook 0 "All done."
silent "conductor mode is silent, because the conductor is already talking"
app mode copassenger

NOREPO=$HP_TEST_TMP/norepo
mkdir -p "$NOREPO"
if git -C "$NOREPO" rev-parse --show-toplevel >/dev/null 2>&1; then
  t_skip "outside a git repository it is silent" "the temporary directory is inside a git repository"
else
  hook 0 "All done." "$NOREPO"
  silent "outside a git repository it is silent"
fi

# ---------------------------------------------------------------------------
# 2. It speaks once, as systemMessage, and never twice for the same changes.

printf 'new\n' > "$CP/second.txt"
hook 0 "All done, implemented."
says "changed files and a claim of done suggest review" "/hyperpower:review"
t_stdout_has "the file count leaves out the state directory" "with 2 files changed"
t_eq "the output is a systemMessage and nothing else" "systemMessage" \
  "$(t_tool json-keys "$T_OUT" .)"
t_file "the memo is kept in the state directory" "$CP/.hyperpower/copassenger.json"

hook 0 "All done, implemented."
silent "the same claim on the same changes is not repeated"

# Counted as work, the memo would make five files and a new fingerprint, and it would
# start suggesting humanize about itself.
hook 0 "Here is the change."
silent "its own memo is not new work"

# ---------------------------------------------------------------------------
# 3. One line per signal, highest priority first.

fresh
mkdir -p "$CP/app/migrations"
printf 'm\n' > "$CP/app/migrations/0002_add_column.py"
hook 0 "Added the column."
says "a migration suggests the backend pair" "/hyperpower:council"

fresh
printf '{}\n' > "$CP/package.json"
hook 0 "Bumped a package."
says "a manifest suggests janitor" "/hyperpower:janitor"

fresh
for n in 1 2 3 4 5; do printf 'x\n' > "$CP/file$n.txt"; done
hook 0 "Wrote some files."
says "five files suggest humanize" "5 files changed"

fresh
printf 'export const A = 1\n' > "$CP/Widget.tsx"
hook 0 "Made a widget."
says "a component suggests humanize" "touched UI"

fresh
printf 'plain\n' > "$CP/notes.txt"
hook 0 "Wrote a note."
silent "a change that matches no signal is silent"

fresh
mkdir -p "$CP/app/migrations"
printf 'm\n' > "$CP/app/migrations/0003_more.py"
printf '{}\n' > "$CP/package.json"
hook 0 "Migration is in."
says "schema outranks a manifest" "/hyperpower:council"

hook 0 "Done, the migration is in."
says "a claim of done outranks every other signal" "/hyperpower:review"

# ---------------------------------------------------------------------------
# 4. paths.state moves where it reads app.json and keeps its memo.

MOVED=$HP_TEST_TMP/moved
mkdir -p "$MOVED"
git -C "$MOVED" init -q
awk '{ print } /^paths:$/ { print "  state: .claude/hyperpower" }' \
  "$HP_TEST_REPO/hyperpower.yml" > "$MOVED/hyperpower.yml"
git -C "$MOVED" add hyperpower.yml
git -C "$MOVED" commit -q -m base
"$HP_PYTHON" "$HP_APP" --root "$MOVED" init --name moved --scope feature --mode copassenger --origin new >/dev/null
printf 'x\n' > "$MOVED/change.txt"
hook 0 "All done." "$MOVED"
says "with paths.state set, it reads app.json from there" "/hyperpower:review"
t_stdout_has "the moved state directory is not counted as work" "with 1 file changed"
t_file "with paths.state set, the memo lands there" "$MOVED/.claude/hyperpower/copassenger.json"
t_no_file "with paths.state set, nothing lands in .hyperpower" "$MOVED/.hyperpower"

# ---------------------------------------------------------------------------
# 5. A crash is silent in a session and loud under the debug flag.

printf '[]\n' > "$CP/.hyperpower/app.json"
printf 'changed\n' >> "$CP/base.txt"
hook 0 "All done."
t_ne "under HYPERPOWER_HOOK_DEBUG a crash exits non-zero" 0 "$T_STATUS"
t_stderr_has "under HYPERPOWER_HOOK_DEBUG a crash prints its traceback" "Traceback"

T_STDIN=$PAYLOAD
t_run "$HP_PYTHON" "$HOOK"
silent "without the debug flag the same crash is silent, so a session never breaks"

t_file_lacks "no output in this case ever carried a decision" "$ALL" '"decision"'
