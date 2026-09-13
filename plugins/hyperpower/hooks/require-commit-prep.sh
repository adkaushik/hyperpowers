#!/usr/bin/env sh
#
# hyperpower commit gate. PreToolUse on Bash. OFF BY DEFAULT.
#
# Blocks a bare `git commit` until the change has been through the harness.
# It does nothing at all unless an opt-in flag file exists:
#
#   <repo>/.hyperpower/commit-gate                        this repo
#   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hyperpower-commit-gate   every repo
#
# Bypass one commit by prefixing the command with HYPERPOWER_COMMIT_GATE=off.
#
# Exit 0 allows. Exit 2 with a deny payload blocks. Every failure path exits 0,
# so a broken hook never traps a commit.
#
# Pure POSIX sh. jq is used when present and is not required.

payload=$(cat 2>/dev/null) || payload=""

# ------------------------------------------------------------- locate --------

project_root=${CLAUDE_PROJECT_DIR:-}

if [ -z "$project_root" ]; then
    project_root=$(git rev-parse --show-toplevel 2>/dev/null) || project_root=""
fi

if [ -z "$project_root" ]; then
    project_root=$PWD
fi

# --------------------------------------------------------- opt-in check -----

claude_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
repo_flag="$project_root/.hyperpower/commit-gate"
machine_flag="$claude_dir/hyperpower-commit-gate"

if [ ! -f "$repo_flag" ] && [ ! -f "$machine_flag" ]; then
    exit 0
fi

# ----------------------------------------------------- extract command -------

command_text=""

if command -v jq >/dev/null 2>&1; then
    command_text=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
fi

# No jq. Cut everything up to the last "command":" and drop the trailing quote
# and whatever follows it. Basic regular expressions only, so BSD sed and GNU sed
# both handle it.
if [ -z "$command_text" ]; then
    command_text=$(
        printf '%s' "$payload" |
            tr -d '\n' |
            sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"//p' |
            sed 's/"[^"]*$//' |
            head -n 1
    )
fi

# Last resort: match against the whole payload rather than block on a parse miss.
if [ -z "$command_text" ]; then
    command_text=$payload
fi

if [ -z "$command_text" ]; then
    exit 0
fi

# --------------------------------------------------------- match commit -----

# Matches `git commit`, `git -C /path commit`, `cd x && git commit`, and an env
# prefix such as `GIT_AUTHOR_NAME=x git commit`. It does not match `git log`.
git_commit_re='(^|[;&|(])[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(env[[:space:]]+)?git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)'

printf '%s' "$command_text" | grep -Eq "$git_commit_re" || exit 0

# Explicit one-commit bypass. It has to sit in command position, so the same token
# inside a commit message does not open the gate.
bypass_re='(^|[;&|(])[[:space:]]*(env[[:space:]]+)?HYPERPOWER_COMMIT_GATE=(off|0|false)([[:space:]]|$)'

printf '%s' "$command_text" | grep -Eq "$bypass_re" && exit 0

# ---------------------------------------------------------------- deny -------

# Reasons are literal text written here. No path and no user data is interpolated
# into them, so nothing in a reason ever needs JSON escaping.
deny() {
    _reason="hyperpower commit gate: $1 Run the change through the harness, or prefix this command with HYPERPOWER_COMMIT_GATE=off to commit once without it. Delete .hyperpower/commit-gate to turn the gate off for good."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"},"systemMessage":"%s"}\n' \
        "$_reason" "$_reason"
    printf '%s\n' "$_reason" >&2
    exit 2
}

# ------------------------------------------------------------- evidence ------

# The flag stays at .hyperpower, so the opt-in check above never starts Python. The run
# journal follows paths.state, so it is resolved only once the gate is on for a commit.
state_dir=""
plugin_root=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)
if [ -n "$plugin_root" ] && command -v python3 >/dev/null 2>&1; then
    state_dir=$(python3 "$plugin_root/scripts/hp-config" --root "$project_root" --state-dir 2>/dev/null) || state_dir=""
fi
[ -n "$state_dir" ] || state_dir="$project_root/.hyperpower"
runs_dir="$state_dir/runs"

[ -d "$runs_dir" ] || deny "no run journal in the state directory."

run_id=$(ls -1t "$runs_dir" 2>/dev/null | head -n 1)
[ -n "$run_id" ] || deny "the run journal is empty."
[ -d "$runs_dir/$run_id" ] || deny "the newest run journal entry is not a run folder."

gates_file="$runs_dir/$run_id/gates.json"
[ -f "$gates_file" ] || deny "the newest run did not reach the Gates stage."

if grep -Eq '"result"[[:space:]]*:[[:space:]]*"fail"' "$gates_file" 2>/dev/null; then
    deny "the newest run recorded a failing gate."
fi

# A gate that did not run is not a pass. A run in which nothing passed verified nothing.
if ! grep -Eq '"result"[[:space:]]*:[[:space:]]*"pass"' "$gates_file" 2>/dev/null; then
    deny "the newest run recorded no passing gate, so nothing was verified."
fi

# did_not_run covers two cases. A gate turned off in config is intended. A missing tool or a
# timeout is not, and it never counts as a pass. Both detail strings come from gates/_lib.sh.
if grep -Eq '"blocking_unverified"[[:space:]]*:[[:space:]]*\[[[:space:]]*"' "$gates_file" 2>/dev/null; then
    deny "a blocking gate in the newest run could not execute, so its check never happened."
fi

# Any change made after the gates ran is unverified. Staged files first, then the
# working tree, which covers `git commit -a`.
changed=$(git -C "$project_root" -c core.quotepath=false diff --cached --name-only 2>/dev/null)
if [ -z "$changed" ]; then
    changed=$(git -C "$project_root" -c core.quotepath=false diff --name-only HEAD 2>/dev/null)
fi

stale=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    path="$project_root/$file"
    [ -e "$path" ] || continue
    if [ -n "$(find "$path" -newer "$gates_file" -print 2>/dev/null)" ]; then
        stale=$((stale + 1))
    fi
done <<CHANGED
$changed
CHANGED

if [ "$stale" -gt 0 ]; then
    deny "files changed after the Gates stage ran, so the gate result is stale."
fi

exit 0
