# workflows

Deterministic orchestration scripts. Control flow lives in JavaScript, not in a prompt, so
fan-out, dedupe, and tallying happen the same way every run.

Run one with the `Workflow` tool:

```
Workflow({ scriptPath: "${CLAUDE_PLUGIN_ROOT}/workflows/review-sweep.js",
           args: { base: "main" } })
```

## Index

| File | Does | Agent calls | Wall clock |
|---|---|---|---|
| `review-sweep.js` | Partition a diff, review each slice, adjudicate each finding | 1 + slices + findings | 6-15 min on a 20-file diff |
| `council-vote.js` | Four independent votes on one decision, then a synthesis | 5, or 6 with grounding | 4-8 min |

Both are read-only. Neither edits a file, runs the test suite, installs anything, or writes
to the run journal. The caller writes the journal.

## When each is worth its cost

| Workflow | Run it when | Do not run it when |
|---|---|---|
| `review-sweep` | The diff spans more than one file or more than one subsystem | A one-file change with a rulebook precedent. One reviewer costs less and finds the same defects. |
| `review-sweep` | The change crosses an integration seam, so the two sides land in different slices | The diff is generated output or a lockfile bump |
| `council-vote` | Reversing the decision costs more than making it: a schema shape, a public interface, a dependency, a migration order | A later commit can undo it cheaply. One agent is enough there. |
| `council-vote` | Two options both look right and you cannot say why | You already know the answer and want it confirmed. That is a rubber stamp, not a council. |

The cost rule: a workflow earns its place when the structure changes the answer. Parallel
slices find integration seams a single reviewer reads past. Independent votes surface a
dissent a single agent averages away. Neither is worth paying for when one agent would
reach the same result.

## review-sweep.js

Three phases: Partition, Sweep, Verify.

1. Partition. One mechanical agent reads `git diff <base>...HEAD` and `git status`, groups
   the changed files and their blast-radius neighbours into 2 to 6 slices, and reports
   every path it skipped in `left_out`. Generated and vendored trees are skipped.
2. Sweep. One `hyperpower:reviewer` per slice, in parallel.
3. Verify. One `hyperpower:skeptic` per finding, after the findings are deduped by
   `file:line:summary`.

### Args

| Field | Type | Default | Meaning |
|---|---|---|---|
| `base` | string | `main` | The ref the diff runs against |
| `scope` | string or string[] | `null` | Review these paths instead of the diff. Use it for a post-fix re-run. |
| `note` | string | `''` | Free text passed to every agent as context |

### Returns

| Field | Meaning |
|---|---|
| `confirmed` | Findings the skeptic traced end to end, ranked by severity |
| `plausible` | Findings the code alone could not settle. Never dropped for want of a reproduction. |
| `refuted_count` | Findings the skeptic killed |
| `unverified_count` | Findings whose skeptic returned nothing. These were never adjudicated. |
| `partitions` | The slices as reviewed, after any overflow merge |

It also returns `status`, `unverified`, `left_out`, `out_of_scope`, `collateral`, and
`notes`. Each of those exists to stop a silent drop. `left_out` is what the partition
skipped. `unverified` is what no skeptic reached.

`status` is one of `reviewed`, `empty_diff`, `nothing_to_review`, `no_findings`, or
`partition_failed`. The first four are clean early returns. `partition_failed` means the
partition agent returned nothing and no slice was reviewed.

### Why the sweep is a barrier and the verify is not

The sweep uses `parallel()`. The verify uses `pipeline()`. That is the one structural
decision in the script.

`parallel()` is a barrier. Wall clock across the sweep equals the slowest slice, and no
skeptic starts until every reviewer lands. The dedupe needs all findings at once, so the
barrier is real and it is paid on purpose: two reviewers reporting the same integration
seam from opposite sides is the normal case in a partitioned review, and one duplicate
finding costs a whole skeptic.

`pipeline()` has no barrier. Each finding runs adjudicate then merge on its own clock, so
wall clock equals the slowest single chain rather than the sum of the slowest stages.
Switching the verify phase to `parallel()` would add the slowest skeptic's tail to every
other finding and buy nothing.

## council-vote.js

Three phases: Ground, Voices, Synthesize.

1. Ground, optional. A read-only agent pulls the code excerpts the decision turns on. It
   runs when `paths` is non-empty, or when `ground` is `always`.
2. Voices. Four independent schema-forced votes in parallel: `hyperpower:reviewer`,
   `hyperpower:skeptic`, `hyperpower:builder`, and a generalist holding the main agent's
   judgment seat. No voice sees another.
3. Synthesize. One agent turns the ballot into a recommendation with the dissent attached.

The roster is persona-only. There is no external vendor CLI routing and none is planned.

### Args

| Field | Type | Default | Meaning |
|---|---|---|---|
| `question` | string | required | The decision, as one question |
| `options` | array | required, 2 or more | Strings, or `{label, detail}` objects. Voted on as `o1`, `o2`, and so on. |
| `paths` | string[] | `[]` | Starting paths for the Ground phase |
| `ground` | `auto` \| `always` \| `never` | `auto` | `auto` grounds only when `paths` is non-empty |
| `context` | string | `''` | Background the voices should not have to rediscover |

Miss `question`, or pass fewer than two options, and the workflow returns
`status: not_run` with the missing field named. It does not guess the decision and it does
not invent the choices.

### Returns

| Field | Meaning |
|---|---|
| `tally` | Per-option counts and voters, plus `counted`, `abstained`, `dropped`, `leader`, `tied_options`, `margin`, `tie` |
| `abstains` | Every abstaining voice with its reason |
| `dropped` | Every voice whose agent returned nothing |
| `synthesis` | Recommendation, rationale, dissent, open risks, reversal condition, `follows_tally` |
| `voices` | The counted ballots in full |

Abstains and dropped voices are excluded from the denominator and reported by name.
Counting an abstain as a vote would invent a position the voice refused to take. A tie sets
`leader` to null and fills `tied_options`, because naming a leader would hand the
synthesizer a majority that does not exist.

`status` is `decided`, `no_quorum`, or `not_run`. `no_quorum` means no voice cast a
countable vote, so nothing was synthesized.

## Adding a workflow

1. Start the file with `export const meta = {...}` as a pure literal. No variables, no
   template interpolation.
2. Use the same phase titles in `meta.phases` and in every `phase()` call.
3. Default to `pipeline()`. Reach for `parallel()` only when a stage needs every prior
   result at once, and comment why.
4. Never call `Date.now()`, `Math.random()`, or `new Date()`. They break resume and throw.
5. Log what you dropped. A silent cap reads as full coverage.

Read config from inside the agent prompts, not the script. Workflow scripts have no
filesystem access, so `hyperpower.yml` is read by the agents they spawn. Every prompt that
names a config field also names the fallback for when the file is absent.

See [docs/contributing.md](../../../docs/contributing.md) for the writing rules.
