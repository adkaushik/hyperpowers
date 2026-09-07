# Stage contracts

A stage that fails validation is a hard stop, not a warning.

Kernel part 2 is the typed boundary between stages. Every stage boundary is a JSON Schema
here, and a stage that cannot produce a valid contract fails loudly rather than degrading
into prose the next stage misreads. Prose degrades silently. The next stage reads what it
expected to read, acts on it, and nothing in the output shows the misreading.

Do not repair an invalid contract by hand. Do not continue on a partial one. Do not fall
back to the stage's final message when its contract is rejected.

## Use it

```sh
../scripts/hp-validate build --file .hyperpower/runs/4f2a/build.json
cat build.json | ../scripts/hp-validate build --stdin
../scripts/hp-validate --list
```

| Exit | Means | Do |
|---|---|---|
| 0 | valid | record the contract, run the next stage |
| 1 | invalid, unreadable, or not JSON | hard stop. Print the stage, the violations, the run id. |
| 2 | usage error | hard stop. Nothing was checked. |
| 78 | no schema for that stage, or the schema is unusable | hard stop. Nothing was checked. |

Every violation is printed with its JSON path, not just the first one.

```
invalid: bad.json against schemas/build.json
  $.gates_run                  missing required field
  $.invented_field             field not in the schema
  $.assumptions[0].source      "guessed" is not one of: "rulebook", "inferred", "asked"
3 violations.
```

## The nine schemas

One per stage boundary, in pipeline order. The producer owns the field set. The schema
records it.

| Schema | Written by | Read by |
|---|---|---|
| `route.json` | `skills/route` | `skills/run`, the stage loop |
| `understand.json` | `agents/mapper` | `agents/planner` |
| `plan.json` | `agents/planner` | `agents/designer`, `agents/builder` |
| `design.json` | `agents/designer` | `agents/builder`, the visual gate |
| `build.json` | `agents/builder` | `hp-gates`, `skills/review` |
| `gates.json` | `scripts/hp-gates` | `skills/run`, the fix loop |
| `review.json` | `skills/review` | the fix loop, `/hyperpower:why` |
| `fix.json` | `skills/run` | `/hyperpower:why`, the archivist |
| `render.json` | `skills/run` | `/hyperpower:why` |

Every schema is Draft 2020-12, `"type": "object"`, with a `required` list and
`"additionalProperties": false`. A stage that invents a field fails.

## The envelope

Eight fields may appear on any step contract. Which ones are required is set per stage,
because a stage is held to what its own producer writes.

| Field | Holds | Required in |
|---|---|---|
| `step` | the stage name, as a `const` matching the file name | all nine |
| `assumptions` | the assumption array, present even when empty | all nine |
| `notes` | anything the next stage needs | all but `gates` |
| `files_read` | every path read, so resume can hash them | route, understand, plan, design, gates |
| `rejected` | options considered and dropped | route, plan, design |
| `run_id` | the run folder under `.hyperpower/runs/` | route, gates |
| `prompt_hash` | sha256 of the prompt that produced the contract | route, gates |
| `cache_key` | stamped by `hp-journal`, which owns its shape | never |

`prompt_hash` and `cache_key` are stamped after the stage returns, so a contract handed to
`hp-validate` does not carry them yet. Requiring them would stop every run on its first
stage.

## The assumption record

Every stage contract carries the array. `hp-validate` refuses to load a schema that drops
it, changes its seven fields, or widens `source` or `status`. The record is fixed by the
design, and a per-stage variant is not allowed.

```json
{"id":"a1","claim":"settings API returns a bare array","source":"inferred",
 "confidence":"low","declared_at":"plan","checkable":"src/api/settings.ts",
 "status":"declared"}
```

| Field | Values |
|---|---|
| `source` | `rulebook`, `inferred`, `asked` |
| `confidence` | `high`, `medium`, `low` |
| `declared_at` | any of the nine step names |
| `checkable` | the file or command that settles the claim, or `null` |
| `status` | `declared`, `verified`, `refuted`, `unresolved` |

`status` is `declared` until the gate-time pass re-reads `checkable` and stamps it. Carry
an upstream assumption forward with its original `id`, `claim` and `declared_at`. Do not
restate it as a new one, and do not renumber it.

An absent `assumptions` array reads to `/hyperpower:why` as zero assumptions declared.
Emit `[]`, never nothing.

## Review findings

`findings[].verdict` is the skeptic's tier: `CONFIRMED`, `PLAUSIBLE`, `REFUTED`, or `null`
for a collateral finding no skeptic adjudicated. `REFUTED` belongs in the contract and not
in the rendered report.

An empty `findings` array is valid, and it is a good answer. It means the diff is clean.
Do not pad the list to look thorough. Padding costs a skeptic per fake finding.

The array is never truncated. Cap-at-five applies to the rendered view only, and
`render.json` records `shown` and `total` per section so the view can be checked against
the contract.

## What the validator implements

`hp-validate` is Python standard library only. No `jsonschema`, no PyYAML, no network. It
implements seven keywords:

`type`, `enum`, `const`, `properties`, `required`, `additionalProperties`, `items`.

A schema using anything else is refused at load time with exit 78. That is deliberate: a
keyword the validator silently ignored would be a constraint the author believed was
enforced. Do not add `minLength`, `pattern`, `oneOf`, `$ref`, or `$defs` to a schema here
without adding it to `SUPPORTED` and to `validate()` first.

`hp-validate` also refuses a schema that breaks a kernel invariant:

1. Root is not an object, has an empty `required`, or leaves `additionalProperties` open.
2. `step` is missing from `required`, or its `const` disagrees with the file name.
3. `assumptions` is missing from `required`, or its record is a variant.

## Changing a schema

1. Change the producer first. The schema records what a stage writes; it does not decide it.
2. Add the field to `properties`, and to `required` when the producer always writes it.
3. Keep `additionalProperties: false`. Never open it to make a contract pass.
4. Run `../scripts/hp-validate --list`. It loads all nine and fails on the first unusable one.
5. Validate a real contract from a run journal, not a hand-written sample.

Never widen an enum to make one failing contract pass. The failure is the boundary working.

## Known disagreements

These schemas match the producers. Where two committed files disagree, the schema follows
the one that writes the contract, and the disagreement is listed here rather than hidden.

| Disagreement | Schema follows |
|---|---|
| `confidence`: `docs/design-spec.md` shows only `low` and enumerates nothing; `agents/builder.md` and `agents/mapper.md` enumerate `low, medium, high` | the three-value list, because `agents/designer.md` and `skills/route` both emit `medium` |
| `assumptions` in `review.json`: the example in `skills/review/SKILL.md` omitted it | the design spec, which says every step contract carries the array. The example now emits `assumptions: []`. |
| `notes` and `rejected` in `gates.json`: the envelope in `skills/run/SKILL.md` lists both, `scripts/hp-gates` writes neither | `hp-gates`, which is the executable producer |
| `tests.first_run` in `build.json`: `agents/builder.md` fixes the value at `failed` | `failed` as the only value. A test that passed on its first run does not test the change, so fix the test rather than recording a pass. |
| `review_slices_max` in `route.json`: `skills/route/SKILL.md` and `task-classes.yml` both say Route omits the field when the class value is `null`, which is the `trivial` class | the producer. The field is optional, and an integer whenever Review is in `stages`. Requiring it stopped every `trivial` run at its first stage. |

## Resolved: `task_class`

`plan.json` once enumerated `bugfix, feature, refactor, migration, chore`. Three of those
five appeared nowhere else in the tree, and five of the seven real classes failed
validation, so a `bug`, `dependency`, or `ui-feature` run stopped hard at Plan.

`plan.json` now carries the seven classes in `task-classes.yml`, which is what
`route.json`, `skills/route/SKILL.md`, and `agents/planner.md` already named. The planner
is told not to change `task_class` and not to name a class outside `task-classes.yml`, so
that list is the only one it can emit. Route writes the same value into `meta.json`, and
`/hyperpower:usage` groups by it, so the three now agree.

`hp-selfcheck task-classes` compares the three lists on every run and fails when they
drift apart again.
