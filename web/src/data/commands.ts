/**
 * Command reference, rendered by the docs section on the landing page.
 *
 * `brief` is the part people scan: how you call it, when you reach for it, what
 * lands when it finishes. `body` is markdown, written in a lighter voice for
 * the people who scroll past the table.
 *
 * Source of truth for behaviour is docs/commands.md in the plugin repo. When
 * that changes, this changes.
 */

export type CommandGroup =
  | 'Setup'
  | 'Run'
  | 'Memory'
  | 'Suggestors'
  | 'Analytics'
  | 'Quality'

export type CommandDoc = {
  slug: string
  name: string
  group: CommandGroup
  note: string
  invoke: string
  when: string
  expect: string
  body: string
}

export const COMMAND_GROUPS: Array<CommandGroup> = [
  'Setup',
  'Run',
  'Memory',
  'Suggestors',
  'Analytics',
  'Quality',
]

export const COMMAND_DOCS: Array<CommandDoc> = [
  {
    slug: 'build',
    name: '/hyperpower:build "<what to build>"',
    group: 'Setup',
    note: 'start here: a feature, a whole app, or take over one',
    invoke: '/hyperpower:build "a habit tracker with streaks"',
    when: 'Whenever you want something built. This is the command to learn first.',
    expect:
      'It sets the repo up if needed, works out where it is, and builds with you, stopping for the approach and for the verify result.',
    body: `
The other commands are still there, but you should rarely need to type them.
\`build\` calls each one when a step needs it.

The first time, it runs setup inline, reports what it found in three lines, and
carries on. After that it works out where it is:

| It finds | It does |
|---|---|
| a one-file change | makes it, runs the gates, and reports |
| an app it was already building | says where it stopped and asks before continuing |
| code, but no app on record | shows its picture of the app and asks you to correct it |
| an empty repo | proposes the features and the order to build them in |

It can drive or ride along. Driving, it builds one feature at a time and stops
for the approach and for the verify result. Riding along, you write the code,
and after a turn that changed files it adds one line about what to check. Say
"take over" or "I'll drive" to switch.

After each feature it writes a report of what every agent did, decided and
spent, and offers to open it.

If you close the session partway through an app, the next session says where
the app stopped and waits for you to ask before it continues.
`,
  },
  {
    slug: 'help',
    name: '/hyperpower:help',
    group: 'Setup',
    note: 'every command, grouped by when you need it',
    invoke: '/hyperpower:help [command] [--verbose] [--check]',
    when: 'You forgot the name of the thing you wanted. Happens weekly.',
    expect:
      'The full list grouped by when you would reach for it, opening with the three worth learning first.',
    body: `
Start here on day one and then forget it exists until you need it again.

The list is not grouped by how the plugin is built inside, it is grouped by the
moment you would actually want each command. Setting up a repo is one moment.
Driving a requirement is another. Digging through what happened last Tuesday is
a third.

Pass a fragment and it matches several:

\`\`\`
/hyperpower:help run
\`\`\`

\`--verbose\` prints every command with an example, which is a lot of screen but
useful once.

\`--check\` is the boring one. It compares the help table against the skills
actually on disk and reports drift. If a command exists with no help entry, or a
help entry points at a command that is gone, it says so instead of quietly
skipping it.
`,
  },
  {
    slug: 'init',
    name: '/hyperpower:init',
    group: 'Setup',
    note: 'set up this repo',
    invoke: '/hyperpower:init [--refresh] [--no-interview]',
    when:
      'To set a repo up without building anything. `/hyperpower:build` runs it for you the first time.',
    expect:
      'Stack detected, at most six questions, `hyperpower.yml` written, rulebook generated, every gate verified.',
    body: `
\`/hyperpower:build\` runs this for you the first time, so you only need it on its
own when you want a repo set up without building anything.

It looks at what you already have. Package manager, test runner, type checker,
build command, linter, the shape of your folders. Then it asks you at most six
questions about the things it could not figure out on its own, writes
\`hyperpower.yml\`, generates the rulebook from what it found, and runs every gate
once to confirm they actually execute.

Re-running it is safe. It reads the config that is already there and only fills
in the gaps, so you are not going to lose your settings by typing it twice.

\`--refresh\` regenerates the rulebook and leaves your config alone. Reach for
this when the codebase has moved on and the rules feel stale, which usually
shows up first as a rising gate failure rate in \`/hyperpower:usage\`.

\`--no-interview\` does detection only and skips the questions. Good for CI or
for a repo you are only poking at.

The config file is meant to be committed so your team shares it. If you need one
machine to differ, \`hyperpower.local.yml\` overrides it and stays gitignored.
`,
  },
  {
    slug: 'doctor',
    name: '/hyperpower:doctor',
    group: 'Setup',
    note: 're-verify gates and tools',
    invoke: '/hyperpower:doctor',
    when: 'After changing config, upgrading deps, or switching machines.',
    expect: 'A list of what is broken, each with the exact command that fixes it.',
    body: `
Something stopped working and you do not know what. Run this before you start
debugging by hand.

It re-verifies every gate and every tool the config points at, then reports what
is broken along with the fix. Not a vague "tsc not found" but the actual command
to run.

The common cases it catches: a dependency upgrade moved a binary, you switched
laptops and never installed something, or you edited \`hyperpower.yml\` and
pointed a gate at a script that does not exist.

Worth running right after \`/hyperpower:init\` on a machine you have not used
before.
`,
  },
  {
    slug: 'config',
    name: '/hyperpower:config',
    group: 'Setup',
    note: 'print the effective config',
    invoke: '/hyperpower:config',
    when: 'A setting is not doing what you think it is doing.',
    expect: 'Every field with the file each value came from.',
    body: `
Two config files merge into one, so the value that is actually in effect is not
always the value you last typed.

This prints the merged result field by field, and next to each one, where it came
from: \`hyperpower.yml\`, \`hyperpower.local.yml\`, or the built-in default. That
last column is the entire point of the command.

One thing that surprises people: a list is a single leaf. If your local file sets
a list, it replaces the committed list whole. It does not merge item by item.

The underlying script is \`hp-config\`, and a run records the config hash it
used, so what this prints is what the run actually saw.
`,
  },
  {
    slug: 'paths',
    name: '/hyperpower:paths',
    group: 'Setup',
    note: 'show or set editable directories',
    invoke: '/hyperpower:paths [dir ...]',
    when: 'You want the harness nowhere near certain folders.',
    expect: 'The current allowed list, or the new one after you pass directories.',
    body: `
With no arguments it shows which directories the harness is allowed to edit.

Pass a list and it changes:

\`\`\`
/hyperpower:paths src/ packages/core/src/
\`\`\`

Useful in a monorepo where you only want it touching one package, or in a repo
with generated code that should never be hand-edited by anyone including a
model.

Set this early. It is much easier than reviewing a diff that wandered into
\`vendor/\`.
`,
  },
  {
    slug: 'run',
    name: '/hyperpower:run "<requirement>"',
    group: 'Run',
    note: 'drive one requirement to the end',
    invoke: '/hyperpower:run "add rate limiting to the signup endpoint"',
    when: 'You have one requirement and you want it finished.',
    expect:
      'Route, understand, plan, design, build, gates, review, bounded fix loop, render. Around twelve minutes on a feature with a ten-file diff.',
    body: `
The main event. You hand it one requirement in plain language and it goes.

It opens a run journal under \`.hyperpower/runs/<run-id>/\` and moves through the
stages, validating each stage's output contract before the next stage is allowed
to read it. So a plan that came out malformed does not quietly become a build.

Design is the only stage that waits for you. Everything else either runs to
completion or stops hard.

Timing, roughly: twelve minutes for a \`feature\` class run with a ten-file diff,
ninety seconds for something \`trivial\`. Run \`/hyperpower:route\` first if you
want to know which one you are about to pay for.

One rule worth internalising: a blocking gate that could not run is a hard stop,
not a pass. If \`tsc\` is missing, the run does not shrug and continue. It stops
and tells you the tool is missing. This is the behaviour that makes the gate
result mean something.

Keep the requirement to one thing. "Add rate limiting to signup" works. "Add
rate limiting and also refactor the auth module and fix that flaky test" gives
you a worse plan and a diff nobody wants to review.
`,
  },
  {
    slug: 'route',
    name: '/hyperpower:route "<requirement>"',
    group: 'Run',
    note: 'print the stages it would run, and stop',
    invoke: '/hyperpower:route "add a settings screen"',
    when: 'Before a run you are not sure about. Costs nothing.',
    expect: 'The task class, the stages, and which of them will wait for you.',
    body: `
A dry run. It classifies the requirement, prints the stages, and stops. No run
folder, no tokens burned on the actual work.

\`\`\`
Route  ui-feature. The requirement adds a settings screen, which is rendered
       output a human reads.
       feature also fit. Picked ui-feature, the heavier one.
Stages understand, plan, design, build, gates, review, fix, render.
       Design waits for you.
\`\`\`

When two classes fit it picks the heavier one and names both, so you can see the
call it made and disagree with it.

Cheap habit to build: route first, then run. Takes a few seconds and you know
whether you are in for ninety seconds or twelve minutes.
`,
  },
  {
    slug: 'resume',
    name: '/hyperpower:resume <run-id> --from <step>',
    group: 'Run',
    note: 'replay from any step',
    invoke: '/hyperpower:resume 4f2a --from gates',
    when: 'A run stopped, you fixed the cause, you do not want to start over.',
    expect:
      'The step and everything downstream is invalidated, drift is reported, then it replays.',
    body: `
Runs stop. Sometimes it is a gate, sometimes it is you hitting the brakes. This
picks the run back up without redoing the parts that were fine.

Before it touches anything it re-hashes the working tree and tells you what moved
since each step:

\`\`\`
Resume run 4f2a from Gates.
  Understand   ok
  Plan         ok
  Build        DRIFTED — 3 files changed since this step
Re-run from Build instead? [build / gates-anyway / abort]
\`\`\`

That drift report matters. If you hand-edited files after the build step, the
build contract on disk no longer describes the code, and running gates against it
tells you nothing useful.

\`gates-anyway\` exists for the case where your own edit was the fix and you know
exactly what you changed. It is offered, never chosen for you.

\`latest\` works as a run id anywhere a run id is accepted, so you rarely need to
go look one up.
`,
  },
  {
    slug: 'why',
    name: '/hyperpower:why <run-id>',
    group: 'Run',
    note: 'what it decided and assumed',
    invoke: '/hyperpower:why 4f2a --assumptions',
    when: 'Reviewing a diff you did not write, or explaining one in standup.',
    expect: 'The decisions with reasons, and every assumption with its status.',
    body: `
The diff tells you what changed. This tells you why, which is the part that is
normally lost.

\`--assumptions\` lists every assumption the run made with a status: verified,
refuted, or unresolved.

Read the refuted list first. Those are the assumptions that turned out to be
wrong, on a run that shipped code anyway. If something in the diff looks odd,
the explanation is usually sitting in that list.

\`--rejected\` shows the options that were considered and dropped, with reasons.
Handy in review when someone asks why it did not do the obvious thing. Often it
considered the obvious thing and had a reason.

If an assumption is wrong and you want it fixed rather than just noted, that is
\`/hyperpower:correct\`.
`,
  },
  {
    slug: 'correct',
    name: '/hyperpower:correct <run> <step> <id> "<text>"',
    group: 'Run',
    note: 'correct a recorded assumption',
    invoke:
      '/hyperpower:correct 4f2a plan a1 "it returns { items: [] }" --scope run',
    when: '`/hyperpower:why` showed you an assumption that is plainly wrong.',
    expect:
      'The correction is recorded against that assumption and applied at the scope you picked.',
    body: `
You read the assumptions, one of them is wrong, you know the right answer. Say
it here instead of letting the same mistake repeat.

Scope decides how far it travels:

| Scope | Applies to |
|---|---|
| \`once\` | this replay only |
| \`run\` | every remaining step in this run |
| \`forever\` | promoted into the rulebook, with a diff for you to approve |

\`forever\` is the one with teeth. It goes into the rulebook and shapes future
runs, which is why it shows you a diff and waits for a yes rather than just
writing it.

If your correction contradicts code the harness can read, it says so once and
then does what you told it. You get one warning, not an argument.

Pair it with \`/hyperpower:resume\` when you want the corrected assumption to
actually change the output.
`,
  },
  {
    slug: 'decisions',
    name: '/hyperpower:decisions [query]',
    group: 'Memory',
    note: 'search the archive',
    invoke: '/hyperpower:decisions "auth" --by agent_autonomous',
    when: 'Someone asks why the code is like this and nobody remembers.',
    expect: 'Matching decision records with who made them and on what basis.',
    body: `
Every decision worth keeping gets written down by the archivist. This command is
the only thing that reads that archive back out. It is never loaded into context
automatically, which is why it can grow without slowing anything down.

\`--by\` filters on who decided:

| Value | Means |
|---|---|
| \`human\` | you decided |
| \`human_directed\` | you asked, it carried out |
| \`agent_autonomous\` | it decided, nobody asked |
| \`agent_proposed_approved\` | it proposed, you approved |

\`--by agent_autonomous\` is your audit list. Decisions made without anyone
asking you. Skim it every few weeks. That is where surprises live.

\`--stale\` shows decisions whose \`reversal_condition\` has become true. Every
record carries a note about what would make it wrong, and this finds the ones
that already are.
`,
  },
  {
    slug: 'rules',
    name: '/hyperpower:rules',
    group: 'Memory',
    note: 'show the rulebook',
    invoke: '/hyperpower:rules --recent',
    when: 'The harness keeps doing something and you want to know which rule.',
    expect: 'The rulebook, or just what changed, or just what is dead weight.',
    body: `
The rulebook is the thing that makes run number forty better than run number
one. Rules get promoted into it when a mistake repeats often enough to count as
a pattern instead of bad luck.

\`--recent\` shows what the promoter added lately and the evidence it used.
Worth a look after a rough week, because a rule added on the back of one weird
run is a rule you probably want to delete.

\`--unused\` lists rules that have prevented nothing in the last twenty runs.

Run \`--unused\` before you raise \`limits.rulebook_max_rules\`. Most of the time
the cap is not the problem, the dead rules are.
`,
  },
  {
    slug: 'gc',
    name: '/hyperpower:gc',
    group: 'Memory',
    note: 'compact the archive',
    invoke: '/hyperpower:gc',
    when: 'The archive got big and search results got noisy.',
    expect:
      'Stale decisions marked, near-duplicates merged, superseded chains folded.',
    body: `
Runs the gardener over the decision archive.

It marks stale decisions, merges near-duplicates, and folds chains where a later
decision superseded an earlier one, so searching does not return five versions of
the same call.

What it deletes is narrow: records that are superseded, about files that no
longer exist, and older than six months. All three, not any one. Everything lives
in git anyway, so a compaction you dislike is one revert away.

Runs only when you ask. It is not going to reorganise your archive in the
background.
`,
  },
  {
    slug: 'scout',
    name: '/hyperpower:scout',
    group: 'Suggestors',
    note: 'log opportunities',
    invoke: '/hyperpower:scout',
    when: 'Right after a run, while the context is still warm.',
    expect:
      'Up to three new entries in `.hyperpower/backlog.jsonl` plus a markdown view.',
    body: `
Every time you work on something you notice three other things that are wrong and
then forget all of them by lunch. This catches those.

Bug risks, tech debt, test gaps, performance, ux, feature ideas. It writes
\`.hyperpower/backlog.jsonl\` and a markdown view you can actually read.

Every entry has to cite evidence from the work that just happened. No evidence,
no entry. That constraint is what keeps it from turning into a wall of generic
advice about adding more tests.

Three new entries per run, maximum. When it spots something already logged it
increments an \`occurrences\` counter instead of adding another row, so the
thing you keep tripping over rises to the top on its own. Free prioritisation.
`,
  },
  {
    slug: 'janitor',
    name: '/hyperpower:janitor',
    group: 'Suggestors',
    note: 'log dependency debt',
    invoke: '/hyperpower:janitor --all',
    when: 'Before a dependency bump, or when a migration has been pending forever.',
    expect: 'Dependency and migration debt written to `.hyperpower/hygiene.jsonl`.',
    body: `
Same idea as scout, pointed at dependencies and migrations instead of code.

By default it looks at the current diff. \`--all\` takes the whole repo, which is
what you want the first time.

It runs the tools your repo already configures. It never installs one, and it
never upgrades anything. So it is safe to run whenever, and the output is a list
for you to act on rather than a surprise lockfile change.
`,
  },
  {
    slug: 'usage',
    name: '/hyperpower:usage',
    group: 'Analytics',
    note: 'pass rates, fix-loop rounds, gate failures',
    invoke: '/hyperpower:usage --since 30d --by stage',
    when: 'The harness feels slower or dumber than it did last month.',
    expect:
      'Run counts, stage pass rates, fix-loop distribution, gate failures, assumption ratio, median duration.',
    body: `
The health check. \`--since\` takes \`7d\`, \`30d\` or \`all\`; \`--by\` groups by
stage, agent, model or run.

Two numbers carry the signal:

1. **Gate failure rate.** How often the build stage produces something that does
   not pass your own checks.
2. **Fix-loop rounds per task.** How many attempts it takes to clear those gates.

If both are climbing, the rulebook has drifted away from the codebase. The code
moved, the rules did not, and the harness is now working from a description of a
repo that no longer exists. Fix is \`/hyperpower:init --refresh\`.

The assumption verified-to-refuted ratio is the other one worth a glance. A lot
of refuted assumptions means it is guessing about your codebase more than it is
reading it.
`,
  },
  {
    slug: 'cost',
    name: '/hyperpower:cost',
    group: 'Analytics',
    note: 'tokens and money by stage',
    invoke: '/hyperpower:cost --since 30d --by model',
    when: 'The bill arrived and you want to know which stage did that.',
    expect: 'Tokens and money grouped how you asked, cache reads shown separately.',
    body: `
Tokens and money, grouped by stage, agent, model or run.

Cache reads are broken out separately rather than folded into the total, because
they dominate the token count and cost almost nothing. Mixed together they make
every number look alarming for no reason.

Prices come from \`pricing.yml\` with a \`last_verified\` date attached. If that
date is old, the output says the price is stale instead of presenting a guess as
a fact. Small thing, but it means you can trust the number or know not to.

Group by stage first. Usually one stage is most of the bill and it is not the one
you assumed.
`,
  },
  {
    slug: 'telemetry',
    name: '/hyperpower:telemetry [status|off|on|purge]',
    group: 'Analytics',
    note: 'control what gets recorded',
    invoke: '/hyperpower:telemetry status',
    when: 'You want to know what is being recorded, or want it to stop.',
    expect: 'What is recorded and where, or the setting changed, or files deleted.',
    body: `
All of this is local. Nothing is uploaded anywhere, by anything, ever.

| Subcommand | Does |
|---|---|
| \`status\` | what is recorded and where it lives |
| \`off\` / \`on\` | stop or start recording |
| \`purge\` | delete everything recorded, and report the file count |

\`status\` is worth running once just to see the file paths. It is all JSONL
inside \`.hyperpower/\`, in your repo, readable with \`cat\`.

Turning telemetry off means \`/hyperpower:usage\` and \`/hyperpower:cost\` stop
having anything to report, which is the trade.
`,
  },
  {
    slug: 'visualize',
    name: '/hyperpower:visualize',
    group: 'Analytics',
    note: 'report what the agents did this session',
    invoke: '/hyperpower:visualize --redact --runs 5',
    when: 'After the work, when you want to see the shape of what happened.',
    expect:
      'A self-contained HTML report in `.hyperpower/reports/`, merged from three local sources.',
    body: `
Builds a visual report from three things it already has: the session transcript,
the workflow journals, and this repo's run journal. Merges them into one
self-contained HTML file.

| Flag | Does |
|---|---|
| \`--list\` | recorded sessions for this repo, newest first |
| \`--session <id>\` | report on an earlier session, by id prefix |
| \`--redact\` | hash file paths before writing |
| \`--runs N\` | harness runs to include. Default 5. |
| \`--out PATH\` | write somewhere other than \`.hyperpower/reports/\` |

Run it after the work, not during. A live transcript is still being appended, so
a report built mid-run is describing something unfinished.

**Before you share the file, read this.** The transcript carries your prompts,
your file paths, and your command lines. Rerun with \`--redact\` first.
Redaction rewrites path-shaped substrings and leaves tool names, gate names and
timings intact, so the report stays readable. It is not a guarantee, because a
free-text command line can contain literally anything.

Nothing is uploaded. It writes a file and stops.

Exit codes: 0 report written, 1 the session recorded nothing, 2 bad input, 78 no
logs found.
`,
  },
  {
    slug: 'status',
    name: '/hyperpower:status',
    group: 'Analytics',
    note: 'what the harness is doing right now',
    invoke: '/hyperpower:status --watch 5',
    when: 'A run is going and you want to watch it from a second session.',
    expect: 'Whether the protocol is active here, and what the running run has done.',
    body: `
A session driving \`/hyperpower:run\` is busy until the run yields. So open a
second session and point this at it. That is the intended way to watch a run, not
a workaround.

It reads the run journal, which is on disk, which is why it works from anywhere.

| Flag | Does |
|---|---|
| \`--watch N\` | reprint every N seconds until the run finishes |
| \`--run <id>\` | one run, by id prefix. Default: the newest |
| \`--last N\` | the N newest runs |
| \`--stop-hint\` | when a run looks stuck, print how to end and redirect it |
| \`--json\` | the facts without the prose |

The stuck signals are mechanical, not a judgement call: the same failure key N
times, a fix loop at round 4 or 5, a blocking gate still failing, a blocking gate
sitting at \`did_not_run\`, or no journal write in ten minutes. They are facts
about the run, not an opinion about whether your approach is any good.

It only reads. It never stops a run. \`--stop-hint\` prints the commands and you
decide.

Exit codes: 0 reported, 1 no run to report on, 2 bad input, 78 no config.
`,
  },
  {
    slug: 'council',
    name: '/hyperpower:council "<question>"',
    group: 'Analytics',
    note: 'independent votes from the owning departments',
    invoke: '/hyperpower:council "should this be a queue or a cron"',
    when: 'A judgement call where you want reads that did not contaminate each other.',
    expect: 'Independent answers from the departments that own the question, then a tally.',
    body: `
Ask a question, get votes from the departments that own it. No voice sees another
voice's answer.

That isolation is the entire design. A voice that reads someone else's answer
first anchors to it, and what comes back looks like consensus but is actually
contagion. Five people agreeing because they each thought about it is worth
something. Five people agreeing because they read person one is worth nothing.

Roster comes from \`departments.yml\`. Six departments, each a pair holding
opposed priors: \`fe-architect\` against \`fe-shipper\`, \`be-architect\` against
\`be-pragmatist\`, \`infra-reliability\` against \`infra-cost\`,
\`product-manager\` against \`product-analyst\`, \`ux-designer\` against
\`ux-reasoner\`, \`reviewer\` against \`skeptic\`.

Two departments, four voices, is the normal size. \`--full\` puts twelve in the
room and costs accordingly, so it only happens if you ask for it by name.

A voice that fails to answer is reported, not quietly dropped from the tally.

No decision record is written until you accept a recommendation. A
recommendation is not a decision.
`,
  },
  {
    slug: 'standup',
    name: '/hyperpower:standup "<question>"',
    group: 'Analytics',
    note: 'the same roster, arguing in rounds',
    invoke: '/hyperpower:standup "ship the migration now or after the release"',
    when: 'The answer depends on how two concerns trade against each other.',
    expect: 'Round one independent, round two rebuttals, then one synthesis.',
    body: `
Council, but the voices read each other.

Round one is independent, same as council. Round two hands each voice every other
position and asks it to answer the strongest argument against itself. Then one
synthesis.

Two rounds, never three. A third round produces restatement at full price.

Roughly twice the cost of a council:

| Room | Voices | Council calls | Standup calls |
|---|---|---|---|
| one department | 2 | ~3 | ~5 |
| two departments | 4 | ~5 | ~9 |
| \`--full\` | 12 | ~13 | ~25 |

Pick standup when the question is a tradeoff and you want to see the argument.
Pick council when you want independent reads and the disagreement itself is the
signal.

Same rule about decision records: nothing is written until you accept something.
`,
  },
  {
    slug: 'humanize',
    name: '/hyperpower:humanize',
    group: 'Quality',
    note: "take the model's fingerprints off the code",
    invoke: '/hyperpower:humanize src/ --all',
    when: 'Before review, on code a model wrote.',
    expect: 'Three passes. Only the comments pass edits, and only after you say yes.',
    body: `
Models leave marks. Placeholders that were going to be filled in later, hedging
comments, a helper invented for one call site, an abstraction built for a second
case that never arrived. This finds them.

This is the one you type. \`sweep\` is the pipeline-internal version and assumes
the slop gate already ran.

Three passes:

1. **Slop code.** Placeholders, deferrals, hedging, stubs, dead paths,
   over-abstraction, wrong-fit code, swallowed exceptions, invented helpers.
   Reports findings and a plan. Applies nothing.
2. **Slop comments.** Enforces *your repo's* comment rule, read from
   \`CODEBASE_RULEBOOK.md\`, then \`CLAUDE.md\`, then \`.claude/rules/\`. This is
   the only pass that edits, and only after showing you a sample and getting a
   yes. It never deletes a comment that explains why something is the way it is.
3. **Repeated code.** Blocks appearing three or more times, parallel functions,
   copy-paste with one thing changed. It recommends collapsing only when the
   copies actually change together. Two copies is a coincidence.

Scope is the current diff. Pass a path to narrow it, \`--all\` for the repo.

It checks for \`antislop\`, \`ai-slop-detector\` and \`jscpd\` first and tells you
which are installed. With none of them it covers the same classes itself and
labels the findings as a model's reading rather than a linter's result. Weaker
claim, stated as one.
`,
  },
  {
    slug: 'sweep',
    name: '/hyperpower:sweep',
    group: 'Quality',
    note: 'layer 2 slop sweep on the diff',
    invoke: '/hyperpower:sweep',
    when: 'Inside the pipeline, after the slop gate. Rarely by hand.',
    expect: 'Findings static analysis cannot reach, on the current diff.',
    body: `
The pipeline-internal half of \`humanize\`. If you are typing a command yourself,
type \`humanize\` instead.

It assumes the slop gate already ran, so it goes straight at what static analysis
cannot see: over-abstraction, code that does not fit the problem, swallowed
exceptions, comments explaining what instead of why, invented helpers that
duplicate something already in the repo.

Scope is the current diff.
`,
  },
  {
    slug: 'review',
    name: '/hyperpower:review',
    group: 'Quality',
    note: 'partition, review, adjudicate',
    invoke: '/hyperpower:review',
    when: 'On a diff big enough that one pass would skim it.',
    expect: 'Findings marked CONFIRMED or PLAUSIBLE, each one adjudicated by a skeptic.',
    body: `
Splits the diff into slices that make sense on their own, reviews each one, then
sends a skeptic at every finding that came back.

Findings land in one of two buckets:

- **CONFIRMED** — traced end to end. The path from cause to effect is in the
  code.
- **PLAUSIBLE** — undecidable from the code alone. Might need runtime context,
  might need to know something about production.

PLAUSIBLE findings are never dropped just because nobody could produce a
reproduction. A real bug that is hard to reproduce is still a real bug, and
quietly filtering those out is how a review tool becomes useless.

The partitioning is what makes this different from asking for a review in one
shot. A forty-file diff reviewed as one blob gets skimmed. Sliced up, each piece
gets actual attention.
`,
  },
  {
    slug: 'eval',
    name: '/hyperpower:eval',
    group: 'Quality',
    note: 'score a prompt change',
    invoke: '/hyperpower:eval --baseline',
    when: 'You changed a prompt and want to know if you made it worse.',
    expect: 'The eval suite runs and prints a release verdict.',
    body: `
Prompt changes feel like improvements. This checks.

It runs the suite and prints a verdict. A prompt change ships only when all three
hold: no blockers, correctness and safety within 0.1 of baseline or better, and
the weighted score beats baseline.

\`--baseline\` records the current scores as the thing to beat.

Fifteen stack-neutral cases ship with the plugin. Add your own after a few real
runs, written against work you have actually read.

Neither \`init\` nor this command generates cases from your commit history, and
that is deliberate. A case lifted from a commit nobody reviewed is a baseline
nobody trusts, and every comparison after it inherits that.
`,
  },
]
