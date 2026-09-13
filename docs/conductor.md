# The conductor — design

Date: 2026-09-13
Status: built

## Why this exists

hyperpower grew to twenty-six commands, each good, and became hard to use. Every request
added a command; none reduced what a person has to know. The user fell back to Superpowers
brainstorming and Anthropic's feature-dev, which win on one property: **one entry point
that conducts**, asking at the moments a human is needed and pulling in the right capability
without being told its name.

hyperpower already has more of the right machinery than either — gates that execute, a run
journal, assumptions checked against code, twelve opposed voices, PR review, slop detection.
The conductor is not new capability. It is new access to capability that already works.

## Decisions

| Question | Decision |
|---|---|
| Scope | both a single feature and a whole app across sessions |
| Mode | conductor drives; co-passenger rides along while the human drives |
| Setup | none. `/hyperpower:build` sets itself up inline |
| Starting state | new, take over an existing app, or resume |
| Co-passenger presence | one line after substantial work, silence on trivial turns |
| Checkpoints | scaled: trivial none, feature two, app two per feature plus one up front |
| State | on disk, JSON, because an app outlives a session and a hook cannot read a chat |
| Reports | visualize runs after every feature or app step, stored, offered in one line |

## 1. Intake

One command, three forms:

```
/hyperpower:build "a habit tracker with streaks"     new
/hyperpower:build                                    take over the app I am in
/hyperpower:build --takeover                         the same, explicit
```

**Step 0 — set up.** No `hyperpower.yml`: run what `init` does, inline, and say what was
detected in three lines. `init` remains for anyone who wants it separately.

**Step 1 — starting state**, first match wins:

| Found | Action |
|---|---|
| `app.json` in the state directory | resume: say where it left off, ask before continuing |
| code, no `app.json` | take over: reconstruct the picture, confirm it |
| empty repo | new app: agree the feature list first |
| one-file change | trivial: do it, report, no stops |

**Step 2 — scope and mode.** Inferred from the request. Ambiguous on either: one
multiple-choice question with the best guess marked. Never two.

**Take over** reads routes, components, models and tests and drafts the state: what is
built, what is half-done (placeholders, stubs, disabled paths), and the stack. One stop to
confirm it. Building on a wrong picture of the user's own app is the expensive mistake.

**Discoverable.** The first run ends with the whole interface — four phrases:
`take over`, `I'll drive`, `what's next?`, `stop`. Everything else is offered when relevant.

**Predictable.** It states what it detected and what it will do before anything costly.
The same repo produces the same picture.

## 2. Conductor flow

The phases reuse the existing pipeline. The conductor adds the conversation around it.

| Phase | Capability used | Stops? |
|---|---|---|
| Discovery | `route` | feature and app: confirms understanding |
| Explore | `mapper` agent | no |
| Clarify | new: edge cases, errors, integration points | only when something is genuinely unspecified |
| Approach | `planner`, and `council` when the choice is expensive | **yes — offers two or three, recommends one** |
| Build | `builder` agent, test first | no |
| Verify | gates, `review`, `humanize` | **yes — "fix now, later, or ship as is?"** |
| Report | `render`, `why`, `visualize` | offers the report, does not stop |

Checkpoints scale with the work:

| Work | Stops |
|---|---|
| trivial | none |
| feature | two: approach and verify |
| app | one up front to agree the feature list and order, then two per feature |

## 3. State

Truth lives in `<state>/app.json`. `<state>/app.md` is a rendered view for people. The
state directory is `paths.state`, `.hyperpower` by default.

JSON rather than YAML because the feature list is a list of maps and `hp-config`'s
hand-rolled YAML parser does not support one. Every read is stdlib `json`.

```json
{
  "version": 1,
  "name": "habit-tracker",
  "scope": "app",
  "mode": "conductor",
  "origin": "new",
  "stack": ["next.js", "django"],
  "current": "f2",
  "features": [
    {"id": "f1", "name": "auth", "status": "done", "phase": null,
     "run_id": "4f2a", "report": ".hyperpower/reports/f1-auth.html"},
    {"id": "f2", "name": "reminders", "status": "active", "phase": "build",
     "run_id": null, "report": null}
  ],
  "reconciled_head": "a3f19c2",
  "created_at": "2026-09-13T10:00:00Z",
  "updated_at": "2026-09-13T11:20:00Z"
}
```

`status` is `planned`, `active`, `done`, `half-done` or `dropped`. `phase` is null unless the
feature is active.

**Drift.** The file can disagree with the code when the human builds outside the conductor.
`reconciled_head` records the commit the state was last checked against. On resume, commits
since then are listed and any feature whose files changed is flagged before the conductor
trusts its own record.

`scripts/hp-app` owns every write. Writes go to a temp file and rename, so the hook never
reads a half-written state.

## 4. Co-passenger

A `Stop` hook, `hooks/copassenger.py`. It fires when the agent finishes a turn.

**It only speaks when `app.json` says `mode: copassenger`.** In conductor mode the conductor
is already driving and a second voice is noise. With no `app.json`, it is silent. Switching
mode rewrites the field and the hook follows.

**It never blocks.** It emits `systemMessage`, which shows the user a line and lets the turn
end. It never emits `decision: "block"`, which would force the agent to keep working. It
exits 0 on any error — a hook that breaks the session is worse than one that says nothing.
It respects `stop_hook_active` as a loop guard even though it never blocks.

**Real work, detected mechanically.** A fingerprint of changed and untracked files is
compared with the last one seen. No change and no claim of completion: silence.

**One line, highest priority first:**

| Signal | Suggestion |
|---|---|
| the turn claims done, and files changed | review before trusting it |
| migrations, models or schema touched | the backend pair |
| a lockfile or manifest touched | `janitor` |
| five or more files changed | `humanize` |
| components or screens touched | `humanize` |

The same suggestion is never repeated for the same fingerprint.

The first signal is the one that matters most. It is the "it said done and it was not" case
that prompted this whole design.

## 5. Reports, errors, testing

**Reports.** After a feature or an app step completes, the conductor runs `hp-visualize`
to a stable path, `<state>/reports/<feature-id>-<name>.html`, records the path on the
feature in `app.json`, and offers it in one line. Trivial work gets no report.

**Errors.**

- A phase that cannot proceed says why and what would fix it, and stops. It does not guess.
- A blocking gate at `did_not_run` is not a pass. The verify checkpoint says so.
- Drift is reported before it is acted on, never silently reconciled.
- The hook never raises.

**Testing.**

- `tests/cases/hp-app.sh`: every subcommand and exit code, atomic writes, drift against a
  moved HEAD, `paths.state`, and the note session start injects.
- `tests/cases/copassenger.sh`: fed fake Stop payloads — silent on no change, silent in
  conductor mode, silent without `app.json`, the done claim wins priority, no repeat for
  the same fingerprint, its own memo is not work, never emits `decision`, exits 0 on
  garbage input.
- Every hook call in that case runs with `HYPERPOWER_HOOK_DEBUG=1`, which re-raises. A hook
  that swallows every exception passes a silence test while crashing on every turn. The
  first version of this one did exactly that.
- Selfcheck continues to enforce the help table and the command docs.

## Not in this

- A workflow script driving phases. Workflows run in the background, the opposite of a
  conductor that talks.
- Co-passenger acting on its own. It suggests. The human runs things.
- Migrating existing runs into an app. An app starts from `build`.
