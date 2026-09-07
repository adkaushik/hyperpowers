# agents

One file per agent role. An agent earns a file when it has a job no existing agent does —
not when a name would be nice.

## Index

| File | Frontmatter `name` | Spawn as | Model | Job |
|---|---|---|---|---|
| `mapper.md` | `mapper` | `hyperpower:mapper` | inherit | Map the affected code read-only, and select the rulebook rules it triggers |
| `planner.md` | `planner` | `hyperpower:planner` | inherit | Turn the map into typed tasks, tests first, with checkable acceptance |
| `designer.md` | `designer` | `hyperpower:designer` | inherit | Write the spec, build the mock, get it locked, write the build brief |
| `builder.md` | `builder` | `hyperpower:builder` | opus | Implement one task from a typed contract, test first |
| `reviewer.md` | `reviewer` | `hyperpower:reviewer` | opus | Review one slice of a partitioned diff, extract undeclared assumptions |
| `skeptic.md` | `skeptic` | `hyperpower:skeptic` | opus | Try to refute one finding. CONFIRMED, PLAUSIBLE, or REFUTED |
| `archivist.md` | `archivist` | `hyperpower:archivist` | haiku | Write decision records and failure events from the run journal |
| `promoter.md` | `promoter` | `hyperpower:promoter` | haiku | Promote repeat failures into `CODEBASE_RULEBOOK.md` |
| `gardener.md` | `gardener` | `hyperpower:gardener` | sonnet | Compact the decision archive on `/hyperpower:gc` |

The frontmatter `name` is the bare role. The plugin supplies the namespace, so every caller
spawns `hyperpower:<name>`. Never spawn a bare `reviewer`: that resolves to a same-named
agent in the user's own `~/.claude/agents/`, which does not know this contract and returns
output the pipeline cannot read. That failure is silent.

## Two planes

`hyperpower:builder`, `hyperpower:reviewer`, and `hyperpower:skeptic` run inside the
pipeline. They are on the critical path and use `models.judgment`.

`hyperpower:mapper`, `hyperpower:planner`, and `hyperpower:designer` are on the critical
path too, and set `model: inherit`. They run on the tier the route contract picked for
their stage, which `task-classes.yml` sets per class. A pinned model would ignore it.

`hyperpower:archivist`, `hyperpower:promoter`, and `hyperpower:gardener` run off the
critical path. They cost a normal run nothing. Two more background agents ship as skills
instead: see `skills/scout/` and `skills/janitor/`.

## Triggers

| Agent | Trigger | Reads | Writes |
|---|---|---|---|
| `hyperpower:archivist` | post-run | `.hyperpower/runs/<run-id>/` | `decisions/`, `mistakes.jsonl` |
| `hyperpower:promoter` | post-run, after the archivist | every `mistakes.jsonl`, then one record on a hit | `CODEBASE_RULEBOOK.md`, `.hyperpower/promotions.jsonl` |
| `hyperpower:gardener` | `/hyperpower:gc` only | `decisions/` | `decisions/` |

Exactly one thing crosses from the background plane into a run: the rulebook.

## Adding one

Check first: does this differ from an existing agent in capability, or only in prompt
wording? If only in wording, extend the existing agent instead.

See [docs/contributing.md](../../../docs/contributing.md) for the writing rules, and
[docs/architecture.md](../../../docs/architecture.md) for where each agent sits.
