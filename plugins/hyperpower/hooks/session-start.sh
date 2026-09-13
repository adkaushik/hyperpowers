#!/usr/bin/env sh
#
# hyperpower SessionStart hook.
#
# Injects the harness protocol into the main agent at session start. Emits a
# SessionStart payload through hookSpecificOutput.additionalContext when jq is
# on PATH, and plain stdout when it is not. Claude Code treats SessionStart
# stdout as additional context, so both paths reach the model.
#
# Exits 0 on every path. A session never fails to start because of this hook.
#
# Pure POSIX sh. No bash builtins, no jq dependency, no network.

# ---------------------------------------------------------------- emit -------

emit() {
    _text=$1
    _payload=""

    if command -v jq >/dev/null 2>&1; then
        _payload=$(
            printf '%s' "$_text" | jq -Rs \
                '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}' \
                2>/dev/null
        )
    fi

    if [ -n "$_payload" ]; then
        printf '%s\n' "$_payload"
    else
        printf '%s\n' "$_text"
    fi

    exit 0
}

# ------------------------------------------------------------- locate --------

project_root=${CLAUDE_PROJECT_DIR:-}

if [ -z "$project_root" ]; then
    project_root=$(git rev-parse --show-toplevel 2>/dev/null) || project_root=""
fi

if [ -z "$project_root" ]; then
    project_root=$PWD
fi

config="$project_root/hyperpower.yml"
local_config="$project_root/hyperpower.local.yml"
rulebook="$project_root/CODEBASE_RULEBOOK.md"

# An app recorded by /hyperpower:build rides along with whichever branch emits, so a session
# opened mid-app says so without anyone having to remember a command. hp-app prints nothing
# when no app is recorded, and any failure here leaves the note empty.
app_note=""
plugin_root=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)
if [ -n "$plugin_root" ] && command -v python3 >/dev/null 2>&1; then
    app_note=$(python3 "$plugin_root/scripts/hp-app" --root "$project_root" note 2>/dev/null)
fi

# ------------------------------------------------------ no config branch -----

# The harness does not guess. With no config, say one line and stop.
if [ ! -f "$config" ] && [ ! -f "$local_config" ]; then
    emit "hyperpower is installed, but $project_root has no hyperpower.yml yet. Run /hyperpower:build to start: it sets the repo up itself, then asks what you want to build. /hyperpower:init still works for setup on its own.${app_note:+

$app_note}"
fi

# --------------------------------------------------------- read config -------

# Read one key from the top-level voice: block. Prints nothing when the file or
# the key is absent. Only voice.adhd_shaping and voice.plain_english are read.
read_voice_flag() {
    [ -f "$1" ] || return 0
    awk -v key="$2" '
        /^[^[:space:]#]/ { invoice = ($0 ~ /^voice:/) ? 1 : 0; next }
        invoice == 1 {
            line = $0
            sub(/#.*/, "", line)
            if (line ~ ("^[[:space:]]+" key "[[:space:]]*:")) {
                sub(/^[^:]*:[[:space:]]*/, "", line)
                gsub(/[[:space:]]/, "", line)
                if (line != "") { print line; exit }
            }
        }
    ' "$1" 2>/dev/null
}

# hyperpower.local.yml overrides hyperpower.yml, field by field.
adhd_shaping=$(read_voice_flag "$local_config" adhd_shaping)
[ -n "$adhd_shaping" ] || adhd_shaping=$(read_voice_flag "$config" adhd_shaping)
[ -n "$adhd_shaping" ] || adhd_shaping=true

plain_english=$(read_voice_flag "$local_config" plain_english)
[ -n "$plain_english" ] || plain_english=$(read_voice_flag "$config" plain_english)
[ -n "$plain_english" ] || plain_english=true

config_source=""
[ -f "$config" ] && config_source="hyperpower.yml"
if [ -f "$local_config" ]; then
    if [ -n "$config_source" ]; then
        config_source="$config_source, hyperpower.local.yml"
    else
        config_source="hyperpower.local.yml"
    fi
fi

# ------------------------------------------------------- build sections ------

rulebook_note=""
if [ ! -f "$rulebook" ]; then
    rulebook_note="
CODEBASE_RULEBOOK.md does not exist at this root. Run /hyperpower:init --refresh to
generate it. Until it exists, say in your output that no rulebook was available. Do not
invent one."
fi

render_section="RENDER
voice.adhd_shaping and voice.plain_english are both false. No render shaping is in force.
Write plainly anyway."

if [ "$adhd_shaping" != "false" ] || [ "$plain_english" != "false" ]; then
    render_section="RENDER
Render is the one boundary where machine output becomes human output. The rules below
apply there and nowhere else. Do not apply them inside agent-to-agent handoffs, subagent
prompts, or findings lists that have not reached the boundary. Applying them earlier
silently drops findings."

    if [ "$adhd_shaping" != "false" ]; then
        render_section="$render_section

Shape, because voice.adhd_shaping is true: lead with the action, number multi-step work,
restate current state, suppress tangents, give specific time estimates, make wins visible,
stay matter-of-fact on errors, no preamble and no recap and no closing pleasantry.
Rank, never cap. Show the top five, then say how many remain. The full ranked list stays
in the contract."
    fi

    if [ "$plain_english" != "false" ]; then
        render_section="$render_section

Voice, because voice.plain_english is true: short sentences, subject-verb-object. No
idioms, no metaphors, no wordplay, no rhetorical build-up, no rhetorical questions.
Technical terms stay exact. State cause and fix for every error."
    fi
fi

# ------------------------------------------------------------ protocol -------

# Built as a double-quoted string, not a heredoc. A heredoc inside a command
# substitution breaks in bash when the body holds an unpaired apostrophe.
protocol="hyperpower harness active. Root: $project_root. Config: $config_source.

SCOPE
This protocol binds the main agent in this session only. It is injected once, at session
start. A subagent you spawn never receives it and never re-runs this hook. Copy any rule a
subagent needs into that subagent's prompt. Do not assume a subagent knows the pipeline,
the gates, the assumption format, or the render rules.

PIPELINE
Route -> Understand -> Plan -> Design -> Build -> Gates -> Review -> Fix loop -> Render

Design runs for UI work only. Skip a stage that does not apply; a one-file change with a
rulebook precedent runs Understand, Build, Gates, Review. Never reorder the stages that do
run. Never run Build before Understand. Never run Review before Gates. The fix loop is
bounded at five rounds: rounds 1-3 resume the same builder, rounds 4-5 use a fresh builder
one model tier up. Round 5 failing is a hard stop that reports. Do not start a sixth round.

GATES
Gates execute commands from hyperpower.yml and read exit codes. No model judgment.
Exit 0 is pass. Non-zero is fail. Exit 78 is could-not-run.
Gates fail closed. A gate that cannot execute reports that it did not run.
Never report a pass you did not verify. Never call a skipped gate passed. Never treat a
missing tool as a pass. A gate marked blocking: false reports a warning and does not stop
the run.

CONDUCTOR
The entry point is /hyperpower:build. It sets the repo up, takes over an existing app or
starts a new one, and pulls in the commands below without the user naming them. When the
user describes something to build and names no command, offer /hyperpower:build in one
line. Do not recite the command list. /hyperpower:help does that when asked.

RULEBOOK
Read CODEBASE_RULEBOOK.md at the repo root before any code change. It holds this repo's
conventions, patterns, banned APIs, and test layout. It is capped, so every rule in it
displaced another rule to get there.
If the rulebook contradicts your plan, follow the rulebook. If the rulebook contradicts
code you can read, report the conflict once, then follow the rulebook until the human
decides. Do not edit a file in paths.source before you have read the rulebook.$rulebook_note

ASSUMPTIONS
Every stage records what it assumed. Nothing waits on a human.
Fields: id, claim, source (rulebook | inferred | asked), confidence, declared_at,
checkable, status. Status moves declared -> verified | refuted | unresolved.
Declare an assumption the moment you infer something you did not read. Point checkable at
the file that would settle it, so a mechanical pass can stamp the status at gate time.
Do not delete a refuted assumption. Refuted is the highest-value output this harness
produces. An undeclared assumption is the failure it exists to catch.

NAMES
Everything is namespaced hyperpower:. Commands are /hyperpower:build, /hyperpower:review,
/hyperpower:scout. Agents are hyperpower:reviewer, hyperpower:skeptic, and the rest.
Never spawn an agent by a bare name. A bare name does one of two things: it fails to
resolve, or it silently resolves to a same-named agent in the user's own ~/.claude/agents/.
That agent has different instructions, does not know this protocol, and returns a contract
this pipeline cannot use. The second failure is silent, so the run will look correct.

$render_section${app_note:+

$app_note}"

emit "$protocol"
