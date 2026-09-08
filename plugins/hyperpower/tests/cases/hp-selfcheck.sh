#!/bin/sh
# hp-selfcheck: the plugin's own guard rails bite.
#
# hp-selfcheck reads the tree and compares it against the documentation. Every check here
# passes on the shipped tree, which proves nothing on its own: a check that cannot fail
# reports the same clean result as a check that works. So each fault is planted in a copy
# of the tree under the scratch directory, and the matching check must report it.
#
# The copy is the whole point. Never plant a fault in the plugin repository.
set -eu

case ${1:-} in
  --help|-h)
    printf '%s\n' \
      'hp-selfcheck.sh - one hyperpower kernel test case.' \
      'It needs the scratch repo and the helper library tests/run-tests builds.' \
      'Run it with: tests/run-tests --only hp-selfcheck'
    exit 0
    ;;
esac
. "$HP_TEST_LIB"

SELFCHECK=$HP_SCRIPTS/hp-selfcheck
COPY=$HP_TEST_TMP/tree
SAVED=$HP_TEST_TMP/saved

t_selfcheck() { t_run "$HP_PYTHON" "$SELFCHECK" "$@"; }

# plant <relative path> — keep the original outside the copy, so no check ever reads it.
plant() {
  mkdir -p "$SAVED"
  cp "$COPY/$1" "$SAVED/$(basename "$1")"
}

restore() {
  cp "$SAVED/$(basename "$1")" "$COPY/$1"
}

# ---------------------------------------------------------------------------
# 1. The shipped tree passes. This is the check CI runs before anything else.

t_selfcheck --root "$HP_REPO"
t_status "hp-selfcheck exits 0 on the shipped tree" 0
t_stdout_has "it reports how many checks ran" "checks,"

t_selfcheck --root "$HP_REPO" --list-checks
t_status "hp-selfcheck --list-checks exits 0" 0
listed=$(grep -c . "$T_OUT")

# The count comes out of architecture.md, so a check added there and not here fails.
documented=$(grep 'hp-selfcheck' "$HP_DOCS/architecture.md" \
  | sed -n 's/.*[^0-9]\([0-9][0-9]*\) checks.*/\1/p' | head -n 1)
t_ne "docs/architecture.md states how many checks hp-selfcheck runs" "" "$documented"
t_eq "hp-selfcheck ships the number of checks architecture.md states" \
  "$documented" "$listed"

t_selfcheck --root "$HP_REPO" --only nosuchcheck
t_status "a check name that does not exist is a usage error" 2
t_stderr_has "it lists the checks that do exist" "agent-name"

# ---------------------------------------------------------------------------
# 2. The copy. docs/ and plugins/ are everything hp-selfcheck reads.

mkdir -p "$COPY"
cp -R "$HP_DOCS" "$COPY/docs"
cp -R "$HP_REPO/plugins" "$COPY/plugins"

t_selfcheck --root "$COPY"
t_status "the copy passes before anything is planted" 0

# ---------------------------------------------------------------------------
# 3. An agent frontmatter name carrying the plugin prefix.
#
# The frontmatter name is bare. The plugin supplies the namespace. A prefixed name
# resolves to nothing, so every dispatch to that agent fails at run time.

AGENT=plugins/hyperpower/agents/builder.md
plant "$AGENT"
"$HP_PYTHON" - "$COPY/$AGENT" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    text = handle.read()
with open(path, "w", encoding="utf-8") as handle:
    handle.write(text.replace("name: builder", "name: hyperpower-builder", 1))
PY

t_selfcheck --root "$COPY" --only agent-name
t_status "a prefixed agent name fails the agent-name check" 1
t_stdout_has "the finding names the file it is in" "agents/builder.md"
t_stdout_has "the finding says the name is bare" "bare"
restore "$AGENT"

t_selfcheck --root "$COPY" --only agent-name
t_status "restoring the name clears the finding" 0

# ---------------------------------------------------------------------------
# 4. A placeholder marker left in the tree.
#
# The marker is built at run time from two halves. Writing it as one literal would put it
# in this file, and hp-selfcheck reads this file too, so the check would fail before
# anything was planted.

MARKER=$(printf 'TO%s' 'DO')
plant "$AGENT"
printf '\n%s: finish this later\n' "$MARKER" >> "$COPY/$AGENT"

t_selfcheck --root "$COPY" --only slop-markers
t_status "a placeholder marker fails the slop-markers check" 1
t_stdout_has "the finding names the marker it found" "$MARKER"
restore "$AGENT"

# ---------------------------------------------------------------------------
# 5. A task class in the routing table and not in the schemas.
#
# Three files hold one vocabulary. A class in one of them kills the run at its second
# stage, when the planner copies a class the plan schema does not allow.

TABLE=plugins/hyperpower/task-classes.yml
plant "$TABLE"
"$HP_PYTHON" - "$COPY/$TABLE" <<'PY'
import sys

added = (
    "classes:\n"
    "  hotfix:\n"
    "    stages: [build]\n"
    "    tiers: { build: mechanical }\n"
    "    recognise: a class the schemas never heard of\n"
    "    not_this_class: anything the schemas do know\n"
    "    waits_for_human: false\n"
)
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    text = handle.read()
with open(path, "w", encoding="utf-8") as handle:
    handle.write(text.replace("classes:\n", added, 1))
PY

t_selfcheck --root "$COPY" --only task-classes
t_status "a class the schemas do not name fails the task-classes check" 1
t_stdout_has "the finding names the route schema" "route.json"
t_stdout_has "the finding names the plan schema" "plan.json"
t_stdout_has "the finding names the class that drifted" "hotfix"
restore "$TABLE"

# ---------------------------------------------------------------------------
# 6. A gate script with no entry in the config schema.
#
# hp-gates runs the gates the config lists. A script the schema does not name never runs,
# so it reports nothing and blocks nothing.

cp "$COPY/plugins/hyperpower/gates/lint.sh" "$COPY/plugins/hyperpower/gates/orphan.sh"
chmod +x "$COPY/plugins/hyperpower/gates/orphan.sh"

t_selfcheck --root "$COPY" --only gate-orphan
t_status "a gate script with no schema entry fails the gate-orphan check" 1
t_stdout_has "the finding names the orphaned script" "orphan"
rm -f "$COPY/plugins/hyperpower/gates/orphan.sh"

t_selfcheck --root "$COPY"
t_status "the copy passes again once every fault is removed" 0
