# hooks

Two hooks, wired in `hooks.json`. Session start is always on. The commit gate does nothing
until you create a flag file.

| File | Event | Matcher | Timeout | Default |
|---|---|---|---|---|
| `session-start.sh` | SessionStart | `startup\|resume\|clear\|compact` | 10s | on |
| `require-commit-prep.sh` | PreToolUse | `Bash` | 5s | inert |

Both are POSIX `sh`. Both exit 0 on every failure path. A broken hook never blocks a
session and never traps a commit.

## session-start.sh

Injects the harness protocol into the main agent once per session. Runs in about 3 ms.

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

Two config fields are read and no others: `voice.adhd_shaping` and `voice.plain_english`.
A flag that is absent defaults to `true`. Only the literal value `false` turns a flag off.

### Two branches

| Config state | What gets injected |
|---|---|
| Neither config file exists | one line: run `/hyperpower:init` |
| Either config file exists | the full protocol |

The harness does not guess a config. With no config it says one line and stops. It does not
infer the stack, the gates, or the commands.

### What the protocol says

| Section | Content |
|---|---|
| SCOPE | binds the main agent in this session only |
| PIPELINE | Route, Understand, Plan, Design, Build, Gates, Review, Fix loop, Render |
| GATES | fail closed. Exit 0 pass, non-zero fail, 78 could-not-run |
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
| `.hyperpower/runs/` exists and is not empty | no run journal |
| Newest run folder holds `gates.json` | the run did not reach the Gates stage |
| `gates.json` records no `"result": "fail"` | the run recorded a failing gate |
| `gates.json` records at least one `"result": "pass"` | nothing was verified |
| No `"result": "did_not_run"` blames a missing tool or a timeout | a gate could not execute |
| No changed file is newer than `gates.json` | the gate result is stale |

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
