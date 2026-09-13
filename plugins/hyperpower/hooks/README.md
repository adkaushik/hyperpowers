# hooks

Three hooks, wired in `hooks.json`. Session start is always on. The co-passenger speaks only
while an app is in co-passenger mode. The commit gate does nothing until you create a flag
file.

| File | Event | Matcher | Timeout | Default |
|---|---|---|---|---|
| `session-start.sh` | SessionStart | `startup\|resume\|clear\|compact` | 10s | on |
| `require-commit-prep.sh` | PreToolUse | `Bash` | 5s | inert |
| `copassenger.py` | Stop | none | 10s | silent outside co-passenger mode |

The two shell hooks are POSIX `sh`. `copassenger.py` is Python 3, standard library only.
All three exit 0 on every failure path. A broken hook never blocks a session, never traps a
commit, and never stops a turn from ending.

## session-start.sh

Injects the harness protocol into the main agent once per session. Takes about 80 ms, most
of it Python starting up to check for an app in progress.

Output goes out as a SessionStart payload on `hookSpecificOutput.additionalContext` when
`jq` is on PATH. Without `jq` it prints the protocol as plain stdout, which Claude Code
also treats as additional context. Both paths reach the model. `jq` is not required.

### What it reads

| Source | Used for |
|---|---|
| `CLAUDE_PROJECT_DIR` | project root. Falls back to `git rev-parse --show-toplevel`, then `$PWD` |
| `hyperpower.yml` | whether the harness is configured, and the `voice.*` flags |
| `hyperpower.local.yml` | the same fields, overriding the committed file field by field |
| `CODEBASE_RULEBOOK.md` | presence only. The hook never reads its contents |
| `hp-app note` | a paragraph about the app in progress, or nothing |

Two config fields are read and no others: `voice.adhd_shaping` and `voice.plain_english`.
A flag that is absent defaults to `true`. Only the literal value `false` turns a flag off.

### Two branches

| Config state | What gets injected |
|---|---|
| Neither config file exists | one line: run `/hyperpower:build`, which sets the repo up |
| Either config file exists | the full protocol |

The hook does not guess a config. With no config it says one line and stops. It does not
infer the stack, the gates, or the commands. `build` does that, with the user watching.

### An app in progress

`/hyperpower:build` records an app in `app.json`, in the state directory. When one exists,
both branches end with the paragraph `hp-app note` prints: the app, how many features are
done, the current feature and its phase, and an instruction not to resume until the user
asks.

A session opened mid-app says where it stopped. Nobody has to remember a command.

No app, no `python3`, or any error: the paragraph is empty and the rest is unchanged.

### What the protocol says

| Section | Content |
|---|---|
| SCOPE | binds the main agent in this session only |
| PIPELINE | Route, Understand, Plan, Design, Build, Gates, Review, Fix loop, Render |
| GATES | fail closed. Exit 0 pass, non-zero fail, 78 could-not-run |
| CONDUCTOR | `/hyperpower:build` is the entry point. Offer it in one line. Do not recite commands |
| RULEBOOK | read `CODEBASE_RULEBOOK.md` before any code change |
| ASSUMPTIONS | every stage declares them; `declared -> verified \| refuted \| unresolved` |
| NAMES | address every agent and command as `hyperpower:<name>` |
| RENDER | ADHD shaping and plain voice, each gated on its `voice.*` flag |

The protocol is for the main agent. A subagent you spawn does not re-run this hook and does
not inherit the injected text. Copy any rule a subagent needs into that subagent's prompt.

The RENDER section changes with config. Both flags false produces one line saying no
shaping is in force, rather than an empty section.

### Test it

```
CLAUDE_PROJECT_DIR="$PWD" sh plugins/hyperpower/hooks/session-start.sh
```

## copassenger.py

After a turn that changed files, it adds one line about what to check next. It runs only
while `/hyperpower:build` has an app in co-passenger mode, where the human writes the code.

### When it speaks

Every row must hold. The first one that fails ends the hook with no output.

| Condition | Why |
|---|---|
| `stop_hook_active` is false | loop guard |
| `app.json` in the state directory says `mode: copassenger` | in conductor mode, the conductor is already talking |
| files are changed or untracked, outside the state directory | its own memo is not work |
| the changes are new since the last turn, or the turn claims done | a turn that changed nothing gets silence |
| one of the signals below matched | most turns match none |
| the line differs from the last one it said for the same changes | it never repeats itself |

### What it says

One line. Highest priority first.

| Signal | Points at |
|---|---|
| the last message claims done: `done`, `implemented`, `should work`, `ready to ship` and similar | `/hyperpower:review` |
| a path under `migrations`, `models` or `schema` | `/hyperpower:council` with the backend pair |
| a lockfile or manifest: `package.json`, `go.mod`, `Cargo.toml` and the rest | `/hyperpower:janitor` |
| five or more files | `/hyperpower:humanize` |
| a `.tsx`, `.jsx`, `.vue` or `.svelte` file | `/hyperpower:humanize` |

The claim of done outranks everything. A turn that says done when it is not is the case this
hook exists for.

Changes are fingerprinted from `git diff HEAD --stat`, the changed file names, and their
mtimes. The last fingerprint and the last line said are kept in `copassenger.json`, in the
state directory.

### What it never does

1. It never emits `decision: "block"`. That forces the agent to keep working, which is the
   driver's call, not the passenger's.
2. It never runs a command. It names one. The human decides.
3. It never raises. Every failure exits 0 with no output.

It emits a top-level `systemMessage`, which shows the user one line and lets the turn end.
It takes about 75 ms.

### Test it

Silence has two causes: nothing to say, or a crash. `HYPERPOWER_HOOK_DEBUG=1` re-raises, so
a crash prints a traceback instead of passing for silence.

```
printf '{"cwd":"%s","stop_hook_active":false,"last_assistant_message":"done"}' "$PWD" |
  HYPERPOWER_HOOK_DEBUG=1 python3 plugins/hyperpower/hooks/copassenger.py
```

It says something only with an app in co-passenger mode and a changed file. Output
`{"systemMessage": ...}` means it spoke. No output and exit 0 means a row in the first
table did not hold.

## require-commit-prep.sh

Blocks a bare `git commit` until the change has been through the harness. Off by default.

### Turn it on

```
mkdir -p .hyperpower && touch .hyperpower/commit-gate
```

Commit that file to turn the gate on for everyone on the repo. Add it to `.gitignore`
instead to keep it yours.

| Flag file | Scope |
|---|---|
| `<repo>/.hyperpower/commit-gate` | this repo |
| `${CLAUDE_CONFIG_DIR:-~/.claude}/hyperpower-commit-gate` | every repo on this machine |

Either flag enables the gate. With neither flag present the hook exits 0 on its first check
and reads nothing else.

### What it checks

Checks run in order. The first one that fails denies the commit.

| Check | Deny reason |
|---|---|
| `runs/` in the state directory exists and is not empty | no run journal |
| Newest run folder holds `gates.json` | the run did not reach the Gates stage |
| `gates.json` records no `"result": "fail"` | the run recorded a failing gate |
| `gates.json` records at least one `"result": "pass"` | nothing was verified |
| No `"result": "did_not_run"` blames a missing tool or a timeout | a gate could not execute |
| No changed file is newer than `gates.json` | the gate result is stale |

The run journal is found with `hp-config --state-dir`, so `paths.state` moves it. The flag
file stays at `.hyperpower/commit-gate` either way, so the opt-in check never starts Python.

A `did_not_run` gate is never counted as a pass. A gate turned off in config is intended and
does not deny. A gate whose tool is off PATH, or which exceeded
`limits.gate_timeout_seconds`, denies.

Changed files come from `git diff --cached --name-only`, falling back to
`git diff --name-only HEAD` so that `git commit -a` is covered.

A deny prints a `permissionDecision: deny` payload on stdout, the reason on stderr, and
exits 2. Every allow path exits 0 and prints nothing.

### Bypass, and turn it off

| Goal | Command |
|---|---|
| Commit once without the gate | prefix the command with `HYPERPOWER_COMMIT_GATE=off` |
| Turn it off for this repo | `rm .hyperpower/commit-gate` |
| Turn it off for this machine | `rm ~/.claude/hyperpower-commit-gate` |

### Limits, stated plainly

1. It matches `git commit` in the Bash tool command string. A script that commits, or a
   base64-wrapped command, walks past it. This is a speed bump for the agent, not a
   security control.
2. It fails open. If the payload cannot be parsed, or the directory is not a git repo, the
   hook exits 0 and the commit proceeds.
3. It does not read the diff, the commit message, or the staged content. Gate evidence is
   the only thing it judges.
4. It picks the newest run folder by modification time. It does not verify that the run was
   about these files.

### Test it

```
printf '{"tool_input":{"command":"git commit -m x"}}' |
  CLAUDE_PROJECT_DIR="$PWD" sh plugins/hyperpower/hooks/require-commit-prep.sh
echo "exit=$?"
```

Exit 0 means allow. Exit 2 means deny, and the reason is on stderr.

## hooks.json

Paths use `${CLAUDE_PLUGIN_ROOT}`, so the plugin works from any install location. Do not
hardcode a path. Do not raise the SessionStart timeout to cover a slow script; the hook has
to stay fast enough that a session start never waits on it.

The Stop command checks for `python3` before it runs the co-passenger. Without that check,
a machine with no Python would show a hook error at the end of every turn.
