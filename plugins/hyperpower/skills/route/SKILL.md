---
name: route
description: Classify a requirement into a task class, then emit the route contract that /hyperpower:run executes - the ordered stage list and the model tier for every stage in it. Reads task-classes.yml in the plugin. Picks the heavier class when two fit, and says so. Use /hyperpower:route "<requirement>", or let /hyperpower:run call it before it opens the run journal.
---

# Route

Pick one task class. Emit the stage list and the tier per stage. Say why in one sentence.

Route classifies. It never reads the code it is routing, never plans, and never edits a
file.

About ten seconds. Route runs on `models.mechanical`. A cheap classifier is safe here
because the ratchet only ever errs heavy: a wrong call costs one extra stage, never a
skipped one.

## Step 1 - load the inputs

| Input | From | If missing |
|---|---|---|
| requirement | the argument, or the text `/hyperpower:run` passes | stop and ask for it. Do not route an empty string. |
| config | `hp-config --json` on stdout | exit 78 means no `hyperpower.yml`. Say `Run /hyperpower:init.` Stop. |
| classes | `${CLAUDE_PLUGIN_ROOT}/task-classes.yml` | stop. Do not invent a stage list. |

`/hyperpower:run` calls you before `hp-journal new`, because `hp-journal new --task-class`
needs the class you are about to pick. So there is usually no run id yet. Emit
`run_id: null` and let `hp-journal step` stamp the real id when run records the contract.

When run calls you it passes the config it already loaded. Do not call `hp-config` a second
time in that case.

## Step 2 - classify

Four rules, in order. This is mechanical. Do not weigh a class on how interesting it is.

1. Disqualify every class with one true line in its `not_this_class` list.
2. Of the rest, keep every class with at least one true line in its `recognise` list.
3. More than one kept: pick the class latest in the `ratchet` list.
4. None kept: use the `fallback` class.

The ratchet is one way. It never lowers a class.

| Case | Pick |
|---|---|
| `feature` and `ui-feature` both fit | `ui-feature`, and name both in `candidates` |
| `dependency` and `bug` both fit | `bug` |
| nothing fits | `fallback`, and say the requirement matched no class |
| replaying route on an existing run | never lighter than the class in `meta.json` |

Ambiguity is not a reason to ask the human. Ratchet up, declare an assumption, and
continue. The heavier class runs more stages, so the cost of being wrong is one extra
stage, not a missed defect.

## Step 3 - resolve the tiers

Read the chosen class's `tiers` map. Resolve each value against the config.

| Tier | Model |
|---|---|
| `judgment` | `models.judgment` |
| `mechanical` | `models.mechanical` |

There is no third tier. A stage in `stages` with no entry in `tiers` means the class is
malformed. Stop and name the class and the stage. Do not default the tier.

## Step 4 - declare what you assumed

Route infers from a sentence, so it assumes often. Declare each one with the standard
shape. `declared_at` is `route`. `status` is `declared` and you never set another value.

```json
{"id":"a1","claim":"the settings panel is rendered, not a JSON response",
 "source":"inferred","confidence":"medium","declared_at":"route",
 "checkable":"src/settings/","status":"declared"}
```

Declare one whenever a `recognise` line was true on the wording alone and not on anything
you read. Under-declaring here is what makes a wrong class invisible later.

## Step 5 - emit the contract

```json
{"step":"route","run_id":null,"prompt_hash":"sha256:1f0c...","files_read":[],
 "requirement":"add a settings screen with masked preview values",
 "task_class":"ui-feature",
 "why":"the requirement adds a settings screen, which is rendered output a human reads",
 "stages":["understand","plan","design","build","gates","review","fix","render"],
 "skipped":[],
 "tiers":{"understand":"mechanical","plan":"judgment","design":"judgment",
          "build":"judgment","gates":"mechanical","review":"judgment",
          "fix":"judgment","render":"mechanical"},
 "models":{"judgment":"claude-opus-5","mechanical":"claude-haiku-4-5"},
 "review_slices_max":6,"waits_for_human":true,
 "candidates":["feature","ui-feature"],"ratcheted_from":"feature",
 "assumptions":[],"rejected":[],"notes":[]}
```

| Field | Holds |
|---|---|
| `requirement` | the requirement as given, unedited. Nothing else in the journal records the ask. |
| `task_class` | the one chosen class |
| `why` | one sentence, naming the signal in the requirement, not the class definition |
| `stages` | the class's `stages` list, verbatim and in order |
| `skipped` | every stage in `pipeline` not in `stages`, as bare stage names |
| `tiers` | one entry per stage in `stages`. No stage may be absent. |
| `models` | the two resolved model ids, so the journal records what actually ran |
| `review_slices_max` | the class's slice ceiling, verbatim. `null` when review is not in `stages`. Emit the field either way: `schemas/route.json` requires it and types it `integer` or `null`. |
| `waits_for_human` | the class's flag. True only for `ui-feature`, where a human locks the mock. |
| `candidates` | every class that fit, lightest first. One entry when only one fit. |
| `ratcheted_from` | the lighter class the ratchet passed over, or `null` |
| `rejected` | one entry per disqualified class: `{"option":"bug","reason":"..."}` |

`assumptions`, `rejected`, and `notes` are always present, even when empty. An absent
`assumptions` array reads to `/hyperpower:why` as zero assumptions declared.

`files_read` is `[]`. Route reads `task-classes.yml`, which lives in the plugin and not in
the repo. `hp-journal hash` blob-hashes repo-relative paths, so a plugin path would hash as
a missing file and report drift on every later resume.

Do not put `cache_key` on the contract. `hp-journal hash` writes that field, and
`hp-validate` rejects the shape it writes.

`requirement` is the only place the journal records the ask. `meta.json` holds the class,
the base sha, and the tiers, and no field for the requirement. So `schemas/route.json` must
list `requirement` as a string property: that schema sets `additionalProperties: false`, and
`hp-validate route` rejects any field it does not list. Do not drop the field to make the
validator pass, and do not move it into `notes`. The planner and the archivist both read it.

## Step 6 - hand it back

| Caller | Do |
|---|---|
| `/hyperpower:run` | return the JSON. Run validates it, opens the journal, and records it. |
| a human, directly | validate it with `hp-validate route --stdin`, print it, and say it was not written. Do not create a run folder. |

Route never calls `hp-journal new`. Opening a run folder for a classification nobody
executes leaves an empty run in `/hyperpower:usage` forever.

## Step 7 - the human line, with the cost

Say the class, why, the stages, and **how long this is likely to take**. The estimate comes
from this repo's own recorded runs, never from a guess:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/hp-status --json
```

Read `stage_seconds_median` and sum the entries for the stages you selected. Report
`runs_measured` alongside it, because an estimate from one run is not an estimate — say so
rather than presenting it as one.

With no history at all, say "no recorded runs yet, no estimate" and do not invent a number.

```
Route  ui-feature. The requirement adds a settings screen, which is rendered output a human reads.
       feature also fit. Picked ui-feature, the heavier one.
Stages understand, plan, design, build, gates, review, fix, render. Design waits for you.
Est    ~24 min, from 6 recorded runs. plan is the long one at ~13 min.
```

This is progress output, not the render boundary. Do not shape it and do not truncate it.

## Step 8 - stop when the run is expensive

**More than four stages: report, then stop and ask.** Wait for a yes.

```
That is 7 stages, ~24 min. Proceed? Or:
  triage    understand + render only, ~10 min, ends with findings
  narrower  give me a smaller requirement
```

Four or fewer: proceed without asking. Small work must stay frictionless, and a
confirmation on every run trains people to hit yes without reading.

Why the gate exists: the classification lands in about 25 seconds, and the expensive
stages run for twenty minutes after it. Everything needed to decide is known at 25 seconds.
Spending the twenty minutes before offering the choice is the defect this closes.

Two exceptions, both of which skip the gate:

- **A replay.** `/hyperpower:resume` already has a class in `meta.json` and the human
  already chose once.
- **A headless run.** No human can answer, so stalling accomplishes nothing. Proceed, and
  put the class, stage list and estimate in the first line of output so the log shows what
  it committed to.

Offer `triage` by name whenever the requirement reads as a question. A requirement asking
what, why, where or how much usually wants findings, and routing it to `feature` writes a
plan for work nobody has agreed to start.

## Do not

- Do not read the source files to classify. The requirement is the input. Understand reads
  the code, and it runs after you.
- Do not invent a class, a stage, or a tier that is not in `task-classes.yml`.
- Do not pick the lighter class when two fit, and do not pick a lighter class than the one
  recorded in `meta.json`.
- Do not ask the human to pick the class. Ratchet up and declare an assumption instead.
- Do not emit a `stages` list without a `tiers` entry for every stage in it. Run stops on
  that contract, and the stop is the correct behaviour.
- Do not emit `route` inside `stages`. Route already ran.
- Do not invent a duration. Read `stage_seconds_median`, or say there is no history.
- Do not skip the confirmation above four stages because the requirement looks obvious.
  The 25-second classification is exactly when the human can still act cheaply.
- Do not ask for confirmation at four stages or fewer. That is friction with no payoff.
