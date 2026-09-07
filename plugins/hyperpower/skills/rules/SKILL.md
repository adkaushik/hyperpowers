---
name: rules
description: Show CODEBASE_RULEBOOK.md - the rules loaded into every run, and the count against limits.rulebook_max_rules. --recent shows what the promoter added and on what evidence. --unused shows rules that have prevented nothing in the last 20 runs. Read only. Run --unused before raising the cap. Use /hyperpower:rules.
---

# Rules

Print the rulebook and the count against the cap. Report nothing that is not in the file.

Read only. This command never adds, edits, or evicts a rule. The rulebook has exactly two writers: the promoter, and `/hyperpower:correct --scope forever`.

The rulebook loads on every run, so its size is a tax on every run. The cap exists for that reason, and `--unused` exists to be run before anyone raises it.

## Config

| Field | Default | Use |
|---|---|---|
| `limits.rulebook_max_rules` | `30` | the cap, printed against the current count |

Read `hyperpower.yml` at the repo root, then `hyperpower.local.yml` over it, field by field. Without either file, use the default and do not ask the user to create one.

If `CODEBASE_RULEBOOK.md` does not exist at the repo root, report `no rulebook - run /hyperpower:init` and stop. Do not create it.

## Two rule formats

Read both. Do not rewrite one into the other.

| Writer | Heading | Provenance | Source label |
|---|---|---|---|
| `init`, or a human | `## R7 - <rule>` | a `Source:` line in the body | `init` |
| `/hyperpower:correct --scope forever` | `## R9 - <rule>` | `source: correction, run 4f2a, step plan, assumption a1` | `correction` |
| promoter | `### R17 - <rule>` | `<!-- hyperpower: added=2026-09-07 source=promoter signal=gate_failed key=generated-import-drift evidence=3 -->` | `promoter` |

A rule with no `Source:` line and no metadata comment was written by hand. Show its source as `hand`. The promoter is not allowed to evict those, so never list one as an eviction candidate.

## Default view

Print every rule. One line each: id, rule text, source, and evidence count when the metadata comment carries one.

```
CODEBASE_RULEBOOK.md - 24 of 30 rules.

R1   Fetch through src/api/client.ts               init       observed, 14 call sites
R7   Do not import from src/generated/             promoter   evidence 3
R9   Settings API returns { items: [] }            correction run 4f2a
R12  Tests live beside the file they test          hand

6 slots free.
```

The five-item cap applies to summaries. It does not apply here. The user asked to see the file, so truncating it to five rules answers a different question. Print all of them.

## `--recent`

Read `.hyperpower/promotions.jsonl`. One line per promoter action. Read nothing else.

| Field | Means |
|---|---|
| `action` | `promoted` or `skipped`, no other value |
| `rule` | the rule id written, `null` on `skipped` |
| `key` | the mistake key that crossed threshold |
| `signal` | `forever_correction`, `assumption_refuted`, `gate_failed`, `finding_confirmed` |
| `evidence` | distinct runs that fired that key |

Show newest first, ten actions maximum, then say how many remain. Show `skipped` lines too. A candidate skipped with `reason: "lost to R09 at cap"` is the evidence that the cap is binding, which is exactly what a reader of `--recent` needs.

```
Promoter, last 10 actions.

2026-09-07  promoted  R17  generated-import-drift  gate_failed  3 runs  demoted R09
2026-09-05  skipped   -    settings-api-shape      assumption_refuted  3 runs  lost to R09 at cap
```

If the file is missing, report `the promoter has written nothing yet`. That is not an error and needs no fix.

The log records intent. `git diff CODEBASE_RULEBOOK.md` records what actually changed. On a disagreement, the file wins.

## `--unused`

A rule is unused when it has prevented nothing in the last 20 runs.

1. Take the 20 most recently modified directories under `.hyperpower/runs/`.
2. For each rule, grep those directories for the rule id token and for the `key` in its metadata comment.
3. Count the distinct runs where either token appears. That is the prevention count.
4. A rule with a count of zero, and no `last_prevented` date inside the window, is unused.
5. Rank the unused rules by `added` date, oldest first.

```
4 unused of 24 rules, over 20 runs (2026-08-02 to 2026-09-07).

R9   Prefer named exports in src/api/       added 2026-05-11  0 preventions
R14  Do not inline SVG over 4kb             added 2026-06-02  0 preventions
```

With fewer than 20 recorded runs, report the actual run count and call nothing unused. The window is the measurement.

A rule that is silently obeyed leaves no trace in a run journal, so a zero count is weak evidence, not proof. `--unused` produces a shortlist for the human to review. Do not evict a rule from this command.

## Before raising the cap

Run `--unused` before raising `limits.rulebook_max_rules`. Raising the cap is the most common way to make the harness slowly worse: every extra rule costs tokens on every run and dilutes the rules that matter.

The exception: raise it only when `--unused` reports zero unused rules over a full 20-run window and `--recent` shows candidates being skipped at the cap. Raise it by five, not by fifty, then re-check `--unused` after 20 more runs.

The human edits `hyperpower.yml`. This command reports the number and stops.

## Do not

- Do not add, edit, or evict a rule. This command is read only.
- Do not create `CODEBASE_RULEBOOK.md`.
- Do not change `limits.rulebook_max_rules`, and do not offer to.
- Do not report any rule as unused on fewer than 20 recorded runs.
- Do not truncate the default view to five rules.
