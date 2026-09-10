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

### Departments

Pairs holding opposed priors. Two voices with the same prior produce one answer twice, so
each pair is defined by what it argues *against*. `/hyperpower:council` counts them;
`/hyperpower:standup` lets them read each other and respond. Roster and attendance live in
`departments.yml`.

| File | Frontmatter `name` | Spawn as | Model | Argues for |
|---|---|---|---|---|
| `fe-architect.md` | `fe-architect` | `hyperpower:fe-architect` | inherit | The code someone maintains in a year |
| `fe-shipper.md` | `fe-shipper` | `hyperpower:fe-shipper` | inherit | A user seeing this sooner |
| `be-architect.md` | `be-architect` | `hyperpower:be-architect` | inherit | Data still correct after the third incident |
| `be-pragmatist.md` | `be-pragmatist` | `hyperpower:be-pragmatist` | inherit | The smallest thing that is actually correct |
| `infra-reliability.md` | `infra-reliability` | `hyperpower:infra-reliability` | inherit | Being able to undo this at 3am |
| `infra-cost.md` | `infra-cost` | `hyperpower:infra-cost` | inherit | The bill that arrives every month |
| `product-manager.md` | `product-manager` | `hyperpower:product-manager` | inherit | The version that reaches a user soonest |
| `product-analyst.md` | `product-analyst` | `hyperpower:product-analyst` | inherit | Finding out before building |
| `ux-designer.md` | `ux-designer` | `hyperpower:ux-designer` | inherit | The flow a user actually walks |
| `ux-reasoner.md` | `ux-reasoner` | `hyperpower:ux-reasoner` | inherit | The version that asks least of the user |

`reviewer` and `skeptic` above are the sixth pair. They already worked this way before the
departments existed, and they are the reason the shape is worth repeating.

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
